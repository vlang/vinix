# Inherited descriptor W^X approval

Empty-path `execveat` now checks `wxallowed` on the executable description's
actual saved mount. Revoking approval only in a copied namespace no longer
denies an inherited approved description; granting it only in the copy no
longer authorizes an inherited unapproved one. Unauthorized explicit
`VINIX_ALLOW_WX=1` requests return `EPERM`.

The existing scalar descriptor selector reaches `fs.wx_exec_allowed` in both
architecture loaders. Its privileged initial-user-namespace effective-root
and `CAP_SYS_ADMIN` override is unchanged. The remaining check selects the
existing raw reader for descriptions and namespace reader for pathname loads.
Scripts still authorize their interpreter separately. No owner, allocation,
reference transition or free is added.

Use `--case descwx` or `dw-0` through `dw-7`. Native `all` includes the group.
Linux `move-reference` excludes it: `wxallowed` and the explicit Vinix W^X
opt-in are not Linux mount policy.

| Case | Saved mount | Copied mount | Image / launcher |
| --- | --- | --- | --- |
| 0 | Approved | Unapproved | Linked ELF, UID/GID 1000 owner |
| 1 | Unapproved | Approved | Linked ELF, UID/GID 1000 owner |
| 2 | Approved | Unapproved | Unlinked ELF, UID/GID 1000 owner |
| 3 | Unapproved | Approved | Unlinked ELF, UID/GID 1000 owner |
| 4 | Approved | Unapproved | Linked ELF, effective root without `CAP_SYS_ADMIN` |
| 5 | Unapproved | Approved | Linked ELF, effective root without `CAP_SYS_ADMIN` |
| 6 | Approved | Unapproved | Script, UID/GID 1000 owner, separately approved native interpreter |
| 7 | Unapproved | Approved | Script, UID/GID 1000 owner, separately approved native interpreter |

The fixture copies its own static ELF and duplicates read-only and `O_PATH`
descriptions, then closes their originals. Both mounts stay executable and
read-only with `nosuid,nodev`. Remount requests use the administrator-only
option string; `/proc/self/mounts` independently checks its live advertisement
before and after copying the namespace. Linked cases also test fresh ordinary
and `O_PATH` descriptions, absolute `execveat`, relative `execveat` from a
fresh directory description and ordinary `execve`. Two cycles cover each
route with and without the environment request. Default launches must retain
W^X even on approved mounts. Initial-namespace root with `CAP_SYS_ADMIN` must
still succeed with a request on either mount. The restricted-root cases remove
that capability from the launcher's effective and permitted sets before exec.

Successful images verify real/effective UID/GID, test RWX `mmap` and RW-to-RWX
`mprotect`, write/read marker data, and repeat the mapping checks after fork.
Denied mappings require `EOPNOTSUPP`; accepted launches exit with status 38
only after those checks. Unauthorized exec requests must return `EPERM`.
Identity, size, mode, ownership, link count, mtime/ctime and signature bytes
are preserved; executable reads may update atime.

Evidence from 2026-10-15 is retained under `build/development17-20261013`:

| States | Result |
| --- | --- |
| `mount-descwx-{arm,x86}-dw-{0,2}-before-b` | Previous kernels wrongly deny inherited approved linked/unlinked descriptions with `EPERM` after the namespace copy revokes approval. |
| `mount-descwx-{arm,x86}-dw-{1,3}-before-b` | Previous kernels wrongly admit inherited unapproved linked/unlinked descriptions after approval in the copy; the image verifies RWX permission and exits 38. |
| `mount-descwx-{arm,x86}-descwx-after-b` | All eight corrected native cases pass. |
| `mount-descwx-{arm,x86}-all-after-b` | Complete native mount suites pass, including all eight W^X cases. |
| `mount-descwx-{arm,x86}-linux-b` | The same probe ELFs pass the portable Linux 6.12.51 suites; the Vinix-only W^X group is excluded. |

| Architecture | Kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `bbca9f6e2140de669d691f3df2e1eea7d8b401f98c2f358540758d27a17b2cd2` | `bf08bf6371542653d88a69a54a67e9805804cea2e0772a59f5e6de681359367b` |
| x86_64 | `acce4a711c71c71f6e28c6b570923573e5a96658415cc14bf71d25196086d5d1` | `a9d7baede3e401d24fd22be5951afa047f7d9373d3d5ae9a9a3977abf4343364` |

`mount-descwx-{arm,x86}-input` preserves complete source manifests, source
snapshots, generated C, kernels and hashes. Builds use V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. Native ARM uses HVF/four CPUs; x86 uses TCG/two, each with
1024 MiB. Linux uses HVF/TCG, two CPUs and 512 MiB. Networking is disabled.
Controls and Linux runs allow 600 seconds; focused and cumulative native
runs allow 900 seconds.

Controls and corrected native runs share all thirty fixture sources and
probe/C artifacts; Linux reuses the identical probe executables. Both probe
C files have SHA-256
`818f7c29b7c58b3cee995f8debfc1151a20dc9446df373efcacf51e59a65867d`.
ARM probe compilation reuses the owned musl SDK and V Clang wrapper documented
in [descriptor execution](descriptor-exec.md), including its GCC 14.2.0 support
objects and hashed manifests. This is a host build input, not native toolchain
qualification inside Vinix.

The isolated builds extend the qualified [descriptor-exec inputs](descriptor-exec.md),
changing only `kernel/fs/wx_policy.v` and the two architecture loader calls.
They retain the documented exclusions of open-created VFS hunks, staged
pointer-return spelling, earlier fcntl/descriptor/lock changes, and existing
process-name/path publication locks in the current loaders. The post-commit
comparison accounts for those exact pre-existing publication hunks. Concurrent
checkout edits remain excluded. The complete current checkout kernel was
not built or booted.

The assertion-enabled source/C audit compares all parsed namespace-qualified
functions after compiler temporary/discard/loop-index normalization. Each
complete changed body matches after adding the scalar parameter, the stack
branch selecting the existing raw/namespace readers, and the caller argument.
Every other parsed function is unchanged, including privileged authorization,
noexec, mappings, descriptor releases and interpreter/translator handling.
Receipt checks pin all thirty fixture sources, controllers, artifacts,
controls, shared native/Linux probe/C identity and positive markers.
`descriptor-wx-c-audit.txt` in each input, `mount-descwx-source-evidence-b.log`,
`mount-descwx-evidence-b.log` and `mount-descwx-post-commit-b.log` retain the
audit results. The post-commit audit checks all ten committed paths, the exact
three-file kernel patch, tested source identity after the documented exclusions,
and preservation of unrelated staged VFS edits.

Initial `a` control states reproduced the forward denial, but the reverse
states exposed a fixture expectation error: an unexpectedly admitted image
was told to expect default W^X. Final `b` probes expect requested RWX whenever
an image starts, allowing the reverse controls to prove the unwanted grant
and reach status 38. Initial logs and artifacts remain preserved. Final
controls, focused/cumulative native suites and Linux runs all use the corrected
probe artifacts.

Concurrent remount timing, dynamic ELF interpreters, ARM translation execution,
credential transitions, combined error ordering, broader MAC/W^X combinations,
relative paths through inherited directory descriptions with divergent flags,
persistent/overlay integration, allocation-flatness and desktop performance
remain outside this qualification. Full OCI/rootless acceptance and roadmap
section 17 remain in progress.
