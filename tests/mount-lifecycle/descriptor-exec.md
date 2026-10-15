# Inherited descriptor executable loading

`execveat` with an empty path and `AT_EMPTY_PATH` now uses the actual saved
mount of its descriptor for the executable's `noexec` check. An inherited
executable description stays usable when its namespace copy gains `noexec`;
a description on `noexec` gains no execution authority when the copy loses
that flag. Denied requests return `EACCES`.

Both architecture loaders carry a scalar descriptor selector. Ordinary
pathname entry calls pass false; empty-path `execveat` records its origin
before freeing the path. The selected noexec reader is the existing raw
mount-flags reader, now exported from FS. Scripts resolve their interpreter
through ordinary pathname loading. ARM translator entry calls also pass false.
MAC, pledge/unveil, inode permissions, credentials, W^X admission, image reads,
ELF interpreter checks, argument ownership and descriptor commit/error releases
retain their previous bodies and order. No allocation, owner, reference
transition or free is added.

[Linux v6.12 `do_open_execat`](https://github.com/torvalds/linux/blob/v6.12/fs/exec.c)
checks `noexec` on the opened file's saved path and returns `EACCES` before
loading the image.

The subsequent [directory policy checks](directory-exec-policy.md) extend
saved-mount execution policy to relative requests through inherited directory
descriptions. Cases 6/7 now include retained script directories, and cases
8/9 add ELF directory routes as UID/GID 1000 owners.

Use `--case descexec` or `de-0` through `de-9`. Native `all` and Linux
`move-reference` include the group:

| Case | Saved description | Copied mount |
| --- | --- | --- |
| 0 | Executable linked native ELF | `noexec` |
| 1 | `noexec` linked native ELF | Executable |
| 2 | Executable unlinked native ELF | `noexec` |
| 3 | `noexec` unlinked native ELF | Executable |
| 4 | UID/GID 1000 owner's executable native ELF | `noexec` |
| 5 | Owner's `noexec` native ELF | Executable |
| 6 | Executable script with an executable native interpreter | `noexec` |
| 7 | `noexec` script with an executable native interpreter | Executable |
| 8 | Owner's executable ELF through retained directories | `noexec` |
| 9 | Owner's `noexec` ELF through retained directories | Executable |

The fixture copies its own static native ELF and duplicates both ordinary
read-only and `O_PATH` descriptions before closing the originals. Script
interpreters use separate executable paths outside the remounted target.
After copying the namespace and assigning opposite mount flags, statfs
independently establishes both policies. Four cycles fork and execute each
retained description. Linked targets also exercise fresh descriptions,
absolute `execveat` with an invalid dirfd, relative `execveat` from a fresh
directory descriptor and ordinary `execve`. Fresh and pathname requests follow
the namespace copy. Successful images verify their real/effective UID/GID and
exit with status 37; denied requests must return `EACCES`. File identity,
mode, ownership, size, link counts, mtime/ctime and signature bytes remain.
Exec reads may update atime.

Evidence from 2026-10-15 is retained under `build/development17-20261013`:

| States | Result |
| --- | --- |
| `mount-descexec-{arm,x86}-de-{0,2}-before-d` | Previous kernels wrongly return `EACCES` through inherited executable linked/unlinked descriptions when the namespace copy gains `noexec`. |
| `mount-descexec-{arm,x86}-de-{1,3}-before-d` | Previous kernels execute the image through inherited `noexec` descriptions when the copy becomes executable; the child reaches status 37. |
| `mount-descexec-{arm,x86}-descexec-after-d` | All eight corrected native cases pass. |
| `mount-descexec-{arm,x86}-all-after-d` | The complete native mount suites pass. |
| `mount-descexec-{arm,x86}-linux-d` | The same probe executables pass the portable Linux 6.12.51 suites, including all eight exec cases. |

| Architecture | Kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `29fdf9b0e37ebc3cd559ac0acfdaa031653e71d7a6657b4697855d0cb405079c` | `9597c9d55f18304cc7d798a688979ef06ef7566919d2c58d30c891d5ed2bfa33` |
| x86_64 | `113f659cecb8933e1fb0310ff7bffbee1ca5be327ad8a394b2288cd7a266bc9d` | `ee0730eedca21e580d9f7535ea23ed07634caecb31a6d93621681134b902d13c` |

`mount-descexec-{arm,x86}-input` preserves source manifests, loader/policy
snapshots, generated C, kernels and hashes. Kernel builds use V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. Native ARM uses HVF/four CPUs; x86 uses TCG/two, with
1024 MiB. Linux uses HVF/TCG, two CPUs and 512 MiB. Controls and Linux runs
allow 600 seconds; focused and cumulative native runs allow 900 seconds.
Networking is disabled. Controls and corrected native runs share all
twenty-nine fixture sources and probe/C artifacts. Linux reuses the identical
probe executables. Both architectures' probe C has SHA-256
`385e74b9ef061e5248066e56bef2c348bc1b352b968c3c1215f48977a7c7a0b6`.

The ARM host probe build uses an owned musl SDK copied from Homebrew
`musl-cross/0.9.11`, with GCC 14.2.0 startup/support objects. The
`mount-descexec-arm-sdk/sources.json` manifest pins 2322 include/library entries
and symlink targets; `gcc/sources.json` pins `crtbeginT.o`, `crtend.o`,
`libgcc.a` and `libgcc_eh.a`. The V compiler wrapper supplies these support
paths to Clang's link step. `mount-descexec-sdk-b.log` and
`mount-descexec-gcc-support-a.log` record verified copies. This is a host build
input, not a qualification of these toolchains running inside Vinix.

Initial ARM states `de-0-before-a` and `de-0-before-b` stopped before boot,
respectively at missing headers from a removed userland sysroot and missing
GCC startup/support objects. The first SDK copy failed on a dangling dynamic
loader symlink; its partial tree remains at `mount-descexec-arm-sdk-before-a`.
The corrected V copier preserves symlinks and verifies every copied entry.
The `de-0-before-c` retry booted and reproduced the direct-descriptor denial.
Initial `*-linux-a` states failed the inherited-directory relative-path
expectation described below. Their complete logs and artifacts, initial native
states and compiler-audit diagnostics remain preserved. Final `d` states use
fresh probe executables with the corrected portable relative-path case.

The isolated builds extend the qualified [descriptor-access inputs](descriptor-access.md),
changing only the two architecture loader files and the raw reader's visibility
in `kernel/fs/mount_policy.v`. The baseline retains the previously documented
exclusions of open-created VFS hunks, staged pointer-return spelling and earlier
fcntl/descriptor/lock changes. It also excludes the existing process-name/path
publication locks in the current loaders: the post-commit comparison accounts
for those exact pre-existing hunks. Later checkout changes remain excluded.
The complete current checkout kernel was not built or booted.

The assertion-enabled source/C audit compares all parsed namespace-qualified
functions after normalizing compiler-generated temporary, array and iterator
numbers. Each changed loader/dispatch body matches completely after adding the
scalar selector and the checked stack-valued noexec reader selection. Every
other parsed function, including the raw reader and descriptor release helper,
is unchanged. Receipt checks pin all twenty-nine fixture sources, controllers,
artifacts, controls, shared native/Linux probe/C identity and positive markers.
The post-commit audit compares the exact committed three-file kernel patch,
accounts for the same process-publication hunks in both source snapshots and
checks that other sessions' staged VFS changes remain separate.
Per-architecture `descriptor-exec-c-audit.txt`,
`mount-descexec-source-evidence-c.log`, `mount-descexec-evidence-d.log`
and `mount-descexec-post-commit-d.log` retain the results.

The initial Linux fixtures exposed a separate pre-copy directory mismatch.
The evidence above covers direct image descriptions and fresh relative
directories. [Later qualification](directory-exec-policy.md) covers inherited
directory policy in both flag directions, relative/absolute links and
interpreter refusal without changing the general path walker.

Concurrent remount/setns, dynamic ELF interpreters, ARM translation execution,
relative shebang resolution, credential transitions, combined error precedence,
broader MAC/W^X combinations, descriptor-specific `wxallowed`, persistent/overlay
integration, allocation-flatness, mount reclamation and desktop performance
remain outside this qualification. Full OCI/rootless acceptance and roadmap
section 17 remain in progress.
