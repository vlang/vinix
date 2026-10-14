# Pathname truncation attachment policy

`truncate(path, length)` now preserves the resolved mount context and requires
that attachment and its backend to be writable before overlay copy-up or a
size change. The previous implementation checked the file's permissions and
attributes but did not check read-only mount policy. Direct truncation could
therefore bypass the read-only bind that refused writable and truncating opens.

The syscall snapshots the starting directory and mount together. A new
`retain_path_target_on_mount` helper resolves under the VFS lock, retains the
resolved node and its resource, then releases the lock. The syscall releases
both references after its complete operation or any subsequent failure. The
helper leaves the existing `PathTarget` layout unchanged; this truncation
change leaves metadata callers unchanged. The subsequent
[mode and ownership checks](metadata-policy.md) reuse that helper.
Mount entries remain permanent; the resolved cursor needs no separate owner.
The read-only check precedes attribute checks, copy-up and `grow`. Existing
MAC/pledge/unveil checks, write permissions and immutable/append-only checks
remain in place. The lifetime change is independently reviewed against the
frozen sources and generated C on both architectures.

This follows the pathname mount-write check and retained path in
[Linux v6.12 `vfs_truncate` and `do_sys_truncate`](https://github.com/torvalds/linux/blob/v6.12/fs/open.c).
Descriptor truncation is a separate operation and remains outside this change.

Use `--case truncate` or `tr-0` through `tr-5`. Each case runs in a child with
a private mount namespace and an eight-byte tmpfs marker.

| Case | Routes exercised |
| --- | --- |
| 0 | Writable tmpfs source and read-only directory bind, then reversed flags |
| 1 | Local paths after copying that mount namespace, with both flag directions |
| 2 | Chroot root and cwd through different aliases of the same inode, both directions |
| 3 | A regular-file bind and its original pathname, both directions |
| 4 | Read-only bind reached through a held directory description after lazy detach |
| 5 | Writable/read-only descriptions left by a thread after its private namespace retires |

Each pair repeats shrink-to-zero, growth to 32 bytes and same-size eight-byte
requests 200 times. Read-only requests must return `EROFS`, retaining the
marker's size, contents and device/inode through both aliases. Writable requests
must succeed and report the requested size. A writable open then restores the
marker before the next check. Negative lengths remain `EINVAL`; directory
targets remain `EISDIR`, even through a read-only attachment. A UID/GID 1000
child receives `EACCES` for the writable marker's mode 0600 and `EROFS` through
the read-only route, without changing data. The retired-namespace worker uses
explicit stack storage until `pthread_join`; its open descriptions remain in
the shared descriptor table for the caller's observations.

Fresh native result directories retain all ten V fixture files, generated C,
the probe ELF, kernel ELF, image, serial log and a hash receipt. The controller
checks every source/artifact hash before probe reuse. The same native probe ELF
runs the portable suite on Linux 6.12.51. Qualified kernels are isolated builds
of the frozen `mount-bindpolicy` baseline plus the VFS/socket-lookup changes;
concurrent sessions' checkout edits are excluded.

Evidence from 2026-10-14 is under `build/development17-20261013`:

| States (both `arm` and `x86`) | Result |
| --- | --- |
| `mount-truncate-*-tr-{0,4}-before-b` | Previous kernel accepts truncation through live and detached read-only aliases. |
| `mount-truncate-*-tr-5-before-c` | Previous kernel accepts truncation through a retained read-only description after namespace retirement. |
| `mount-truncate-*-all-after-a` | Corrected kernel passes the full native suite and all six truncation cases. |
| `mount-truncate-*-linux-a` | Linux 6.12.51 passes the portable suite using the same probe ELF. |

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `5e267f79932ffed72f6e618f1da0eeb3712eed3a721f844e5f930406d884166e` | `8268dca9ff29af3089551638df7b69237ef3cc5474d95cd78dde16d4aaec56a2` |
| x86_64 | `ea634fb3b715d84333751e0d3d9334b25e6e1b24fd6a54cc586546a1a8562f08` | `21242f1e9f148585a48628058a354b9c9f11e495b6e7740a70a714795596cbc4` |

Each `mount-truncate-{arm,x86}-input` freezes the kernel ELF, generated C,
VFS/socket-lookup sources and complete source manifest. Builds use pinned V
source `f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link shuffle seed 17. Native ARM uses HVF/four CPUs, x86 uses TCG/two CPUs;
Linux references have two CPUs. Networking is disabled. Native timeout is
300 seconds; Linux timeout is 180 seconds.

`mount-truncate-lifetime-review.md` records the independent review of frozen
VFS source `2cb4c169a7a9e4edef559e6899364328d313ea325f2c69ca405ab812aa44028e`,
socket lookup source `1b94f65958e8724f6223bbd10bfaf2e00eb2f5215efd4ddf2d7e21b63123f5d8`
and both generated C files. The evidence audit checks the review pins, every
receipt/artifact/source hash, the exact owned VFS delta against the prior
baseline, all case markers, shared ELF identity, authorization/retention order
and cleanup on all nine post-retention return paths without new heap promotion.

Initial `before-a` states retain the guest format compilation
failure; the final probe uses the LP64 `long` format for its signed length.
`tr-5-before-b` states retain failed image construction during host disk
exhaustion. Fresh `tr-5-before-c` states reproduce the intended runtime control
with the final probe. Owned object caches were removed and completed images
were converted to independent APFS clones; frozen source/C/ELF inputs, stack
usage, receipts and artifact hashes remain intact.

Concurrent remount/namespace switching, full overlay truncate qualification,
descriptor truncation, allocation-flat stress and full OCI/rootless acceptance
remain open. These checks do not qualify mount reclamation or readonly disk
backends. Roadmap section 17 remains in progress.
