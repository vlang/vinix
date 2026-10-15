# Inherited descriptor inode flags

`FS_IOC_SETFLAGS` now checks the actual saved mount of its descriptor before
changing immutable/append-only bits. An inherited writable description remains
usable when the namespace copy becomes read-only. An inherited read-only
description gains no mutation authority when the copy becomes writable.
Authorized requests that repeat the current bits also require a writable mount.
`FS_IOC_GETFLAGS` remains available through read-only descriptions.

The existing ioctl dispatcher already pins the descriptor and passes its
mount context synchronously. The flag helper now selects the descriptor
read-only reader. MAC, argument validation, backend support, capability
admission, securelevel, unchanged-value handling, overlay preparation and
persistence remain in their previous order. No owner, reference transition,
allocation or free is added.

[Linux v6.12 `fs/ioctl.c`](https://github.com/torvalds/linux/blob/v6.12/fs/ioctl.c)
uses the saved file mount for setter write admission. These tests preserve
Vinix's existing capability-before-mount error ordering. They do not qualify
Linux flag payloads or error precedence.

Use `--case descflags` or `df-0` through `df-5`. Native `all` includes the group;
Linux `move-reference` excludes it, as it excludes the existing inode-flag group.

| Case | Saved description and copied mount |
| --- | --- |
| 0 | Writable regular file; copy remounted read-only |
| 1 | Read-only regular file; copy remounted writable |
| 2 | Writable directory; copy remounted read-only |
| 3 | Read-only directory; copy remounted writable |
| 4 | Writable unlinked regular file; copy remounted read-only |
| 5 | Read-only unlinked regular file; copy remounted writable |

Each case duplicates an ordinary data-read-only description, closes the
original, copies the namespace and gives the copy opposite mount flags.
Fresh descriptions follow the copied mount for linked targets. Statfs and
pathname chmod independently establish that distinction.

Sixty-four cycles cover append-only, immutable, both bits and clearing. A
writable description changes the bits; both aliases observe them. Changed
and unchanged requests through a read-only description return `EROFS`,
preserving bits, identity, ownership, mode, size and timestamps. The unlinked
read-only case has no writable alias and retains its original zero bits.
A forked UID/GID 1000 cannot set changed or unchanged values through either
description (`EPERM`); getters remain available. Final flags, regular data
and unlinked link counts are checked.

Evidence from 2026-10-15 is retained under `build/development17-20261013`:

| States | Result |
| --- | --- |
| `mount-descflags-{arm,x86}-df-0-before-a` | Previous kernels wrongly return `EROFS` through inherited writable descriptions when the namespace copy becomes read-only. |
| `mount-descflags-{arm,x86}-df-1-before-a` | Previous kernels wrongly permit a flag change through inherited read-only descriptions when the copy becomes writable. |
| `mount-descflags-{arm,x86}-descflags-after-a` | All six corrected native cases pass. |
| `mount-descflags-arm-all-after-a` | The complete native mount suite passes, including the existing and new inode-flag groups. |
| `mount-descflags-x86-all-after-b` | The complete native mount suite passes, including the existing and new inode-flag groups. |
| `mount-descflags-{arm,x86}-linux-a` | The same probe executables pass the portable Linux 6.12.51 suite; both native inode-flag groups are excluded. |

| Architecture | Kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `8da3d2017b26c1c0046932d33f0a22b70f0675d6321fabcd266a9b8966aa6c81` | `269e2ac8945a664e944e337aa6c377df6af8c87b95ef682dd8a2285cca231b28` |
| x86_64 | `94dcfaa770055dc73890fdc42b73f4b8cc19704545dd8f8a51eb50c2f0f11eb4` | `71e1dc56f6f70ab05d1de63af3417628c0d4fab703317907b33b98f3023c187b` |

`mount-descflags-{arm,x86}-input` preserves complete source manifests,
source snapshots, generated C, kernels and hashes. Builds use V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. Native ARM uses HVF/four CPUs; x86 uses TCG/two, with
1024 MiB. Linux uses HVF/TCG, two CPUs and 512 MiB. Controls and Linux runs
allow 600 seconds; focused and cumulative native runs allow 900 seconds.
Networking is disabled. Controls and corrected runs share all twenty-six
fixture sources and the same probe/C artifacts.

The first cumulative x86 state, `mount-descflags-x86-all-after-a`, was stopped
by a turn interruption before it wrote a completion receipt. Its partial log
and artifacts remain preserved. The fresh `mount-descflags-x86-all-after-b`
replay uses the same pinned probe and kernel.

The isolated builds extend the qualified descriptor-xattr inputs, changing
only `kernel/fs/attributes.v`. The baseline still excludes pre-existing
open-created descriptor hunks, staged pointer-return spelling edits and earlier
fcntl/descriptor/lock changes described in
[the writer qualification](writer-policy.md). Later checkout changes are also
excluded. The complete current checkout kernel was not built or booted.

The assertion-enabled source/C audit compares all parsed namespace-qualified
functions after temporary/discard/loop-index normalization. The complete flag
helper matches after replacing its namespace-aware read-only helper with the
descriptor helper. Every other parsed function, including the ioctl dispatcher,
policy readers, copy-up and persistence bodies, remains unchanged. Receipt
checks pin all twenty-six fixture sources, controllers, artifacts, controls,
shared native/Linux probe/C identity and positive markers. The post-commit
check preserves other sessions' staged edits.
Per-architecture `descriptor-flags-c-audit.txt`,
`mount-descflags-source-evidence-a.log`, `mount-descflags-evidence-a.log`
and `mount-descflags-post-commit-a.log` retain the results.

Filesystem-backed Linux flag comparisons, concurrent remount/setns,
filesystem-wide remounts, `O_PATH` behavior, anonymous resources, broader
securelevel/MAC/capability combinations and persistent/overlay divergent-route
integration remain open. There is no allocation-flatness or mount reclamation
claim. Desktop performance scenarios are outside this qualification.
Full OCI/rootless acceptance and roadmap section 17 remain in progress.
