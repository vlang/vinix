# Persistent ext2 overlay directory opacity

Directories recreated or renamed over a whiteout now persist
`trusted.overlay.opaque=y` in the backing filesystem before publication. After
clean volume and overlay remounts, opening or listing the recreated directory
continues to exclude its former lower children. Ordinary-user reads hide trusted
attributes; writes and removal retain the existing permission checks.

Internal attribute comparison reads a caller-owned backend snapshot and frees
it on every path. Missing or unsupported attributes mean no marker; another
read error conservatively excludes lower children. Backend writes report their
actual failure. If installing a new directory's marker fails, the private
candidate is discarded, its inode and alias retire through the normal grace period,
and the previous whiteout keeps its name. Generic creation retains ownership
of its name when the factory returns failure.

The qualification also exposed an ext2 link-count bug: replacing an upper
directory with a staged non-directory whiteout reduced the cached parent's
count without rewriting its on-disk inode. Commit `8fc078a86` persists that
destination-parent count in the backing transaction. The independent source
and generated-C review checked both architectures, transaction ordering,
borrowed attribute buffers, rollback and deferred name ownership. Its record
is retained in `build/development17-20261013/opacity-lifetime-review.md`.

## Reproduce

Build both kernels in isolated worktrees with the dependency symlinks described
in `AGENTS.md`. Use the [V guest controller](README.md) with fresh state
directories and a matching kernel:

```sh
V_C_ERROR_BUG_REPORT_DISABLED=1 USE_TCG=0 build-support/run-v-tool.sh \
  tests/overlay-rename/run.v --arch aarch64 \
  --kernel-dir /path/to/arm-worktree/kernel \
  --state-dir /path/to/fresh-arm-opacity --case opaque

V_C_ERROR_BUG_REPORT_DISABLED=1 USE_TCG=1 build-support/run-v-tool.sh \
  tests/overlay-rename/run.v --arch x86_64 \
  --kernel-dir /path/to/x86-worktree/kernel \
  --state-dir /path/to/fresh-x86-full --case opaque-full

e2fsck -f -n /path/to/fresh-x86-full/store.ext2
```

ARM uses HVF on macOS; select TCG when hardware acceleration is unavailable.
Root mounts the private filesystem and transfers its directories. Mutations run
as UID/GID 1000 with supplementary groups cleared and networking disabled.
`--case all` includes the ordinary opacity workload alongside concurrent
replacements, rejected backend renames and durable whiteout recreation.

`opaque` removes two lower directories containing files, then recreates one
and renames a new upper directory onto the other. It checks absent lower names,
complete directory listings, new content and trusted-attribute authorization
both before and after volume/overlay remount. Root checks backing markers,
ownership, permissions, unchanged lower content and the remounted upper
parent's link count against its actual named subdirectories.

`opaque-full` is separate from `all`. It fills a private 4-MiB ext2 volume to
one free block. A new staged directory consumes that block, so its attribute
allocation must fail with `ENOSPC`. Three attempts must leave the old whiteout
effective and restore exact free-block/free-inode counts after the grace period.
With zero free blocks, rename must preserve the source and hidden destination.
After the filler is removed, both operations succeed; a volume remount checks
their persistent markers and parent link count. Slab samples record retention
after the first and third failed mkdir. The controller owns and retires QEMU
before the volume is checked with read-only `e2fsck`.

## Evidence from 13 October 2026

Results are retained under `build/development17-20261013`:

| Run | Result |
| --- | --- |
| `opacity-arm-before-f`, `opacity-x86-before-f` | Saved whiteout-only kernels hide the lower children immediately, then reopen `opaque-create/a` after remount; assertion 152 fails. |
| `opacity-arm-links-before-b`, `opacity-x86-links-before-b` | Intermediate kernels preserve opacity but report six persisted parent links where four are expected; assertion 178 fails. |
| `opacity-arm-after-e` | All cases pass; 5,408/4,768 concurrent reads, zero missing names, listings or bad data; read-only `e2fsck` clean. |
| `opacity-x86-after-e` | All cases pass; 2,528/2,688 concurrent reads, zero missing names, listings or bad data; read-only `e2fsck` clean. |
| `opacity-arm-full-e`, `opacity-x86-full-e` | Three real storage failures each restore `1 -> 1` free blocks and `1005 -> 1005` free inodes. Rename refusal, recovery and remount checks pass; both read-only `e2fsck` checks are clean. |

All controls and final runs use identical committed fixture inputs. Kernels
were built from isolated `9b01dbca2` worktrees plus the filesystem patches in
`eefa7da3a`, `9a20f3de8`, `ddab4531c` and this opacity/parent-count work, excluding
concurrent sessions' unrelated changes. Both builds use the preserved
`compiler-f6358ec/v-from-bootstrap` compiler and link-shuffle seed 17.

| Input | SHA-256 |
| --- | --- |
| Before ARM kernel | `11646c9e5d4e2bcd6272844a4565fe346d908e6e32457e8de0e02d80480d4a59` |
| Before x86 kernel | `7e0835f67468bce795d5cc5d90a1d7654c878bedd4ac46cf7ebf255cd6b1397a` |
| Final ARM kernel | `74ca0751a29da0345bf3ce233dec8ee496ea22c1372d1af0cc5bc32a0dd8604d` |
| Final x86 kernel | `0e0121db04e49007221780c65457ae54feac8baba9e1209b05a76cfecfceaf07` |
| Core fixture | `2a7e0d13003b26cae6d2b0c51263dee16b86675a27ce5256f12180a05aba67e4` |
| Opacity fixture | `2c8afef0f3e69413a9675e2a1491e26539f32869283623de2a06d7841ddfedbf` |
| Storage-full fixture | `1e81ffb5c6db9616ffcbe4dba85619e7baafb0c5e30a6fd261cb88be1b0b4dae` |
| Declaration-only ABI header | `a3aace69b3786c3020f68bdd132a78400ded795e32ab8249e13b140791723a0f` |

The final kernels also pass `opacity-arm-http-b` and `opacity-x86-http-b`, with
19 independently validated authenticated HTTP/account/job/build records each.
`opacity-evidence-checked.log` verifies committed/copied input hashes, source identity,
control failures, final verdicts, filesystem checks and slab samples. The
allocation allowlist audit still fails: all 182 file/kind counts exactly match
the earlier whiteout audit. The allowlist was not expanded.

General overlay retention remains: after 2,000 replacements and grace periods,
both architectures retain 4,018 size-256 objects, 2,012 size-96 objects and 4,037
size-16 objects, matching the prior whiteout qualification. Across two further
failed opaque-directory creations, the failure samples retain four size-16
objects; all other size classes and the large-allocation count stay unchanged.
Disk rollback is verified; these samples do not establish leak-free overlay
operation. A separate AArch64 `ALLOC_TRACK=1` run with the same failed operations
names all four small objects as `resource__filesystem_stat` allocations reached
through `fill_statfs_resource` and `syscall_statfs`. Generated C confirms the
existing mutable-interface call allocates an unfreed 16-byte wrapper for each
of the four measurement calls. The marker/rollback paths have no retained site
in that interval. `opacity-arm-failure-tracked-c` and its named-sites log retain
the diagnostic inputs and output; read-only `e2fsck` is clean. Only the separate
diagnostic kernel's report threshold was lowered to one. Root coordinates
authorized allocation reads while the mutation worker remains UID/GID 1000.
The subsequent [filesystem-stat correction](statfs.md) removes the measured
interface leak; both ordinary space calls and failure samples then stay flat.

The final ARM kernel completed `ops,churn,cache,idle,apps,drag` in
`opacity-desktop-perf-b`. All 36 batches of 200 syscall operations retain zero
bytes per operation. Three 300-process churn batches retain zero bytes; BusyBox
retains one additional 16-KiB size-32 slab page with zero additional live objects.
A focused two-round repeat in `opacity-churn-repeat-a` records zero retained
bytes in all eight 300-process batches. The cache workload writes 32 MiB and
records 16 MiB cached; desktop process-count and duration checks pass.
`opacity-desktop-perf-b.json`, `opacity-desktop-shots-b`,
`opacity-desktop-serial.log` and `opacity-perf-evidence-checked.log` retain the results.
Both full and repeated runs' extracted boot-disk inputs match the final ARM hash.

Earlier setup failures, the intermediate parent-count filesystem errors and
the initial full-volume check made before delayed whiteout retirement remain
in separate logs. `opacity-desktop-perf-a` was stopped when the parent-count
fix required rebuilt kernels. None of those partial or failing runs is counted
as final acceptance.

This qualifies clean remount opacity and actual ext2 storage-exhaustion rollback.
Power-cut/crash recovery, broad overlay lifetime cleanup, unsupported rename
flags, foreign device encodings, full OCI delegation/security semantics and a
mainstream rootless runtime remain open. Roadmap section 17 remains incomplete.
