# UNIX pathname transport permissions

UNIX socket lookup checked pledge/unveil policy and directory traversal but
skipped write permission on the resolved socket inode. An ordinary account could
connect to a socket with mode 0000; named datagram sends used the same unchecked
lookup. [Linux UNIX socket permissions](https://man7.org/linux/man-pages/man7/unix.7.html)
require write access for these pathname operations.

The shared lookup now calls the existing effective-credential DAC/MAC check
after policy validation and before returning the endpoint. Refusal occurs before
changing a datagram peer, queuing a connection or publishing a record. Abstract
names and sends through existing connections do not enter this filesystem check.
Independent review approved the V source and both generated C outputs. The
existing pathname/FD/interface/scratch cleanup unwinds on failure; permission
scratch is freed on every return, and no borrowed pointer escapes.

The V fixture runs as UID/GID 1000 with supplementary groups cleared. Every
persistent socket cycle includes:

- Stream connections refused with `EACCES` for modes 0000, 0400 and 0100, leaving
  the client unconnected and the listener backlog empty. Mode 0200 permits a
  real connection, accept and transfer.
- A record socket refusing mode 0400, permitting mode 0200, then transferring a
  record over the established connection after chmod to 0000.
- Datagram `connect`, addressed `sendto`, `sendmsg`, `sendmmsg` and empty-record
  sends refused for modes 0000, 0400 and 0100. The receiver stays empty, its byte
  sentinel and failed batch length remain unchanged. Mode 0200 permits addressed
  sends and a connection.
- A datagram reconnect refused after chmod to 0000, preserving the prior target:
  a connected write still reaches it, while another addressed send is refused.
- Abstract datagram bind/connect/transfer with umask 0777, then complete cleanup.

On 14 October 2026, results were retained under `build/development17-20261013`:

| State | Result |
| --- | --- |
| `socketperm-arm-before-a`, `socketperm-x86-before-a` | Previous pathname-open kernels accept a mode-0000 stream connection; assertion 486 fails with result 0. |
| `socketperm-arm-basic-a`, `socketperm-x86-basic-a` | Expanded disk-free probe passes in native Vinix. |
| `socketperm-arm-linux-a`, `socketperm-x86-linux-a` | The exact same native probe ELF passes in Linux 6.12.51-0-virt. |
| `socketperm-arm-after-a`, `socketperm-x86-after-a` | Extended direct-ext2/overlay socket checks and clean remount pass; two batches of 32 cycles per backend retain equal live allocation counts. |
| `socketperm-arm-all-a`, `socketperm-x86-all-a` | Existing atomic replacement, rollback, mixed lifetime, persistence, whiteout and opacity regressions pass. |

All 18 ARM slab classes plus the large count, and all 14 x86 slab classes plus
the large count, remain equal between batches; writes-after-free counters stay
zero. Mixed-lifetime samples also stay flat. All four final volumes pass
read-only `e2fsck -f -n`. The allocation audit still has the same 182 baseline
file/kind findings, with no allowlist expansion.

| Input | SHA-256 |
| --- | --- |
| Fixed ARM kernel | `8d8d7cb45ab246c2d8d999f5d6f8aeb30ded27495168e24e1f76251df67da0ae` |
| Fixed x86 kernel | `4a3b6e398bd3863cf69db57b8d12ac62a0a8be2059341e6aa98bb2e8f31f4634` |
| Permission fixture | `a721deb181a35451ae87ebafa85ec8898e9c6aeda533d058a7b168451e4801e3` |
| Socket fixture | `f9e72fe6d41cda5b39f563e9695b4477424c69718c81db92fd91f8b395014348` |
| Shared ARM native/Linux probe | `fb5a497f400fb19fe4c655779b9ccf120e8080d8d2a88d661b8cab1240c6e42d` |
| Shared x86 native/Linux probe | `5957287c1d0dcac9fcce7c9114a0bb0e8d88e9101f8cbe33cb4e4b08b0e3a9e9` |

Builds use the isolated worktrees, preserved `f6358ec` V compiler and link seed
17. `socketperm-evidence.v` is an assertion-enabled V checker for source/receipt
hashes, controls, complete allocation samples, native/Linux probe identity and
filesystem checks; its result is `socketperm-evidence-final.log`. Only the three
known concurrent per-open creation bookkeeping differences are normalized in
VFS. Review is retained in `socketperm-lifetime-review.md`. Repeat these cases
using [the controller instructions](README.md); Linux reference kernels and boot
policy match [the preceding pathname-open qualification](socket-open.md).

This qualified the tested inode-mode permission paths. At this stage UnixSocket
did not forward permission snapshots to its physical backing resource. The
subsequent [backing ACL correction](socket-acl.md) covers inherited ACL permission
snapshots and metadata updates. Direct socket xattr mutation remains open.
Broader credential/capability/MAC policy
matrices, network namespace isolation, full OCI/rootless-runtime acceptance and
complete server qualification also remain open.

The subsequent [descriptor ownership correction](socket-ownership.md) extends
the fixture with creator/acceptor metadata and inherited-listener checks. The
hashes above identify the preceding pathname-permission qualification.
