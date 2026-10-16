# Owned catalog normalization and release validation

Catalog normalization now orders the independently decoded catalog's own
buffers. A successful `catalog_recipe` result owns its architecture list,
imports, selectors and complete nested manifests; `close_decoded_catalog` retires
it. A refusal retires that same owner, including records already normalized
before a later source, permission, coverage, identity or closure failure.
Input JSON can be retired immediately after admission, and separate returned
catalogs do not share their owned storage.

Previously, normalization cloned nested collection buffers and retained the
original decoder envelope, temporary package lists, identity strings, source
splits and validation maps. Structural release validation also retained candidate
and license buffers, per-root search objects, policy permissions and fixed-root
selection arrays. The publisher uses `-gc none`, so these allocations survived
each validation, including validations performed by catalog composition.

The fix sorts owned buffers in place, validates source components through bounded
borrowed views, and explicitly retires temporary maps/arrays. Release closure
checks borrow package fields and license strings only for the duration of the
call, reuse one permission policy and fixed-root buffer, and retire each search
after its borrowed result has been checked. No input manifest is freed by the
closure checker.

The allocation tracker measures one complete normalization, then retires its
returned catalog or error. With the same retained V 0.5.2 compiler, the original
implementation's warmed probe and the corrected implementation report:

| Input | Before: retained bytes / allocations | After |
| --- | --- | --- |
| One import, successful validation | 23,549 / 49 | 0 / 0 |
| 64 imports, successful validation | 905,575 / 2,584 | 0 / 0 |
| One import, unresolved dependency | 15,191 / 48 | 0 / 0 |
| 64 imports, unresolved dependency | 903,997 / 2,565 | 0 / 0 |

The baseline retains its original fixture, publisher sources, binary, output and
hashes. Its probe runs ten independently tracked cycles. The maintained tests
run 1,000 independently tracked cycles for each of sixteen successful/refused
one/64-import cases, requiring zero retained bytes and allocations on every case.
Failures include unsupported architecture lists, unsafe sources, duplicate
identities, duplicate permissions, overlapping selectors, missing host coverage,
mixed shared/host variants and unresolved dependencies. Functional and sanitizer
runners use sixteen cycles without allocation tracking; their logs identify that
mode explicitly.

Independent-result tests retire the original JSON and another returned catalog,
then check complete sorted manifests, selectors, literal arguments, permissions,
associations and proprietary/firmware/license disclosures. Re-decoding canonical
output preserves its bytes. Existing catalog/composition/release, schema,
resolver, all five producer profiles and signed distribution CLI assertions
exercise publication and maintenance through the same code. Sanitizers repeat
normalization, release and composition suites, with leak detection disabled;
the native allocation tracker supplies the separate zero-retention checks.

```sh
v -no-skip-unused -o /tmp/catalog-normalize-check tests/packages/catalog-normalize-check.v
V=/path/to/reviewed/v /tmp/catalog-normalize-check /build/new-normalize-check

v -no-skip-unused -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/catalog-normalize-runtime-check tests/packages/catalog-normalize-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/catalog-normalize-runtime-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-normalize-arm
```

Repeat the guest command for `x86_64` with its matching kernel and a fresh state
directory. The current controller builds the guest, eight assertion runners and
the package CLI afresh, copies the supplied kernel, checks every required marker
and guest-initiated poweroff, then records twelve artifact hashes. Guests exercise functional
normalization, owned-result lifetimes, signed release admission and composed
offline maintenance; allocation tracking runs on the host. The additional
composition ownership runner and literal CLI/API checks are qualified in the
[composer report](composition-ownership-check.md); catalog workspace planning
is qualified in the [workspace report](catalog-plan-check.md), and bounded
materialization in the [import report](import-limits-check.md). The original receipts below
predate those additions and retain their seven-artifact scope.

## Qualification, 2026-10-16

All **35 final host build/run checks passed**, including 16,000 independently
tracked validations with zero retained bytes/allocations, three sanitizer
suites, all five producer profiles and signed CLI regression. Four controller
list/input/existing-directory checks also passed.

Both fresh target guests passed, with clean guest-initiated QMP shutdown:
**AArch64 40.5 seconds**, **x86-64 34.2 seconds**. Their kernels match the earlier
Software installed-root qualification; this change touches no kernel code.

The first guest builds stopped at link time because the composition CLI fixture
used `os.exec`, whose external capture helper was absent from raw-C target links.
That fixture now uses the existing process API. Both targets were rebuilt in
fresh directories, and the final host/sanitizer regressions exercise the same
literal CLI arguments through that helper.

- [Host receipt](results/2026-10-16/catalog-normalize-host.json),
  [tracked allocations](results/2026-10-16/catalog-normalize-memory.txt),
  [baseline](results/2026-10-16/catalog-normalize-baseline.txt) and
  [baseline artifact pins](results/2026-10-16/catalog-normalize-baseline.json).
- [Owned-result sanitizer](results/2026-10-16/catalog-normalize-asan.txt),
  [release sanitizer](results/2026-10-16/catalog-normalize-release-asan.txt),
  [composition sanitizer](results/2026-10-16/catalog-normalize-composition-asan.txt)
  and [signed CLI regression](results/2026-10-16/catalog-normalize-cli.txt).
- [AArch64 receipt](results/2026-10-16/catalog-normalize-aarch64.json),
  [serial](results/2026-10-16/catalog-normalize-aarch64.serial.txt) and
  [QMP](results/2026-10-16/catalog-normalize-aarch64.qmp.txt).
- [x86-64 receipt](results/2026-10-16/catalog-normalize-x86_64.json),
  [serial](results/2026-10-16/catalog-normalize-x86_64.serial.txt) and
  [QMP](results/2026-10-16/catalog-normalize-x86_64.qmp.txt).
- [Source/toolchain/artifact ledger](results/2026-10-16/catalog-normalize-toolchain.json)
  and [V evidence verifier](results/2026-10-16/catalog-normalize-retain.v).

This scope covers normalization and structural release validation after returned
owners/errors are retired. Composer planning/result ownership has a
[separate follow-up](composition-ownership-check.md). Payload acquisition,
complete builder/publication-helper lifetimes, graphical sessions, production
catalog enrollment and crash/device acceptance remain separate work in roadmap
section 14.
