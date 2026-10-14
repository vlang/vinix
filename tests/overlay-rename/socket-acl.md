# UNIX socket backing ACLs and metadata

Replacing a filesystem socket inode with its transport resource hid the inode's
permission snapshot callback. A root-created socket could inherit an ACL denying
UID 1000 while writable other bits let that account connect. Permission checks
must honor the matching named ACL entry and mask, and chmod must keep the ACL
consistent with mode bits. See [POSIX ACL access and mode semantics](https://man7.org/linux/man-pages/man5/acl.5.html)
and [UNIX pathname permissions](https://man7.org/linux/man-pages/man7/unix.7.html).

The UNIX resource now forwards permission snapshots, chmod and metadata
persistence to the retained backing resource. Anonymous, accepted and abstract
sockets keep their existing local metadata behavior. Successful chmod mirrors
the backend's mode and change time; ownership/timestamp persistence transfers
only those metadata fields and restores staged backing fields on failure.
Inode identity and link count remain owned by namespace operations.

Backing callbacks can wait on storage. The VFS pins both the resolved node and
resource under its writer lock before authorization. Connection/datagram
callers retain the returned resource through the entire operation and every
wait. Abstract lookup retains under its registry lock. Pathname chmod, chown
and timestamp changes retain node/resource guards through rollback and
notification. Final releases run outside the writer lock, including refusal of
non-socket resources whose cleanup may remove a device name.

The V probe runs as UID/GID 1000 with supplementary groups cleared. Root stages
six sockets on each selected backend using inherited default ACLs:

- A named UID denial overrides writable other bits for stream, record and
  datagram lookup. Refused connections leave backlogs empty; an addressed empty
  datagram is also refused without publishing a receive record.
- A named UID grant permits a real stream connection and transfer despite
  mode bits denying other accounts. chmod masking that grant refuses access.
- Changing ownership to UID/GID 1000 makes the owner's permissions authoritative,
  preserving the named entry. Explicit timestamps are staged on that inode.
- On direct ext2 and overlay, an out-of-range owner update fails with
  `EOVERFLOW` and preserves owner/group/mode before the ordinary-account checks.
- After closing the transports and remounting ext2 read-only, both direct and
  upper-layer sockets retain UID/GID 1000, nlink 1, mode 0622, their named ACL,
  and the explicit access/modification times.

Repeated direct/ext2-upper socket cycles now inherit ACLs, exercise permission
snapshots and chmod, then unlink/replace/close their inodes. The existing
descriptor, SCM_RIGHTS, mode, peer-credential and transport checks remain active.

On 14 October 2026, results were retained under
`build/development17-20261013`:

| State | Result |
| --- | --- |
| `socketacl-arm-before-e`, `socketacl-x86-before-e` | Previous ownership kernels connect despite the named UID denial; assertion 546 fails with result 0. |
| `socketacl-arm-basic-b`, `socketacl-x86-basic-b` | Expanded native tmpfs probe passes. |
| `socketacl-arm-linux-d`, `socketacl-x86-linux-d` | The exact corresponding native probe ELF passes in Linux 6.12.51-0-virt. |
| `socketacl-arm-after-b`, `socketacl-x86-after-b` | Tmpfs/direct-ext2/overlay ACL checks, two batches of 32 socket cycles per disk backend, rollback and read-only remount pass. |
| `socketacl-arm-all-b`, `socketacl-x86-all-b` | Existing atomic replacement, backend failure, mixed lifetime, whiteout, opacity and persistence checks pass. |

All 18 ARM slab classes plus the large count, and all 14 x86 classes plus the
large count, remain equal between batches; writes-after-free counters stay zero.
All four final volumes pass read-only `e2fsck -f -n`. The allocation audit
retains the exact same 182 baseline file/kind findings without allowlist changes.

| Input | SHA-256 |
| --- | --- |
| Fixed ARM kernel | `e7fd82818a674f661a0f20f0e964c87dbaf3075d86bfce69b0855180434924ba` |
| Fixed x86 kernel | `ac05a50e5eb8b82d993e4aaaea815c2ba8bf864eb2a6c1cf25bdcc06dfc96623` |
| ACL fixture | `a62ff505b804869fe156c8fa3f5789a74d505e5e3dd3672728238564aa406ba1` |
| Core fixture | `15ee8317e9671cb902be57b82d982b400e552be895c6afaafad9281d9531aac7` |
| Socket fixture | `100a04617ef914cd3f40139c66ccc62139a2fb6ff4a2e1a6ddb732614baee606` |
| Shared ARM native/Linux probe | `cd9deef6805615d7b44735480be879f00a60beaae1b1beac471fe978314bc410` |
| Shared x86 native/Linux probe | `e21b82c9a4d78c063c0c0d151fd6e1d57721f102b7ed170d829054ed8fdef881` |

Builds use the isolated worktrees and link seed 17. Shared compiler cleanup and
subsequent executable drift were detected during qualification. A private clean
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c` source tree and the separately preserved
`v-socketacl-pinned` executable (SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`) reproduce both
reviewed C outputs. The comparison relocates exactly one executable-path literal
in the unused generated C `main`; all other bytes match. That `main` is absent
from the production kernel. Reproduction is retained in
`socketacl-c-reproduction-final.log`; the pinned audit is
`socketacl-allocation-audit-c.log`.

`socketacl-evidence.v` verifies source/receipt hashes, controls, all allocation
samples, four filesystem checks, reviewed C hashes and native/Linux probe
identity. Its assertion-enabled run is `socketacl-evidence-final.log`.
`socketacl-lifetime-review.md` approves the source and both generated outputs.
Only the three known concurrent per-open creation bookkeeping differences are
normalized in VFS. Repeat cases using [the controller instructions](README.md).

The first disk runs (`after-a`) ended before the final root-owned fixtures'
chained retirement completed; their filesystem checks detected ten pending
inode/EA allocations. The final fixture waits 25 seconds after those closes
before remount. Earlier runs, failed builds and compiler-drift/reproduction
checks remain separate from the final passing evidence. Unmount draining and
crash recovery while deferred cleanup is pending are not qualified here.

Direct xattr reads/changes while the live socket replaces its filesystem
resource remain unsupported. Bound transport/path metadata still share Vinix's
resource representation; this does not qualify Linux sockfs separation. Generic
metadata staging still has its existing concurrent mutation/rollback limitation.
Broader capability/MAC/namespace matrices, crash consistency and full OCI or
rootless-runtime acceptance remain open.
