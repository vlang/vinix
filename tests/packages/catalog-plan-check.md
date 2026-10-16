# Owned catalog workspace planning

`pack-catalog` now keeps decoded catalog metadata, canonical bytes and the
unique-object budget map in one plan. Admission and budgeting complete before
opening prepared roots or creating destination parents. Successful builds and
handled failures retire that plan; each packed manifest and its comparison
buffers are also retired after checking against the reviewed lock.

The public `CatalogInfo` reply owns its directory, digest and architecture
strings independently of the plan and other replies. `close()` resets it and is
idempotent. Closing replies leaves published catalogs, manifests and objects in
place. The CLI closes its reply after writing the existing format-1 JSON.

Canonical locks/manifests, object deduplication and the original disk-budget
formula are preserved. Budgets include unique payload bytes, metadata, the
largest materialized package, 8 KiB for each budgeted entry and a 64 MiB reserve;
the temporary filesystem is checked separately. Invalid shared object lengths
now refuse during metadata preflight, before any prepared-root/destination work.

## Measurement and assertions

The baseline copies the original metadata/canonicalization/budget portion of
`catalog_build`, retiring the returned canonical string. Its warmed, ten-cycle
probe uses the same retained V 0.5.2 compiler and `-gc none -manualfree` tracker
as the maintained test. Each import contains two file pins, explicit
permissions/associations and proprietary/firmware/license disclosures.

| Planning case | Before: retained bytes / allocations | After |
| --- | --- | --- |
| 64 imports, shared object | 1,719,209 / 1,938 | 0 / 0 |
| 64 imports, 128 unique objects | 1,739,976 / 2,065 | 0 / 0 |
| 64 imports, conflicting final object length | 1,692,791 / 1,929 | 0 / 0 |

The maintained suite warms each case once, then requires zero retained bytes and
allocations across **128 separately tracked attempts in each of 14 cases**:
**1,792 attempts** in total. One/64-import fixtures cover shared and unique
objects plus schema, architecture, source depth, unresolved closure and object
length refusals. Returned errors are retired within the measured scope.
Functional/sanitizer/guest runners use four cycles per case and label this mode.

Independent-owner assertions retire source text, caller directory strings and
two plans before checking returned metadata, licenses, permissions and
associations. They compare canonical bytes against the original encoder and
space estimates against the original formula, including per-entry headroom.
Publication assertions close two actual replies twice and verify both complete
workspaces remain usable. Existing import tests retain space, payload tampering,
namespace replacement, destination race, failure cleanup, retry and reproducible
signed release/offline maintenance coverage.

```sh
v -no-skip-unused -o /tmp/catalog-plan-check tests/packages/catalog-plan-check.v
V=/path/to/reviewed/v /tmp/catalog-plan-check /build/new-catalog-plan-check

v -no-skip-unused -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/catalog-plan-runtime-check tests/packages/catalog-normalize-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/catalog-plan-runtime-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-catalog-plan-arm
```

Repeat for `x86_64` with its matching kernel and a fresh directory. The controller
builds six assertion runners and the package CLI. It requires planning, result
ownership, existing normalization/composition/release and real composition CLI
markers, plus guest-initiated poweroff. Receipts pin ten artifacts: kernel, PID1,
six runners, CLI and serial log. Allocation tracking runs on the host. The new
fixtures are metadata-only and do not execute synthetic application payloads.

## Qualification, 2026-10-16

All **33 host build/run checks passed**, including 1,792 zero-retention planning
attempts and both sanitizer suites. Four controller list/input/existing-directory
checks also passed. Fresh target guests passed with every required marker and
guest-initiated QMP shutdown: **AArch64 42.9 seconds**, **x86-64 43.9 seconds**.

- [33 host build/run checks](results/2026-10-16/catalog-plan-host.json),
  [tracked attempts](results/2026-10-16/catalog-plan-memory.txt),
  [baseline](results/2026-10-16/catalog-plan-baseline.txt) and
  [baseline pins](results/2026-10-16/catalog-plan-baseline.json).
- [Planning sanitizer](results/2026-10-16/catalog-plan-asan.txt),
  [catalog publication sanitizer](results/2026-10-16/catalog-plan-catalog-asan.txt)
  and [signed CLI regression](results/2026-10-16/catalog-plan-cli.txt).
- [AArch64 receipt](results/2026-10-16/catalog-plan-aarch64.json),
  [serial](results/2026-10-16/catalog-plan-aarch64.serial.txt) and
  [QMP](results/2026-10-16/catalog-plan-aarch64.qmp.txt).
- [x86-64 receipt](results/2026-10-16/catalog-plan-x86_64.json),
  [serial](results/2026-10-16/catalog-plan-x86_64.serial.txt) and
  [QMP](results/2026-10-16/catalog-plan-x86_64.qmp.txt).
- [Source/toolchain/artifact ledger](results/2026-10-16/catalog-plan-toolchain.json)
  and [V evidence verifier](results/2026-10-16/catalog-plan-retain.v).

Host checks cover all five publisher profiles, strict catalog decoding,
composition, release, signed CLI maintenance and planning/catalog ASan/UBSan
with leak detection disabled. The allocation tracker supplies the separate
retention measurement. Target runs use kernels pinned to earlier installed-root
qualification; this change touches no kernel code.

Zero-retention measurements cover metadata/budget planning and retired errors.
Results and actual workspace publication have functional/sanitizer coverage.
Acquisition, complete pack/import and shared filesystem-helper lifetimes,
production catalogs, graphical sessions and device/crash acceptance remain
separate work in roadmap section 14.
