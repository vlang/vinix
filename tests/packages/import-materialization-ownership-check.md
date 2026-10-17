# Prepared-root materialization ownership

Prepared-root materialization now retires its directory ancestry, directory
creation and file-opening scratch in manual-free builds. The ancestry stack
stores device/inode values, avoiding interpolated strings and implicit clones.
It releases superseded buffers when it grows. Parent construction uses the owned
POSIX directory helper with the original `0777` request, subject to umask.
Files use one explicitly closed native descriptor, initially mode `0600`, with
partial-write and interrupted-write handling. Final modes, source rechecks and
materialized SHA-256 comparison retain their existing behavior.

The [fixture](../../tools/packages/pkgcore/import_materialization_ownership_test.v)
measures `RootImport.copy`, including the ancestry collection's retirement.
It runs **16 attempts for each of 22 cases (352 calls)** under a 32-descriptor
limit. Every attempt recreates its output outside the tracker. Source roots and
optional pin maps belong to the caller; the measured call borrows them. No
prebuilt materialized output is reused for these measurements.

Cases include multiblock and empty files, missing nested parents, a 16-file
directory tree with empty descendants, guest-absolute and parent-component
aliases, pinned success and size/mode/digest refusal, directory cycles, special
files, eight checkpoint failures and two native creation refusals. Each case
requires zero retained V bytes and allocations and unchanged descriptor counts.
Corrected retries reuse partial output outside the measurement. Functional
checks cover exact bytes, empty directories, stripped special permission bits,
umask, existing parent modes and source preservation.

The preceding implementation retained **183 bytes / 2 allocations** per ordinary
or empty file, **13,980 / 28** with missing nested parents, **26,351 / 139** for
the 16-file tree or its guest alias, and **5,526 / 24** on a directory cycle.
The retained baseline fixture covers the original 20 cases; the two native
creation refusals and the stronger descriptor/functional checks were added after
capturing it. The fixture setup and input bytes for the shared cases are unchanged.

The [host driver](import-materialization-ownership-check.v) runs **55 build/test
checks**: production CLI, 20 assertion suites, signed CLI maintenance, tracked
materialization and native-profile diagnostics, and four ASan/UBSan suites.
It includes source mutation/retry, traversal bounds, lookups, ordinary imports,
direct packing, all five publisher profiles, captured profile/catalog exports,
composition and signed releases. Sanitizer leak detection is disabled; the
separate V tracker measures retained allocations.
Captured FFmpeg export checks require `VINIX_PROFILE_EXPORT_SOURCE` naming the
reviewed 8.0.1 source archive. The driver checks its exact length and SHA-256
before creating output or compiling tests; no source-pin check is bypassed.

The [guest controller](import-materialization-ownership-runtime-check.v) builds
eight programs for each target. It requires every materialization zero-retention
marker, 23 separate materialization case processes, all regression process and
source-consistency markers, and guest poweroff. Each materialization case keeps
all 16 attempts. As in the prior creation qualification, six-second intervals
record `/proc/kernel-resources` around the kernel's removed-node grace period.
The scenario deadline is 600 seconds. These bounded cohorts do not qualify an
unlimited fixture process or establish kernel heap behavior.

This boundary excludes complete private import workspace creation/retirement,
complete profile/catalog/release construction, consumer allocation freedom,
production publisher/catalog migration, graphical sessions and broader
runtime/device/crash acceptance. Roadmap section 14 remains open.

```sh
v -nocache -o /tmp/materialization-check tests/packages/import-materialization-ownership-check.v
VINIX_PROFILE_EXPORT_SOURCE=/reviewed/ffmpeg-8.0.1.tar.xz \
  V=/path/to/reviewed/v /tmp/materialization-check /build/new-materialization-host

v -nocache -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/materialization-runtime tests/packages/import-materialization-ownership-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/materialization-runtime --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-materialization-arm
```

Repeat with `x86_64`, its kernel and a new state directory. Cross compilers,
sysroot and Limine follow the
[hardware controller requirements](../hardware-platform/README.md).

## Recorded results, 2026-10-17

Both unchanged kernels passed all eight program groups, 23 materialization cases
and all 22 zero-retention markers:

| Target | Result | Time | Evidence |
| --- | --- | --- | --- |
| AArch64, QEMU TCG | PASS | 259.8 s | [receipt](results/2026-10-17/import-materialization-ownership-aarch64.json), [serial](results/2026-10-17/import-materialization-ownership-aarch64.serial.txt) |
| x86_64, QEMU TCG | PASS | 210.5 s | [receipt](results/2026-10-17/import-materialization-ownership-x86_64.json), [serial](results/2026-10-17/import-materialization-ownership-x86_64.serial.txt) |

Each guest records 23 before/after cleanup pairs. All recorded resource admission
`Denied` counters are zero. These samples describe the bounded qualification;
they do not establish kernel allocation freedom or an unlimited process lifetime.

The initial host run stopped at the captured FFmpeg export suite because the
required reviewed source archive had not been configured. Its diagnostic is
retained separately. The maintained driver now admits that input before any
compilation, and the corrected qualification used the exact reviewed archive.
Three controller guards pass: missing archive, correct-length archive with the
wrong digest, and an existing output directory all refuse before creating output
or compiling tests.

The corrected host run was subsequently interrupted after 29 checks had printed
PASS. The [continuation](results/2026-10-17/import-materialization-ownership-host-resume.v)
preserves those logs and binaries and journals the remaining checks with source,
compiler and artifact hashes. The first 29 receipt entries explicitly record
`completed_before_resume: true` and `seconds: -1`: their original timings were
lost with the interrupted driver's memory. These are retained passing outcomes,
not newly timed executions.
The [parallel continuation](results/2026-10-17/import-materialization-ownership-host-parallel.v)
uses the same pins and flags with three independent jobs at a time. It completes
compilation before starting run jobs, and saves each completed job separately.

All **55 host build/test checks passed**, including all four ASan/UBSan suites:
[receipt](results/2026-10-17/import-materialization-ownership-host.json),
[check summary](results/2026-10-17/import-materialization-ownership-host.txt).
The [tracked materialization log](results/2026-10-17/import-materialization-ownership-memory.txt)
records zero retained V bytes and allocations for all 352 attempts; the
[baseline](results/2026-10-17/import-materialization-ownership-baseline.txt)
retains the preceding measurements.

The complete native-profile diagnostic now retains **52,087 bytes / 323
allocations**, down from the preceding **138,349 / 557**. Its metadata-only
measurements remain zero, and the canonical catalog bytes are unchanged. See the
[current diagnostic](results/2026-10-17/import-materialization-ownership-native.txt)
and [preceding diagnostic](results/2026-10-17/workspace-creation-ownership-native.txt).
Full import workspace/profile construction is still an open ownership boundary.

The [retainer](results/2026-10-17/import-materialization-ownership-retain.v)
verifies the [source/compiler/artifact ledger](results/2026-10-17/import-materialization-ownership-toolchain.json),
including both guest images, the reviewed source archive, host binaries and
retained evidence. The final continuation also reverified every source/compiler
and completed-artifact pin before collecting this report.
