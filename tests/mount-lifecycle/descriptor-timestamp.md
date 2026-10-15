# Inherited descriptor timestamp policy

`futimens` and empty-path `utimensat` now check the actual saved mount when
their target comes from a held descriptor. An inherited writable description
remains usable when the namespace copy becomes read-only; an inherited
read-only description cannot gain timestamp mutation authority when the copy
becomes writable. Pathname and empty-path cwd targets retain their existing
namespace-aware policy. Backend read-only status still applies.

The timestamp operation already pins its descriptor or pathname resource and
copies the selected context. The change selects the existing descriptor
read-only helper when that held descriptor is present. MAC, inode attributes,
owner/write permissions, timestamp validation, resource preparation,
persistence rollback, notifications and all releases remain. No heap owner,
reference transition or free is added.

[Linux v6.12 `fs/utimes.c`](https://github.com/torvalds/linux/blob/v6.12/fs/utimes.c)
uses the saved file path for descriptor timestamps and mount-write admission
before updating inode times.

Use `--case desctimes` or `dt-0` through `dt-7`. Native `all` and Linux
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

An ordinary data-read-only description is duplicated, its original descriptor
closed, and the namespace copied. Separate `O_PATH` descriptions cover
empty-path timestamp updates. Fresh descriptions exercise the copied mount's
opposite policy for linked targets. Each case repeats three descriptor forms
and five time forms 64 times: explicit nanoseconds, null/current times, two
`UTIME_NOW` fields, omitted mtime and omitted atime. Successful updates verify
the requested or observed real-time values and preserve an omitted field;
denials preserve metadata and all timestamps. Alias observations agree.
Regular-file data, unlinked link counts and file identities are preserved.

Foreign UID/GID 1000 gets `EPERM` for explicit changes and `EACCES` for current
time changes on protected writable files, and `EROFS` on read-only mounts.
Owner cases drop privileges before updating times. Pathname chmod and statfs
checks establish the opposite copied-mount policy. The cumulative suite also
retains existing pathname/cwd timestamp checks.

Evidence from 2026-10-15 is retained under `build/development17-20261013`:

| States | Result |
| --- | --- |
| `mount-desctimes-{arm,x86}-dt-0-before-b` | Previous kernels wrongly return `EROFS` on inherited writable descriptions after remounting the copy read-only. |
| `mount-desctimes-{arm,x86}-dt-1-before-b` | Previous kernels wrongly permit timestamp updates through inherited read-only descriptions after making the copy writable. |
| `mount-desctimes-{arm,x86}-desctimes-after-a` | All eight corrected native cases pass. |
| `mount-desctimes-arm-all-after-a` | The cumulative native mount suite passes, including inode flags, writers, access queries, filesystem statistics and descriptor metadata. |
| `mount-desctimes-{arm,x86}-linux-b` | The same final probe executables pass the portable Linux 6.12.51 suite. |

| Architecture | Kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `0d9af4f71b6e6aa5320749f43dceb8397274d65eb12d2e23ed67768a895b4f23` | `3534d03254e1393f7c677ac5b314cb52bb963332f59419d2056e0fa0cb293ab1` |
| x86_64 | `c20562844d46e34f974133779fd7e61a6eeac75bc694be44550a9f2410ffae2e` | `695c0e78ca1309f1730d0e4bec6ed4e6158fff04936b44952bc0c296a12b473d` |

`mount-desctimes-{arm,x86}-input` preserves complete source manifests,
source snapshots, generated C, kernels and hashes. Builds use V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. Native ARM uses HVF/four CPUs; x86 uses TCG/two, with
1024 MiB. Linux uses HVF/TCG, two CPUs and 512 MiB. Controls, cumulative ARM
and Linux runs allow 600 seconds; focused native runs allow 900 seconds.
Networking is disabled.

The first Linux fixture mislabeled explicit nanoseconds as a `UTIME_NOW`
permission test; final `before-b` sources correct that setup. Earlier Linux,
early artifact-read and audit attempts remain preserved. The successful
source audit additionally normalizes the generated loop index renumbered by
the new conditional; complete function comparison still checks every line.
Final controls and runs share all twenty-four sources and the probe/C artifacts.

The isolated builds extend the qualified descriptor-metadata inputs, changing
only `kernel/fs/vfs.v`. The baseline still excludes the pre-existing
open-created descriptor hunks, staged pointer-return spelling edits and earlier
fcntl/descriptor/lock changes described in
[the writer qualification](writer-policy.md). The complete current checkout
kernel was not built or booted.

The assertion-enabled source/C audit compares all parsed namespace-qualified
functions against the prior build after temporary/discard/loop-index
normalization.
Only the timestamp operation changes. The complete function matches after
selecting the descriptor/path read-only helper; its existing read-only error
cleanup is retained. Receipt checks pin all twenty-four fixture sources,
controllers, artifacts, controls, native/Linux shared executable/C identity
and all positive markers. The post-commit check accounts for the same three
excluded open-created VFS hunks and preserves other sessions' staged edits.
Per-architecture `descriptor-timestamp-c-audit.txt`,
`mount-desctimes-source-evidence-c.log`, `mount-desctimes-evidence-a.log` and
`mount-desctimes-post-commit-a.log` retain the results.

Concurrent remount/cwd/namespace changes, anonymous resources, `O_PATH` with a
null path, both-fields-omitted no-op semantics, combined error ordering,
filesystem-wide remounts, broader ACL/MAC/attribute cases and persistent/overlay
integration remain open. There is no allocation-flatness or mount reclamation
claim. A new cumulative native x86 run and desktop performance scenarios are
outside this qualification. Full OCI/rootless acceptance and roadmap section
17 remain in progress.
