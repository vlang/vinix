# execveat flag and final-symlink validation

Both architecture dispatchers now interpret flags as a C-int argument, reject
bits outside `AT_EMPTY_PATH | AT_SYMLINK_NOFOLLOW` with `EINVAL`, and reject
a final symlink left unfollowed with `ELOOP`. Previously unsupported bits could
launch an image, and unfollowed final links reached the generic `EACCES`
non-regular-image check. `O_PATH` descriptions of symlinks also return `ELOOP`
when used directly with an empty path, with or without `AT_SYMLINK_NOFOLLOW`.

The path is copied before flag validation. An empty path without
`AT_EMPTY_PATH` retains `ENOENT`, including when an unrelated flag is set.
Unknown flags are rejected before directory/file lookup or argument allocation.
The final-link check runs after lookup and before argument allocation. Each
new error path releases only its existing owned path string; the direct-image
descriptor still reaches its existing syscall defer. No reference transition,
allocation or new shared lifetime is added. MAC restoration, descriptor pins,
mount flags, W^X, credentials, script/interpreter handling and image loading
retain their existing bodies.

A separate read-only review of both architecture sources and generated C
found no cleanup issue. It checked the path/target alias, direct-descriptor
release, MAC restoration and absence of new allocations; it did not include
runtime or concurrent-reclamation stress. The retained report is
`build/development17-20261013/mount-execflags-cleanup-review.txt`.

[Linux v6.12 do_open_execat](https://github.com/torvalds/linux/blob/v6.12/fs/exec.c)
validates the two supported flags before opening the image and configures
final-link following from `AT_SYMLINK_NOFOLLOW`. The syscall declares flags
as `int` and copies its filename before entering this validation. The runtime
comparisons below check the selected error combinations directly.

Use `--case execflags` or `ef-0` through `ef-9`. Native `all` and Linux
`move-reference` include all ten cases:

| Case | Checks |
| --- | --- |
| 0 | Unknown flags on an absolute native ELF path with an invalid dirfd. |
| 1 | Unknown flags on a directory-relative native ELF path as UID/GID 1000. |
| 2 | Unknown flags on an empty-path duplicated read-only ELF description. |
| 3 | Unknown flags on an unlinked duplicated `O_PATH` ELF description as UID/GID 1000. |
| 4 | Absolute final symlink refusal; final following and intermediate symlinks remain usable. |
| 5 | Relative final symlink refusal and accepted following as UID/GID 1000. |
| 6 | Dangling final symlink: `ELOOP` without following, `ENOENT` with following. |
| 7 | Direct empty-path `O_PATH | O_NOFOLLOW` symlink description returns `ELOOP` as UID/GID 1000. |
| 8 | All legal flag combinations launch regular images through absolute, relative and empty-path forms, including flags registers with nonzero upper 32 bits. |
| 9 | Selected flag, empty-path, null-path, missing-path and invalid-descriptor error precedence as UID/GID 1000. |

Unknown-bit matrices include low bits, bits adjacent to the supported flags,
bit 31 and all low 32 bits, combined with supported flags. All launches fork;
successful images check real/effective UID/GID and exit with status 37.
Denied calls must return the exact expected error. Identity, size, mode,
ownership, link count and mtime/ctime remain; executable reads may update atime.

Evidence from 2026-10-15 is retained under `build/development17-20261013`:

| States | Result |
| --- | --- |
| `mount-execflags-{arm,x86}-ef-{0,3}-before-a` | Previous kernels ignore unknown flags and launch linked/unlinked native images; child status 37 proves execution. |
| `mount-execflags-{arm,x86}-ef-{4,7}-before-a` | Previous kernels return `EACCES` instead of `ELOOP` for pathname no-follow and direct symlink descriptions. |
| `mount-execflags-{arm,x86}-execflags-after-a` | All ten corrected native cases pass. |
| `mount-execflags-{arm,x86}-all-after-a` | Complete native mount suites pass, including the ten new cases. |
| `mount-execflags-{arm,x86}-linux-a` | The same probe ELFs pass the portable Linux 6.12.51 suites, including all ten new cases. |

| Architecture | Kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `a901ca70c08f4c00a3e3b1c10f4bd8c8b1f6f6790c728e7bd6f541e947fc5cf4` | `846fdf3f08f832614ad6cef9416295780b1b09703cb8151b7eb69179072fc121` |
| x86_64 | `06b1f181ed354bd4d3de1756ce758e6e267b95a4c1b20968502aba21c77c9201` | `1fd91a54d806e140de915af7970c0121df552b5224aa0199e82ad26dc48e8476` |

`mount-execflags-{arm,x86}-input` preserves complete source manifests, loader
and policy snapshots, generated C, kernels and hashes. Builds use V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. Native ARM uses HVF/four CPUs; x86 uses TCG/two, each with
1024 MiB. Linux uses HVF/TCG, two CPUs and 512 MiB. Networking is disabled.
Controls and Linux runs allow 600 seconds; focused and cumulative native runs
allow 900 seconds.

Controls and corrected native runs share all thirty-one fixture sources and
probe/C artifacts. Linux reuses the identical probe ELFs. Both probe C files
have SHA-256
`b13543ad42c03c9039415be75b2372f1807e95d611756e98a0df969feae71216`.
ARM probe compilation reuses the owned musl SDK and V Clang wrapper documented
in [descriptor execution](descriptor-exec.md), with its GCC 14.2.0 support
objects and hashed manifests. These remain host build inputs.

The isolated builds extend the qualified [descriptor W^X inputs](descriptor-wx.md),
changing only the two architecture loader files. They retain the documented
exclusions of open-created VFS hunks, staged pointer-return spelling, earlier
fcntl/descriptor/lock changes and existing process-name/path publication locks
in the current loaders. The post-commit comparison accounts for those exact
pre-existing publication hunks. Concurrent checkout edits remain excluded.
The complete current checkout kernel was not built or booted.

The assertion-enabled source/C audit compares all parsed namespace-qualified
functions after normalizing compiler temporary/discard/loop-index numbers.
Every function except `syscall_execveat` matches the baseline. Its complete
body matches after the reviewed flag normalization/validation, relocated
empty-path check, normalized lookup flags and final-link refusal. The final
link mode expression matches the existing primary-image regular-file check
applied to the selected node. Each new failure branch frees its owned string
and reaches the existing descriptor-release and MAC-restoration defers. No
new allocation, reference transition or shared lifetime is added.

Receipt checks pin all thirty-one fixture sources, controllers, artifacts,
controls, shared native/Linux probe/C identity and positive markers.
`exec-flags-c-audit.txt` in each input, `mount-execflags-source-evidence-b.log`,
`mount-execflags-evidence-a.log` and `mount-execflags-post-commit-a.log` retain
the results. The post-commit audit checks all ten committed paths, the exact
two-file kernel patch, tested source identity after the documented exclusions,
and preservation of unrelated staged VFS edits.

The initial source audit stopped because its helper expected only one regular
file mode check in the loader, which also checks the ELF interpreter. The
corrected audit derives the field expression from the primary-image check
and asserts that it addresses the executable node. Product code and all
runtime probe artifacts remained unchanged; the initial audit log is retained.

Concurrent namespace/remount changes, arbitrary fault/error combinations,
dynamic ELF interpreters, translated images, broader MAC/W^X combinations,
relative paths through inherited directory descriptions with divergent mount
flags, persistent/overlay integration, allocation-flatness and desktop
performance remain outside this qualification. Full OCI/rootless acceptance
and roadmap section 17 remain in progress.
