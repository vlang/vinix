# Mount attachment identities and retained read-only policy

Unmount, remount and move must change an active attachment in the caller's
mount namespace. A held directory fd or cwd can still name a detached mount,
or a mount created only in another namespace. The former policy lookup returned
that raw retained/foreign record when its stable ID was absent from the caller's
table. Using it for attachment changes allowed a second unmount to clear the
replacement mountpoint, a remount to change detached policy, and moves to alter
foreign records or attach into detached/foreign directories.

`attached_namespace_mount` requires an active matching ID in the writer's
captured table. Namespace copies still resolve inherited descriptions to their
local record. Remount and unmount hold the existing VFS writer lock throughout
lookup and mutation; move already used it. Move admission also requires the
destination and current parent chains to belong to that table. A detached or
foreign source/remount/unmount root returns `EINVAL`. A detached destination
returns `ENOENT`; an active foreign destination returns `EINVAL`, matching the
Linux reference. The target directory is explicitly opened first in the probe
to distinguish namespace admission from a missing pathname. Linux's destination check is in
[`do_lock_mount` and `do_move_mount`](https://github.com/torvalds/linux/blob/v6.12/fs/namespace.c).

Policy lookup retains its fallback for data access through held descriptions.
Creation previously ignored that retained context and checked only active
mounts above the inode: a read-only detached fd could create a file. Creation
and writable/truncating opens now also check the resolved mount context before
changing the filesystem or acquiring a new writable description. This preserves
the caller's namespace copy when present and retained policy when absent.

The V fixture has seven cases:

| Case | Held mount | Refused operation |
| --- | --- | --- |
| `id-0` | Lazily detached root, with a new mount at the original path | Unmount the old root. |
| `id-1` | Same arrangement | Remount the old root writable. |
| `id-2` | Same arrangement | Move a live local source onto the old root's child. |
| `id-3` | New root created only in a child's private mount namespace | Unmount that foreign root. |
| `id-4` | Same arrangement | Remount that foreign root writable. |
| `id-5` | Same arrangement | Move the foreign root onto a local destination. |
| `id-6` | Same arrangement | Move a live local source onto the foreign root's child. |

Each case drops supplementary groups and UID/GID to 1000 in a forked account
check, which must receive `EPERM`. Root then repeats the refusal 200 times,
preserving local/replacement device/inode identity and marker data. Retained
fds must read the old marker, refuse missing-file creation without leaving a
file, and refuse `O_WRONLY`, `O_RDWR` and `O_RDONLY|O_TRUNC` opens of the existing
marker with `EROFS`. Relative cwd paths receive the same attachment refusal.
Detached-source moves are checked separately. Foreign cases repeat refusal and
data/policy checks after the child lazily unmounts and exits. Finally, held local
fds allow read-only/writable remounts and a move, and ordinary unmount succeeds
after descriptors close.

Run `--case identities` or an individual case with the native controller in
[README.md](README.md). The default full run also requires the prior unmount
mode, cycle, reparented-holder and exact 64-step depth checks. The Linux launcher
uses the identical native ELF and selects all portable move and identity checks,
without changing identity expectations.

Qualification states from 2026-10-14 are retained in
`build/development17-20261013`:

| States (both `arm` and `x86`) | Result |
| --- | --- |
| `mount-identities-*-id-{0..6}-before-e` | Previous mode/depth kernels accept every stale/foreign attachment operation; final probe, result 0. |
| `mount-identities-*-readonly-before-d` | Attachment guards alone refuse the operation, but creation through the detached read-only fd returns a valid descriptor. |
| `mount-identities-*-all-after-d` | Final native kernels pass all identity, policy, authorization and previous mode/depth checks. |
| `mount-identities-*-linux-c` | Linux 6.12.51 passes the portable checks with the identical final native probe ELF. |

Earlier `before-a` fixture compilation failures, earlier controls, and
`all-after-a`/`readonly-before-a` policy failures are preserved. `all-after-b`
and `all-after-c` passed natively; `linux-a`/`linux-b` exposed the detached and
active-foreign destination errno distinctions, corrected before the final runs.
No failed result is used as a passing qualification.

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `88b0839df77e5e7b8fced2a9b729029c700e2fe58c925d9341b09199df20050b` | `62378e267785070d49c8009346f1580ff916cd8baf3a1564aade752e185d4fb9` |
| x86_64 | `de35d86bbfa757af27bb9dfb460a890465c947bc9d9fb7950f7959606995d5d6` | `576372f9e8615e9dddebf8c004a4a76ce5ba64d175a19f3d57ccc197558f0fb9` |

The final source manifests reuse the prior frozen mount-lifecycle kernels,
changing only `kernel/fs/mount.v`, `mount_policy.v` and the two read-only checks
in `vfs.v`. Other sessions' live changes are excluded. The frozen VFS also
predates another session's committed creation-marker wiring; the commit keeps
that existing wiring. The read-only checks and their surrounding policy
decisions match the qualified source. Isolated builds use V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link shuffle seed 17. Frozen `mount-identities4-{arm,x86}-input` directories
pin the kernel ELF, generated C, all three changed sources and source manifest.
`mount-identities-evidence.log` records independent checks of receipts and
artifacts, all case markers, original-kernel controls, guard-only controls and
native/Linux ELF identity.
It also checks generated active-lookup, parent-traversal and move functions for
allocations, and verifies the retained-context check precedes truncation.
Cached probes with a stale source, wrong architecture or modified ELF are
refused before boot; final negative controls exercise valid cache reuse.

These changes add no mount ownership or reclamation. Mount objects and cached
filesystem trees retain their existing permanent lifetimes. They do not qualify
busy-reference accounting, creating/removing mounts with flat allocations,
full read-only enforcement for every metadata syscall, complete bind-alias
isolation, propagation, new mount/bind/pivot admission, concurrent mount
publication/namespace switching or teardown. Full OCI/rootless qualification
and the rest of roadmap section 17 remain open.
