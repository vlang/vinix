# UNIX descriptor ownership

Unnamed UNIX sockets and socketpairs captured creator credentials for peer
reporting but left stat UID/GID at zero. Ordinary users saw root-owned
descriptors and their own `fchmod()` failed with `EPERM`. Accepted endpoints also
kept zero metadata ownership. Linux initializes socket inode ownership from
[the calling filesystem credentials](https://github.com/torvalds/linux/blob/v6.12/net/socket.c#L594)
and allocates a new socket inode during acceptance.

Vinix now initializes unnamed and paired stat UID/GID from its existing effective
credential model. Acceptance assigns the accepting account's effective UID/GID
before boxing the resource and publishing its FD. Captured listener and peer
credentials retain their connection-time identities. Independent review checked
source and both generated C outputs: only scalar assignments were added, with
no new allocation, boxing or reference changes. The existing queue release keeps
the pending endpoint alive until descriptor publication.

The V probe runs as UID/GID 1000 with supplementary groups cleared. It checks
`fstat` ownership and successful `fchmod(0600)` while preserving socket type and
ownership on unnamed streams, both socketpair ends, accepted stream/record sockets
and abstract datagram sockets. Pairs and accepted descriptors retain the expected
peer credentials and transfer real data after these changes. An abstract socket
also accepts traffic after descriptor chmod to 0000.

Root prepares a mode-0666 listener and gives its FD to the worker through fork.
After dropping credentials the worker connects and accepts it. The accepted
descriptor belongs to UID/GID 1000 and permits its owner's chmod; its peer is the
UID-1000 client. The client still reports the root listener's captured UID/GID 0,
and real data crosses the connection. Both processes close their descriptor
references, and root removes the private pathname.

Results on 14 October 2026 are retained under `build/development17-20261013`:

| State | Result |
| --- | --- |
| `socketowner-arm-before-c`, `socketowner-x86-before-c` | Previous permission kernels report UID/GID 0 and return `EPERM` for the ordinary creator's chmod; assertion 530 fails. |
| `socketowner-arm-basic-a`, `socketowner-x86-basic-a` | Expanded disk-free ownership and inherited-listener probes pass in native Vinix. |
| `socketowner-arm-linux-a`, `socketowner-x86-linux-a` | Each exact native probe ELF passes in the Linux 6.12.51-0-virt reference. |
| `socketowner-arm-after-a`, `socketowner-x86-after-a` | Extended direct-ext2/overlay socket checks pass with flat repeated live allocations and clean remount. |
| `socketowner-arm-all-a`, `socketowner-x86-all-a` | Existing atomic replacement, rollback, mixed lifetime, persistence, whiteout and opacity regressions pass. |

Two batches each run 32 socket cycles per backend, including paired, record and
datagram ownership/permission checks. All 18 ARM slab classes plus the large
count, and all 14 x86 slab classes plus the large count, match between batches.
Mixed-lifetime samples also stay flat; writes-after-free counters remain zero.
All four final volumes pass read-only `e2fsck -f -n`. The allocation audit retains
the same 182 baseline file/kind findings; its allowlist was not expanded.

| Input | SHA-256 |
| --- | --- |
| Fixed ARM kernel | `88210753d1e76042ed036ea07ba12294a197117e33b3d637711562e2d0dfb6e4` |
| Fixed x86 kernel | `c26e8ec299b52c90854871decccc30b2be17c38d065e312e607ffa7cc6711b61` |
| Ownership/permission fixture | `da30e1064f0016ea2a7354cc1fa703f178c61bc6eacd18f1da3fe447fcabce50` |
| Socket fixture | `4714837a8866a86294173b57d4869eca558cabde81af6ace3ec7d83b01b36f22` |
| Core fixture | `d7b99807f8e8dbb61214d8fccdfdb3c7df67aaa2dffd96ce3edf35518833fd49` |
| Shared ARM native/Linux probe | `0df24cd7b1aa6b004329990c4ac4d6e441dfad11a8b9aec5cc13d5e29bac657a` |
| Shared x86 native/Linux probe | `b34bdb223a37cbc9bb8f604d8551c51280cd2f6c9a4985332c73319a3e12936b` |

Builds use the isolated worktrees, preserved `f6358ec` V compiler and link seed
17. The assertion-enabled `socketowner-evidence.v` verifies source/input hashes,
controls, complete allocation samples, identical native/Linux probes and
filesystem checks. Its result is `socketowner-evidence-final.log`; review is in
`socketowner-lifetime-review.md`. Only the three known concurrent per-open
creation bookkeeping differences are normalized in VFS. Earlier control variants
remain separate from the final fixture. Repeat these cases using
[the controller instructions](README.md).

This qualifies the tested effective-credential metadata paths. Distinct filesystem
UID/GID support, broader credential/capability policy matrices, physical socket
ACL forwarding, network isolation and full OCI/rootless/server acceptance remain
open. The reference kernels and boot policy match the preceding
[pathname permission qualification](socket-permissions.md).
