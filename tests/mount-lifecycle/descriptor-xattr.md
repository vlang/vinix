# Inherited descriptor extended attributes

`fsetxattr` and `fremovexattr` now check the actual saved mount of a descriptor
target. An inherited writable description remains usable when the namespace
copy becomes read-only; an inherited read-only description gains no mutation
authority when the copy becomes writable. Pathname xattr operations retain
their namespace-aware attachment policy.

The existing `owned_path` identifies a pathname target and survives overlay
target copies. A descriptor target has no owned pathname. Its flag lookup now
uses a raw attachment reader, shared with the context-based raw flag reader
used by filesystem statistics and descriptor metadata. The reader retains its
existing mount lock/read/unlock body, with no backend callback under that lock.
No target field, heap owner, reference transition or free is added.

MAC, inode attributes, backend read-only/immutable checks, ACL/owner/write
permissions, trusted/security capabilities, overlay admission/copy-up,
notifications, name/value storage and all resource/descriptor cleanup remain.
[Linux v6.12 `fs/xattr.c`](https://github.com/torvalds/linux/blob/v6.12/fs/xattr.c)
uses the saved file mount for descriptor set/remove write admission.

Use `--case descxattrs` or `dx-0` through `dx-7`. Native `all` and Linux
`move-reference` include all eight cases:

| Case | Saved description and copied mount |
| --- | --- |
| 0 | Writable regular file; copy remounted read-only |
| 1 | Read-only regular file; copy remounted writable |
| 2 | Writable directory; copy remounted read-only |
| 3 | Read-only directory; copy remounted writable |
| 4 | Writable unlinked regular file; copy remounted read-only |
| 5 | Read-only unlinked regular file; copy remounted writable |
| 6 | UID/GID 1000 owner, writable file; copy remounted read-only |
| 7 | UID/GID 1000 owner, read-only file; copy remounted writable |

An ordinary data-read-only description is duplicated, the original closed,
and its namespace copied. Fresh descriptions use the copy's opposite flags.
User and trusted attributes start with a five-byte binary value containing
zeros. Each root case repeats replacement, an empty value, removal, creation,
`EEXIST` and `ENODATA` checks 64 times where a writable description exists.
Read-only replacement/removal returns `EROFS` and preserves metadata,
timestamps and values. Cases with a writable alias also verify read-only
denials for absent names. Get/list observations through both aliases agree;
regular data and unlinked link counts remain intact.

Owner cases run user attributes after dropping privileges. A forked foreign
UID/GID 1000 in root-owned cases receives `EACCES` for user attributes and
`EPERM` for trusted attributes on writable mounts, and `EROFS` on read-only
mounts. Owner cases also check trusted-attribute denials. Trusted values and
names stay hidden without administrator capability. Pathname replacement and
statfs checks establish the namespace copy's policy independently.

Evidence from 2026-10-15 is retained under `build/development17-20261013`:

| States | Result |
| --- | --- |
| `mount-descxattrs-{arm,x86}-dx-0-before-a` | Previous kernels wrongly return `EROFS` through inherited writable descriptions when the copy becomes read-only. |
| `mount-descxattrs-{arm,x86}-dx-1-before-a` | Previous kernels wrongly permit replacement through inherited read-only descriptions when the copy becomes writable. |
| `mount-descxattrs-{arm,x86}-descxattrs-after-a` | All eight corrected native cases pass. |
| `mount-descxattrs-arm-all-after-a` | The cumulative native mount suite passes, including pathname xattrs, inode flags, writers, access, filesystem statistics and descriptor metadata/timestamps. |
| `mount-descxattrs-{arm,x86}-linux-a` | The same probe executables pass the portable Linux 6.12.51 suite. |

| Architecture | Kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `6ad983da036f06d5cb37e8474be64981e3e8f6118abb5cad4128fd8ab4e83793` | `bb8bfc0ba2dbcf9bb4cd112c6efd6038d3a8faea2c8ca74ac5f89a8d16a8594d` |
| x86_64 | `f61ca36a7c90ee6965fdaf954889ff7720daf432486e438a879b1fdc2b43034f` | `d1e758ab0fcffd243081cfa0551c6fd24cc6d886c576a768c496839bdb42b719` |

`mount-descxattrs-{arm,x86}-input` preserves complete source manifests,
source snapshots, generated C, kernels and hashes. Builds use V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. Native ARM uses HVF/four CPUs; x86 uses TCG/two, with
1024 MiB. Linux uses HVF/TCG, two CPUs and 512 MiB. Controls, cumulative ARM
and Linux runs allow 600 seconds; focused native runs allow 900 seconds.
Networking is disabled. Controls and corrected runs share all twenty-five
fixture sources and the same probe/C artifacts.

The isolated builds extend the qualified descriptor-timestamp inputs, changing
only `kernel/fs/mount_policy.v` and `kernel/fs/xattr.v`. The baseline still
excludes pre-existing open-created descriptor hunks, staged pointer-return
spelling edits and earlier fcntl/descriptor/lock changes described in
[the writer qualification](writer-policy.md). The complete current checkout
kernel was not built or booted.

The assertion-enabled source/C audit compares all parsed namespace-qualified
functions after temporary/discard/loop-index normalization. The raw context
reader becomes a wrapper; the new attachment reader retains the complete old
locking body. The complete xattr authorization function matches after selecting
raw versus namespace-aware flags. Every other parsed function and target-copy
body remains unchanged. Receipt checks pin all twenty-five fixture sources,
controllers, artifacts, controls, native/Linux shared executable/C identity
and positive markers. The post-commit check preserves other sessions' edits.
Per-architecture `descriptor-xattr-c-audit.txt`,
`mount-descxattrs-source-evidence-a.log`, `mount-descxattrs-evidence-a.log`
and `mount-descxattrs-post-commit-a.log` retain the results.

Concurrent remount/cwd/namespace changes, broader ACL/MAC/security-attribute
combinations, `O_PATH` mutation/error ordering, anonymous resources,
filesystem-wide remounts and persistent/overlay integration remain open.
There is no allocation-flatness or mount reclamation claim. A new cumulative
native x86 run and desktop performance scenarios are outside this qualification.
Full OCI/rootless acceptance and roadmap section 17 remain in progress.
