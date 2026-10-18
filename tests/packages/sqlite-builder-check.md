# Complete SQLite publisher ownership

The SQLite publisher now retires template arguments/selectors, partial packed
inventories, canonicalization scratch, filesystem budgets and wrapped errors.
`SqliteProfileInfo.close()` releases independent reply metadata idempotently;
published locks and caller arguments survive. The CLI closes its reply after
encoding. Version admission uses stack components instead of allocating an
unused `version_parts` array, preserving validation diagnostics.

The unchanged synthetic catalog has SHA-256
`359e8ab218db656657a0b64cca63263e6b589397960b9503e953a65c10fc86e2`.
The [before fixture](results/2026-10-18/sqlite-builder-baseline.v) measured
**97,002 bytes / 337 allocations** retained by an ordinary successful build and
**103,018 / 335** after a ready-checkpoint refusal. Baseline reply disposal is
disabled because the previous API had no close operation. All other fixture
actions match the current complete-builder test.

The [complete builder fixture](../../tools/packages/pkgcore/sqlite_builder_ownership_test.v)
measures **eight attempts across 32 cases (256 calls)** under a 32-descriptor
limit. A public warm-up initializes process-wide JSON field metadata outside the
tracker. Each measured frame includes the implementation with controlled
checkpoint/space/flush hooks and reply/error disposal. Preparation, restoration
and public default-option canonical retries run outside the tracker. Callback
path/environment scratch is freed, and native writes avoid file-helper storage
in the measured frame.

Cases cover both version checks and the runtime compatibility range; missing
roots/architectures; invalid ELF target/mode and notices; output/scratch disk
space and query failures; refusal before imports, after each of four imports
and at the ready checkpoint; late ELF/notice/directory mutation; rewritten locks;
occupied/concurrent targets; flush/private-cleanup failures; and replacement of
the stage, inventory and lock directories. Every case requires zero retained
tracked V bytes/allocations, unchanged descriptors, exact canonical retry and
preserved source/competitor/recovery data. Errors after publication retain the
canonical saved lock.

The [metadata fixture](../../tools/packages/pkgcore/sqlite_profile_ownership_test.v)
measures **896 cycles** across zero through four imports and duplicate/empty
catalog refusal. It checks a runtime version of 1.1.0, borrowed caller versions,
canonical bytes after plan close and independently closeable replies after
caller argument retirement. These measurements exclude first-call JSON metadata
and do not establish allocation freedom for arbitrary publisher profiles or
unlimited fixture process lifetimes.

The [host driver](sqlite-builder-check.v) runs **47 build/test checks**, including
the production CLI, both SQLite owners, native/ELF/import/packing regressions,
all five publisher profiles, all 320 captured staging substitutions and six
ASan/UBSan suites. It pins sources/compiler and log/binary hashes, journals
completed suites atomically and validates pins before resuming. The exact
reviewed FFmpeg archive is mandatory before any compilation. Sanitizer leak
detection is disabled; retained V storage uses the independent tracker.

The [guest controller](sqlite-builder-runtime-check.v) builds four programs per
target. It requires all 32 builder cases, 896 metadata cycles, ordinary SQLite
profile tests, all 64 SQLite staging substitutions and three saved-output cases,
then clean guest poweroff. Each builder case has a separate process containing
all eight attempts. Four staging cohorts each contain sixteen substitutions.
There are 36 six-second before/after resource pairs. The controller defaults to a
600-second scenario deadline; the recorded complete retries request 900 seconds.
No kernel code or allocation lifetime changes here.

```sh
v -nocache -o /tmp/sqlite-builder-check tests/packages/sqlite-builder-check.v
VINIX_PROFILE_EXPORT_SOURCE=/reviewed/ffmpeg-8.0.1.tar.xz V=/path/to/reviewed/v \
  /tmp/sqlite-builder-check /build/new-sqlite-builder-host

v -nocache -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/sqlite-builder-runtime tests/packages/sqlite-builder-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/sqlite-builder-runtime --arch aarch64 --timeout 900 --kernel /build/aarch64-kernel \
  --state-dir /build/new-sqlite-builder-arm
```

Repeat for `x86_64` with its matching kernel and a new state directory. The
recorded x86_64 qualification uses the exact previously retained pre-gzip kernel
with an isolated V plain-USTAR media adapter; production image tooling stays
unchanged. Cross compilers, sysroots, firmware and Limine follow the
[hardware controller requirements](../hardware-platform/README.md).

## Recorded results, 2026-10-18

All **47 host build/test checks passed**, including all six ASan/UBSan suites,
all five publisher profiles and all 320 captured staging substitutions:
[receipt](results/2026-10-18/sqlite-builder-host.json),
[summary](results/2026-10-18/sqlite-builder-host.txt).
The [complete-call log](results/2026-10-18/sqlite-builder-sqlite-builder-run.txt)
contains all 32 zero-retention markers and exact canonical retries. The
[metadata log](results/2026-10-18/sqlite-builder-sqlite-owned-run.txt) confirms
all 896 cycles and independent reply lifetimes.

The separate [CLI check](results/2026-10-18/sqlite-builder-cli.v) passed against
the rebuilt production CLI: [result](results/2026-10-18/sqlite-builder-cli.txt).
It checks format-1 reply fields, catalog digests, paths containing spaces,
unchanged application metadata through a runtime-only update and refusal
preserving an existing lock.

The [journal guards](results/2026-10-18/sqlite-builder-journal-check.txt) refuse
changed source pins, damaged artifact pins and an existing fresh-run directory
before compilation. An intact completed journal resumes with its original
timings and artifact pins.

Both unchanged kernels passed all 32 builder cases, all 896 metadata cycles,
the ordinary SQLite profile tests, all 64 staging substitutions and the three
saved-output cases, then powered off cleanly:

| Target | Result | Time | Evidence |
| --- | --- | --- | --- |
| AArch64, QEMU TCG | PASS | 622.2 s | [receipt](results/2026-10-18/sqlite-builder-aarch64.json), [serial](results/2026-10-18/sqlite-builder-aarch64.serial.txt) |
| x86_64, QEMU TCG | PASS | 579.6 s | [receipt](results/2026-10-18/sqlite-builder-x86_64.json), [serial](results/2026-10-18/sqlite-builder-x86_64.serial.txt) |

Each guest records 36 before/after resource pairs; all 504 aggregate/category
`Denied` samples per guest are zero. These describe the bounded fixture runs,
without a kernel allocation-freedom or unlimited-process-lifetime claim.

The initial 600-second runs timed out after all builder and metadata cases
passed, with no assertion or resource-denial failure. x86_64 printed all four
staging-cohort results but missed final process completion and poweroff;
AArch64 was still in the staging checks. Their original
[AArch64 report](results/2026-10-18/sqlite-builder-aarch64.deadline.txt),
[serial](results/2026-10-18/sqlite-builder-aarch64.deadline.serial.txt),
[x86_64 report](results/2026-10-18/sqlite-builder-x86_64.deadline.txt) and
[serial](results/2026-10-18/sqlite-builder-x86_64.deadline.serial.txt) are retained
separately. The complete suites above used fresh guests with a 900-second
deadline, unchanged implementation and fixtures. The
[retry launcher](results/2026-10-18/sqlite-builder-guest-retry.v),
[original launcher](results/2026-10-18/sqlite-builder-guest-launch.v) and
[plain-USTAR adapter](results/2026-10-18/sqlite-builder-legacy-media.v) retain
the exact local configuration.

The [retainer](results/2026-10-18/sqlite-builder-retain.v) verifies the
[source/compiler/artifact ledger](results/2026-10-18/sqlite-builder-toolchain.json),
including baseline sources, host/guest binaries, both unchanged kernels, CLI
checks and the failed/passing raw evidence. The baseline predates this change
at `9a2cdc4e1`; its fixture bytes match the maintained complete-builder test.

This increment qualifies publisher storage and preserves the existing SQLite
profile contract. Synthetic ELF headers are never executed. Real upstream SQLite
database/library/terminal behavior is covered by the separate
[SQLite lifecycle qualification](sqlite-profile-check.md). Production publisher
selection/catalog migration, other complete profile/catalog/release owners,
graphical presentation and broader runtime/device/crash acceptance remain open.
