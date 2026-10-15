# Inherited descriptor metadata policy

`fchmod`, `fchown` and empty-path `fchownat` now check the actual mount saved in
the open description. Remounting a namespace copy read-only does not revoke an
inherited descriptor's original writable mount; making the copy writable does
not grant permission to mutate through an originally read-only description.
Backend read-only state still applies. Pathname `fchownat` retains its existing
namespace-aware lookup and policy.

The new helper reuses the locked raw mount-flag reader introduced for
`fstatfs`. Each affected syscall changes one read-only helper call. Existing
MAC checks, inode attributes, owner/capability checks, copy-up, persistence,
notifications, error cleanup and descriptor release remain. The change adds
no heap owner, reference transition or free. It does not serialize metadata
updates against concurrent remounts.

[Linux v6.12 `fs/open.c`](https://github.com/torvalds/linux/blob/v6.12/fs/open.c)
uses the file's saved path for `fchmod` and `fchown`, and the resolved path for
empty-path `fchownat`, with mount-write admission before inode mutation.

Use `--case descmeta` or `dm-0` through `dm-7`. Native `all` and Linux
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

An ordinary description opens read-only for data I/O, is duplicated, and retains
its mount after closing the original descriptor and copying the namespace.
Each case repeats `fchmod` and `fchown` through ordinary descriptions, and
empty-path `fchownat` through ordinary and `O_PATH` descriptions, 64 times.
Fresh descriptions exercise the copied mount's
opposite policy for linked targets. Successful requests change and restore
mode/ownership; refused requests preserve metadata and timestamps. Regular
files retain their data, and unlinked files retain a zero link count.

Root runs the regular/directory/unlinked cases. Foreign UID/GID 1000 is refused
with `EPERM` on writable descriptions and `EROFS` on read-only descriptions.
The owner cases drop privileges before the matrix, permit group changes to a
supplementary group on writable descriptions and reject assigning another UID.
Pathname chmod and statfs reports confirm the copied mount remains independent.
These tests do not qualify data writes through the read-only open descriptions.

Evidence from 2026-10-15 is retained under `build/development17-20261013`:

| States | Result |
| --- | --- |
| `mount-descmeta-{arm,x86}-dm-0-before-c` | Previous kernels wrongly return `EROFS` on an inherited writable description after remounting the copy read-only. |
| `mount-descmeta-{arm,x86}-dm-1-before-c` | Previous kernels wrongly permit chmod through an inherited read-only description after making the copy writable. |
| `mount-descmeta-{arm,x86}-descmeta-after-a` | All eight corrected native cases pass. |
| `mount-descmeta-arm-all-after-a` | The cumulative native mount suite passes, including inode flags, writers, access queries and filesystem statistics. |
| `mount-descmeta-{arm,x86}-linux-a` | The same final probe executables pass the portable Linux 6.12.51 suite. |

| Architecture | Kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `dac660e566641dc09cc446b7215c0c5a02944e4f370b88346486a07d59409532` | `dc009005040c33596a91aa5311a325cf0d6e8f6aeda52e1f38f6012d6fe56cb0` |
| x86_64 | `6b3f98a97cc4fbfcc6c151b629c94dec413d53d1c8ce13103386b5437a3a8ed4` | `0088ed394b12c36aee90e6209fe5b2412cefb3831bc06e40ecc683b285e90181` |

`mount-descmeta-{arm,x86}-input` preserves complete source manifests, source
snapshots, generated C, linked kernels and hashes. Builds use V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. Native ARM uses HVF/four CPUs; x86 uses TCG/two, with
1024 MiB. Linux uses HVF/TCG, two CPUs and 512 MiB. Controls, cumulative ARM
and Linux runs allow 600 seconds; focused native runs allow 900 seconds.
Networking is disabled.

The earlier fixture compilation failures remain in the `before-a` and
`before-b` directories; final controls and runs use the same corrected source
and executables. Completed boot images may be losslessly archived as
`test.iso.gz`, with decompression hashes checked before removing raw copies.
Identical historical kernel copies were deduplicated after verifying receipt
hashes and file modes; artifact paths and bytes are retained.

The isolated builds extend the qualified filesystem-statistics inputs by
changing only `kernel/fs/vfs.v` and `kernel/fs/mount_policy.v`. The baseline
still excludes the pre-existing open-created descriptor hunks, staged
pointer-return spelling edits and earlier fcntl/descriptor/lock changes
described in [the writer qualification](writer-policy.md). The complete
current checkout kernel was not built or booted.

The assertion-enabled source/C audit compares all parsed namespace-qualified
functions against the previous build after temporary/discard normalization.
Only the three metadata syscall functions change, each by one helper call.
The complete new helper equals the existing read-only helper after selecting
raw mount flags; every other parsed function remains unchanged. The receipt
audit pins all twenty-three fixture sources, controllers, artifacts, controls,
native/Linux shared executable/C identity and every positive marker. The
post-commit check accounts for the same three excluded open-created VFS hunks
and preserves other sessions' staged edits. Per-architecture
`descriptor-metadata-c-audit.txt`, `mount-descmeta-source-evidence-a.log`,
`mount-descmeta-evidence-a.log` and `mount-descmeta-post-commit-a.log` retain
the results.

Other inherited-descriptor policy families, concurrent mount/cwd/namespace
changes, filesystem-wide remount semantics, broader ACL/MAC/attribute cases,
persistent/overlay integration and rootless OCI acceptance remain open.
There is no allocation-flatness or mount reclamation claim. A new cumulative
native x86 run and desktop performance scenarios are outside this qualification.
Roadmap section 17 remains in progress.
