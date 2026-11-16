# Sync-file information for current leaf exports

Vinix's sync-file descriptors previously returned `ENOTTY` for
`SYNC_IOC_FILE_INFO`. They now support the packaged Linux 56-byte header and
80-byte fence record: allocation-free count queries, pending/success/error
status, first completion timestamp, bounded names, reserved-field validation
and array-before-header output. Positive capacities copy exactly one current
leaf, regardless of excess capacity. Detailed queries allocate one fallible
80-byte owner and free it on every return path.

The comparison uses the packaged
[Linux implementation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/dma-buf/sync_file.c)
and [UAPI](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/include/uapi/linux/sync_file.h).
The audit now requires that exact header clean and retains it. Native status
and timestamp are sampled together under the first-completion lock, then the
lock is released before allocation/usercopy. This provides stronger coherence
than Linux's separate reads, with the same quiescent single-leaf result.

Private stubs report `stub/stub`; native queue leaves report `asahi/queue`,
matching underlying Asahi `JobFence`. Linux scheduler wrapper names remain
different. Generic native leaves report `vinix/fence`. The file name follows
unsigned-context/signed-sequence formatting, including signed minimum, 31-byte
truncation, NUL termination and preservation after the NUL. Published fence
metadata remains retained. The private provenance field can change metadata
layout; native slab/heap cost was not measured.

Validation passed:

- ASan/UBSan with stack-use-after-return detection: 18,032 new query cases
  covering count/detail capacities, pending prepared errors, first completion,
  losing duplicate completions, names and integer boundaries, zeroed records,
  OOM, null/partial user-copy faults, overlap, input mutation, completion and
  final descriptor close between outputs, and source replacement/removal.
  All 69,250 prior synchronization cases, 4,096 borrowed event nodes,
  4,103 geometry probes and 200 capture primitive cycles pass.
- The unmodified pre-feature DRM source from
  `90292aee51e76bf20bf5c982683c834aae9bfd44` passes the prior cases, then fails
  the first info query with `ENOTTY` (25). Its exact bytes and adapted runner
  are retained.
- Async submission, DRM wire/node and fence sanitizer regressions, 21 V test
  files, source/reference gates, strict allocation checks for 81 live ARM C
  helpers and negative checker selftests.
- Isolated ARM and clean x86 kernel builds from the same pre-feature revision
  plus six overlays: DRM dispatch, ioctl definitions, the new query helper,
  syncobj metadata, private stub initialization and the new snapshot helper.
  ELF/C pairs and overlays were retained before switching architecture; x86
  excludes AGX. Selected sources and reviewed native support match the private
  build. Independent source and ARM C lifetime review found no unresolved issue.

The unchanged global allocation allowance audit **still fails** for baseline
and feature: 383 ARM/289 x86 sites with identical per-file/per-kind counts.
Two new source files give 825/811 sources versus 823/809. No auditor or
allowance was changed. These checks do not establish native heap, leak,
multi-CPU or syscall concurrency behavior.

Fresh Omarchy `4bf10ed28342b597009dcf573ffc0d70b94b31e3` and packages
`4d076593b26175ccb483f8e86255d8185c342e28` match checked remote heads. Pins
remain Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`, and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Selected source gates pass;
the full verdict remains `not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-sync-file-info-20261116/`.
The canonical `bundle/` retains sources/references, kernels, C, test binaries,
raw logs, review and the unchanged complete typed inventory checker. Both
canonical and fully restored archive inventories are verified. `completion.txt`
binds sixteen non-report source paths and these two reports to the feature
commit. Earlier source-guard failures and the initial audit remain diagnostics.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `693feab8b3ccfc1e1ad262d24700f66672a747f5fb02acb7cae7e2c3bc18152f` |
| `bundle.tar.gz` | `764015d27593d8fa1b71ae79953185cab0d6147d6d6fb2ca8c34393fa416bc67` |
| `bundle/vinix-aarch64` | `dba27a97304e382d6b3b3a60f85790000d6fdb6f4e3ef3864e2dfcf49ca8e608` |
| `bundle/vinix-x86_64` | `f386c63942e6a35f16b5d1acdf3d9451af73ef4122981dd9a1c5e8609484867f` |

Merge/deadline ioctls, fence containers, full scheduler identity, descriptor
reservation/error precedence, modern ABI/Mesa integration, timeline chains,
callback waits, indexing/locking performance, reclamation and hardware behavior
remain open. No Vinix boot, GPU/firmware execution, hardware test, reboot, SSH
or deployment occurred.
