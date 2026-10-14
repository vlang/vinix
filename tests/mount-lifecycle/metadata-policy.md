# Mode and ownership attachment policy

Mode and ownership syscalls now check the attachment used by the path or
descriptor, together with the inode's backend read-only state. The previous
inode-only check chose the latest bind alias: a read-only alias denied writes
through its writable source, while a writable alias could authorize changes
through the read-only source. Detached or retired descriptions could also lose
their read-only protection when the inode had no matching active mount.

`fchmodat` and pathname `fchownat` snapshot their starting directory and mount
together and resolve with the existing `retain_path_target_on_mount` helper.
Their existing node/resource pins remain held through mutation and notification,
and are released by the same deferred cleanup. `fchmod`, `fchown` and empty-path
`fchownat` check the saved mount on their pinned description. Backend read-only
state, capabilities/ownership, MAC checks and immutable attributes remain in
place; the guard precedes overlay copy-up and persistent metadata changes.
No new ownership transfer, resource pin, heap allocation or interface box is
introduced. These are permission-policy changes to already pinned operations.

The mount checks correspond to the path-based write checks in
[Linux v6.12 mode and ownership operations](https://github.com/torvalds/linux/blob/v6.12/fs/open.c).
The qualification uses read-only data descriptors; metadata changes do not
require the descriptor itself to have been opened for data writes.

Use `--case metadata` or `mp-0` through `mp-6`. Each case runs in a child with a
private mount namespace and an eight-byte tmpfs marker.

| Case | Routes exercised |
| --- | --- |
| 0 | Writable source/read-only directory bind, followed by reversed flags |
| 1 | Local descriptions in a copied namespace, both flag directions |
| 2 | Chroot root and cwd using separate aliases of one inode, both directions |
| 3 | A regular-file bind and its original pathname, both directions |
| 4 | Held directory description through a read-only bind after lazy detach |
| 5 | Descriptions retained after a worker's private namespace retires |
| 6 | Read-only source/writable bind established before the first operation |

Each pair repeats 200 iterations of `fchmodat`, `fchownat`, `fchmod`, `fchown`
and `fchownat(AT_EMPTY_PATH)`. Directory cases also exercise symlink no-follow
`fchownat`. Read-only attempts must return `EROFS` without changing mode, UID,
GID, size, type or inode identity. Successful operations change mode to 0640 or
owner/group to 1/2 and verify those values with `fstat`, then restore 0600 and
0/0 through the writable attachment. No-follow ownership changes affect the
symlink while retaining the target's identity and ownership. Marker data stays
intact. UID/GID 1000 must receive `EPERM` through the writable route and `EROFS`
through the read-only route, preserving all metadata. File-bind and retired
namespace cases qualify regular-file operations without a symlink.

All eleven copied V fixture sources, generated C, probe/kernel ELFs, boot image,
serial log and hash receipt are retained in fresh native output directories.
The exact native probe ELF runs the portable suite on Linux 6.12.51. Isolated
kernel builds start from the frozen `mount-truncate` baseline and apply only
the owned VFS change; concurrent sessions' checkout changes are excluded.

Evidence from 2026-10-15 is under `build/development17-20261013`:

| States (both `arm` and `x86`) | Result |
| --- | --- |
| `mount-metadata-*-mp-0-before-b` | Previous kernel rejects `fchmodat` through the writable source when its bind alias is read-only. |
| `mount-metadata-*-mp-{4,5,6}-before-b` | Previous kernel accepts `fchmodat` through detached, retired and live read-only routes. |
| `mount-metadata-*-all-after-a` | Corrected kernel passes the full native suite and all seven metadata cases. |
| `mount-metadata-*-linux-a` | Linux 6.12.51 passes the portable suite using the same probe ELF. |

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `ec6673bdf11d7b50411fef846587123fddb6ffe7ae7cc8f44522d84fa6df3840` | `cc3fee0760df7d7a17f4d7bdc66936032f44224943ba3ff35e62bb462bf943ba` |
| x86_64 | `e3d9f9245f49ea9c00f0712d65299556c42ff42be7206219a45c01babcb48f6d` | `cbaaea80894dd3b9005586978c2c5e5840dab62726d0f3e5b80cf265291c0fb4` |

Each `mount-metadata-{arm,x86}-input` freezes the kernel ELF, generated C,
VFS/socket-lookup sources and complete source manifest. Builds use pinned V
source `f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link shuffle seed 17. Native ARM uses HVF/four CPUs, x86 uses TCG/two CPUs;
Linux references have two CPUs. Networking is disabled. Full native timeout
is 300 seconds; Linux timeout is 180 seconds.

`mount-metadata-evidence-a.log` audits every receipt/artifact/source hash,
the exact owned VFS delta against the previous baseline, all case markers
and shared ELF identity. Generated C uses stack mount contexts, keeps the
existing cleanup on every post-retention return and places attachment,
authorization and attribute checks before copy-up or metadata mutation.
The descriptor/target cleanup and mount-policy/retention helper implementations
are unchanged. No new direct heap allocation or promotion appears in these
four syscalls. Per-architecture `metadata-c-audit.txt` records the return counts.

Initial `mp-0-before-a` states retain image/assembler failures during host disk
exhaustion. Fresh `before-b` controls reproduce the runtime errors with the
final probe. Verified owned build caches were pruned; frozen sources, C, ELFs,
stack-usage outputs, receipts and completed artifact hashes remain intact.

The subsequent [timestamp checks](timestamp-policy.md) extend route-based policy
to `utimensat`, descriptor/empty-path updates and the older timestamp APIs.

Concurrent remount/namespace switching, inherited foreign-description policy,
existing data writers during remount, O_PATH metadata semantics, xattrs,
inode flags, overlay metadata integration, readonly disk backends, mount
reclamation and complete OCI/rootless runtime acceptance remain open. These
checks do not measure allocation-flat metadata loops. Roadmap section 17
remains in progress.
