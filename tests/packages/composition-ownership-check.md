# Owned catalog composition

The composer now validates and retires each complete input catalog before
reading the next. It streams selected records into one bounded JSON buffer,
then validates and canonically encodes the combined catalog. Temporary encoder
buffers, source prefixes, decoded inputs, merged catalog and planning metadata
are released on success and refusal. The existing per-input/full-output metadata,
64-profile, 4,096-package and source-depth limits still apply.

Published results own their paths, digest, architecture strings and source
records independently of input arguments and the temporary plan.
`CompositionInfo.close()` releases that metadata and resets the result; repeated
close is safe and leaves published files in place. The CLI retires its result
after writing the existing format-1 JSON reply. Strict and explicit-host
composition retain their architecture, identity, dependency and disclosure rules.

## Allocation measurement

The baseline copies the original planning body up to filesystem publication,
retiring its returned catalog/provenance strings. It uses the same pinned V
0.5.2 compiler, `-gc none -manualfree` and native allocation tracker as the new
planner. A large input contains two catalogs of 65 imports each: 32 apps per host
and one shared proprietary/firmware notice. The AArch64 output contains 66
imports. After earlier small-input probes warm encoder caches, the baseline
retains the following on each large planning attempt:

| Planning case | Before: retained bytes / allocations | After |
| --- | --- | --- |
| AArch64 selection | 5,100,202 / 5,209 | 0 / 0 |
| Second input has an unknown schema field | 1,774,532 / 1,745 | 0 / 0 |
| Combined package identity collision | 3,903,049 / 3,488 | 0 / 0 |
| Missing requested host in the second input | 1,940,699 / 2,601 | 0 / 0 |
| Combined source exceeds the depth limit | 3,911,433 / 3,488 | 0 / 0 |

The maintained ownership suite warms each case once, then runs **128 separately
tracked cycles for each of 16 cases**, requiring zero retained bytes and
allocations. The 2,048 attempts cover one/32 app variants per host, strict
composition, both explicit targets and schema, identity, host, depth and profile
ID refusals. Returned errors are retired inside the measured scope. Functional
and sanitizer runners use four cycles per case and label that mode explicitly.

Independent-owner assertions retire caller source arguments, one of two plans
and the second plan before checking the returned result. They check canonical
catalog and provenance SHA-256 against the saved legacy output, complete shared
license/firmware/proprietary disclosures and idempotent close. The legacy catalog
digest is `7cefe79d434695991a6fe7526d0aa45c91af7e5a90cb94921a8b06525aee24dd`;
the provenance digest is
`89376c4a33384af4e6b7149b5f9b57ceb37dd8606b05336f98158249edb084f6`.

## Reproduction and qualification

```sh
v -no-skip-unused -o /tmp/composition-ownership-check tests/packages/composition-ownership-check.v
V=/path/to/reviewed/v /tmp/composition-ownership-check /build/new-ownership-check

v -no-skip-unused -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/composition-ownership-runtime-check tests/packages/catalog-normalize-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/composition-ownership-runtime-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-ownership-arm
```

Repeat with `x86_64`, its matching kernel and a fresh directory. The guest
controller builds five assertion runners and the package CLI. The composition
runner must exercise the actual CLI, including literal paths, API equivalence,
unsupported hosts, argument counts and existing-output refusal; required markers
prevent silent omission. Each receipt pins nine artifacts: kernel, PID1, five
runners, CLI and serial log. Metadata-only ownership fixtures do not execute
their synthetic application payloads. Existing composition/release assertions
also exercise signed offline maintenance.

The current controller additionally runs workspace-plan, import-boundary and
guest-alias assertions and pins twelve artifacts. The receipts below retain this
qualification's nine-artifact scope; the [workspace](catalog-plan-check.md) and
[import](import-limits-check.md) follow-ups record the expanded runs.

The 2026-10-16 qualification passed **25 host build/run checks**, including the
2,048 tracked attempts, publisher schema, native/Apple profiles, distribution CLI
regression and AddressSanitizer/UndefinedBehaviorSanitizer ownership/composition
suites. Leak detection is disabled in sanitizer runs; the allocation tracker
provides the independent retention measurement. Four controller list/input/
existing-directory checks and both fresh target guests passed with required
CLI/API markers and guest-initiated QMP shutdown. Kernels match the earlier
installed-root qualification; no kernel source changes are involved.
The final AArch64 run took 39.7 seconds and x86-64 took 39.9 seconds. Initial
AArch64 source generation overlapped a source edit and failed; both targets were
rebuilt in fresh directories from the settled sources for these receipts.

- [Host receipt](results/2026-10-16/composition-ownership-host.json),
  [tracked attempts](results/2026-10-16/composition-ownership-memory.txt),
  [baseline](results/2026-10-16/composition-ownership-baseline.txt) and
  [baseline pins](results/2026-10-16/composition-ownership-baseline.json).
- [Legacy catalog](results/2026-10-16/composition-ownership-golden-catalog.json),
  [legacy provenance](results/2026-10-16/composition-ownership-golden-provenance.json),
  [ownership sanitizer](results/2026-10-16/composition-ownership-asan.txt),
  [composition sanitizer](results/2026-10-16/composition-ownership-composition-asan.txt)
  and [distribution CLI](results/2026-10-16/composition-ownership-cli.txt).
- [AArch64 receipt](results/2026-10-16/composition-ownership-aarch64.json),
  [serial](results/2026-10-16/composition-ownership-aarch64.serial.txt) and
  [QMP](results/2026-10-16/composition-ownership-aarch64.qmp.txt).
- [x86-64 receipt](results/2026-10-16/composition-ownership-x86_64.json),
  [serial](results/2026-10-16/composition-ownership-x86_64.serial.txt) and
  [QMP](results/2026-10-16/composition-ownership-x86_64.qmp.txt).
- [Source/toolchain/artifact ledger](results/2026-10-16/composition-ownership-toolchain.json)
  and [V evidence verifier](results/2026-10-16/composition-ownership-retain.v).

Zero-retention measurements cover composition planning and retired errors;
result independence/close and filesystem publication are functional/sanitizer
checks. Shared filesystem publication helpers have separate lifetime scopes.
This closes that composer ownership gap, while broader builder lifetimes,
production catalogs, graphical sessions and crash/device acceptance remain open
in roadmap section 14.
