# Extended-attribute attachment policy

Extended-attribute targets retain the resolved attachment as well as their
inode/resource. Set and remove operations require that attachment and the
backend to be writable. The previous inode-only check could reject a writable
source because a bind alias was read-only, or allow changes through a read-only
route because its writable alias was newer or its namespace had retired.

Path lookup snapshots the starting directory and mount, then uses the existing
`retain_path_target_on_mount` helper. `XAttrTarget` stores only the final Mount
identity; it does not borrow the stack cursor or a description's mount context.
Mount entries remain permanent after detach and namespace retirement. A small
`attachment_flags` helper maps that identity into the caller's namespace copy
or falls back to the retained entry. Descriptor targets extract the identity
while their existing FD pin is held. Overlay target copies preserve it.

Existing node/resource and FD pins, cleanup, MAC, backend read-only, immutable,
ACL ownership, namespace capability and file-access checks remain in place.
Set/remove authorization still precedes overlay copy-up and runs again on an
overlay's upper target. Reads and listings retain their existing authorization
and trusted-name filtering. The target grows by one pointer; there is no new
heap owner or resource pin. The attachment lifetime is independently reviewed.

This follows the attachment-specific mount-write requirement in
[Linux v6.12 extended-attribute operations](https://github.com/torvalds/linux/blob/v6.12/fs/xattr.c).

Use `--case xattrs` or `xp-0` through `xp-7`. Each case runs in a child with a
private mount namespace, tmpfs and an eight-byte marker.

| Case | Routes exercised |
| --- | --- |
| 0 | Writable source/read-only directory bind, followed by reversed flags |
| 1 | Local descriptions after a namespace copy, both flag directions |
| 2 | Chroot root and cwd through different aliases, both directions |
| 3 | Regular-file bind and original pathname, both directions |
| 4 | Directory description through a read-only bind after lazy detach |
| 5 | Descriptions retained after a worker's private namespace retires |
| 6 | Read-only source/writable bind established before the first call |
| 7 | File descriptions opened before a namespace copy, retaining unchanged attachment flags |

Each pair repeats 200 iterations of pathname, no-follow and descriptor forms
of set/remove for `user.*` and `trusted.*`. Create, binary replacement, empty
replacement and removal are verified through all three get/list forms on both
routes. Read-only attempts against present and absent names must return `EROFS`
without changing values, mode, UID/GID, size, inode identity or timestamps.
Reads and listings through read-only aliases remain available to authorized
callers. Data descriptors are opened read-only.

Directory cases also change trusted attributes on symlinks with no-follow
operations, keeping the target's attributes and timestamps intact. Following
the same symlink changes its regular target instead; read-only follow and
no-follow changes must fail while preserving both attribute stores.
UID/GID 1000 receives `EACCES` for user writes to the mode-0600 marker and
`EPERM` for trusted writes through writable routes; read-only writes return
`EROFS`. Trusted values and names are hidden from its reads and listings.
The inherited-descriptor case verifies continued read-only protection after
the namespace copy with unchanged flags. Marker data stays intact.

All thirteen V fixture sources, generated C, probe/kernel ELFs, image, serial
log and hash receipt are retained in fresh native states. The exact native
probe ELF runs the portable suite on Linux 6.12.51. Isolated kernel builds
start from the frozen `mount-times` baseline and apply only the two owned
xattr/mount-policy changes, excluding concurrent sessions' checkout edits.

Evidence from 2026-10-15 is under `build/development17-20261013`:

| States | Result |
| --- | --- |
| `mount-xattrs-{arm,x86}-xp-0-before-b` and `-xp-7-before-c` | Previous kernel rejects writable source and inherited-description operations when their bind alias is read-only. |
| `mount-xattrs-{arm,x86}-xp-{4,5,6}-before-c` | Previous kernel accepts replacement through detached, retired and live read-only routes. |
| `mount-xattrs-arm-all-after-a`, `mount-xattrs-x86-all-after-c` | Corrected kernels pass the full native suite and all eight xattr cases. |
| `mount-xattrs-x86-xattrs-after-a` | All eight xattr cases pass in a fresh native x86 guest with the same probe ELF. |
| `mount-xattrs-{arm,x86}-linux-c` | Linux 6.12.51 passes the portable suite with the same probe ELFs. |

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `f3b7b871ddc8c061c957df7062a14f50295280950ee76c89c75664f700465f26` | `1bd9dfc4331c6a1d3a784072a72a17cf507de1d0a46145ed2c9042a8bc4ca95f` |
| x86_64 | `0ce76ce5f360a32b16aae4cf23c393b4c5ab7174be1b73103eadbc2e9352f2ed` | `2a502fe0c960ba82282b31a7e3d92957718f79d712d43d1f9859f8031a93aa4b` |

Each `mount-xattrs-{arm,x86}-input` freezes kernel/C artifacts, changed sources,
VFS/socket-lookup sources and the complete source manifest. Builds use V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link shuffle seed 17. Native ARM uses HVF/four CPUs; x86 uses TCG/two CPUs.
Linux references have two CPUs. Networking is disabled. Full native suites use
300 seconds on ARM and 1800 on x86; the fresh x86 xattr group uses 600 seconds.
Final Linux references use `--timeout 600`;
the controller keeps its 180-second default and records the chosen timeout.

`mount-xattrs-lifetime-review.md` records independent review of xattr source
`0e74a0006fa299f3934c4fe5e6c13a75ea94cb3bf43ac5b8916d286c9ef42e2e`,
mount-policy source `a0e1df0df703f314ff5bce2dd46716f1bcc0fa4ee5f4555062db0cc2c7fbb868`
and both generated C files. The review checks supporting lifetime sources in
the frozen worktrees; later checkout changes in FD, namespace and VFS code are
excluded. The evidence audit checks its pins, every receipt/artifact/source
hash, the exact two-file kernel delta, all markers and shared ELF identity.
It also verifies unchanged syscall/mutation bodies and cleanup, extraction of
the permanent identity, overlay preservation, and no new direct heap promotion
in the changed helpers. Per-architecture `xattr-c-audit.txt` retains these checks.

Initial `linux-a` states preserve the failed divergent-flags inherited-FD
comparison. Linux retains the original attachment's flags; Vinix currently maps
its identity into the caller's namespace copy. That existing difference remains
open, and the final inherited-FD case copies the namespace without remounting.
Initial x86 `linux-b` and native `all-after-a`/`all-after-b` states preserve
time-limit failures without syscall failure markers. The host load average was
above 170 after the 600-second native timeout. Longer runs retain all assertions
and iteration counts. The x86 `pv-4-after-a` isolation check also passes.
`xp-4-before-b` on x86 records a control started before its seed receipt was
finished; fresh `before-c` controls use the completed receipt.

Inherited descriptors whose namespace copies have divergent remount flags,
concurrent remount/setns, mount reclamation, overlay copy-up integration,
persistent-backend transactions, ACL/security-label/capability payloads,
anonymous resources, allocation-flat loops and full OCI/rootless acceptance
remain outside this qualification. Inode flags and other metadata paths still
need complete attachment-policy coverage. Roadmap section 17 remains in progress.
