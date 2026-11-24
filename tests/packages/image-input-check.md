# Release-image package input preflight

`tools/packages/stage.v --check` validates the same configuration and optional
signed offline bundle selected for staging, then returns a reproducible format-1
JSON report. It leaves the image and any retained consumer state unchanged.
The check runs before target compiler lookup, service compilation, launcher or
action installation, and configuration/bundle publication.

The report includes the canonical target root, exact configuration digest and
effective trust/launch-account/organization-policy settings. Bundled repository
summaries record signed index digests, sequence/expiry, host/shared package counts,
proprietary/firmware counts, distinct object counts and deduplicated payload bytes.
It also records the existing conservative bundle disk budget and build reserve.
No current time, free-space observation or private capture path enters the report.

Configuration is marked `initialize` or `preserve`. Bundle handling is `publish`,
`preserve` for an identical verified destination, or `none` without a selected
bundle. Damaged, different, aliased, special and shared-write destinations refuse.
A fresh configuration appearing after preparation also refuses. The check cannot
overwrite any of those inputs or destinations.

Preparation performs the normal signature, complete closure, policy, licensing,
firmware, layout, payload and disk checks and creates a private authenticated
capture. Reporting verifies that capture again, checks existing destinations,
and closing the plan removes the capture. Source changes/removal after preparation
do not alter its report. Other configured remote sources are disclosed but not
fetched. The report summarizes inputs at the time of the check; a complete image
still needs normal staging and its later validation.

The public `ImageConfiguration.check_repositories(&ImageRepositories)` method
returns owned JSON text independent of both plans. Its format and fields are
documented in [SDK 1](../../tools/packages/SDK.md#check-release-image-package-inputs).
Callers free the text and close both plans.

## Assertions and reproduction

The [core fixture](../../tools/packages/pkgcore/image_check_test.v) checks:

- Both host configurations, two signed repositories, a disclosed remote source,
  complete effective trust/policy, exact configuration/index digests, architecture
  counts and explicitly licensed proprietary/firmware flags. Three package
  variants sharing bytes report one object per repository.
- Repeated byte-identical reports, absent image publication, private capture
  cleanup and independent report bytes after plans/source files are removed.
- Literal preservation of an existing configuration with noncanonical whitespace
  and retained consumer history; explicit no-bundle scope and zero bundle budget.
- Corrupt captures, unrelated plans, appeared consumer state and replaced roots.
  Stable captures still report correctly after source removal.
- Publish/preserve/none decisions; occupied fresh configuration and replaced
  destination files, aliases, FIFOs, directories, modes or payloads. Refusals
  preserve the concurrent/damaged bytes and allow retry after restoration.
- The actual staging CLI with `--check` first or last, literal paths, explicit
  options overriding invalid environment inputs, environment-only selection and
  byte-identical reports. Missing target compilers do not prevent checking.
  Normal staging still requires a compiler; missing/non-executable absolute
  compiler paths now report that error before tool compilation. Invalid selected
  architecture/configuration still refuses.

The [host driver](image-input-check.v) runs 22 build/test checks: the real stager,
eight assertion runners, the new runner under ASan/UBSan, the real package CLI
and signed CLI maintenance. Existing bundle/configuration/release/mirror/policy/
catalog/schema checks remain included. Sanitizer leak detection is disabled;
there is no whole-plan allocation-retention claim.

The [guest controller](image-input-runtime-check.v) builds the real staging tool
and five assertion programs. Both guests execute the actual compiler-free CLI
in addition to the report API, existing configuration/bundle consumers, catalog
builds and signed release maintenance. Every report/process marker and
guest-initiated poweroff is required. Each receipt pins nine artifacts: kernel,
PID 1, six binaries and raw serial output.

```sh
v -o /tmp/image-input-check tests/packages/image-input-check.v
V=/path/to/reviewed/v /tmp/image-input-check /build/new-image-input-host

v -no-skip-unused -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/image-input-runtime-check tests/packages/image-input-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/image-input-runtime-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-image-input-arm
```

Repeat for `x86_64` with its matching kernel and a new state directory. The
controller requires explicit QEMU TCG opt-in and a fresh state path. `--list`
creates no guest. Cross-toolchain setup follows the
[hardware controller requirements](../hardware-platform/README.md).

## Qualification, 2026-10-16

All **22 host build/run checks passed**, including ASan/UBSan and signed CLI
maintenance. Four controller list/input/existing-directory guards passed. Final
fresh guests completed every report/process marker and initiated QMP shutdown:
**AArch64 26.7 seconds**, **x86-64 25.7 seconds**, within the 180-second deadline.

The first guest attempts exposed an existing compiler-path diagnostic gap:
the pinned V library returns absolute executable paths without checking their
existence. Host normal staging reached the compiler invocation, while the guest
failed earlier looking up V. Normal staging now checks the selected compiler's
ordinary-file/executable status before looking up V. The final tests require
specific missing/non-executable compiler diagnostics; `--check` bypasses both
lookups. Those initial failed logs are retained separately from passing receipts.

- [Host receipt](results/2026-10-16/image-input-host.json),
  [all checks](results/2026-10-16/image-input-host.txt),
  [report/CLI assertions](results/2026-10-16/image-input-core.txt),
  [sanitizer](results/2026-10-16/image-input-asan.txt) and
  [signed CLI regression](results/2026-10-16/image-input-cli.txt).
- [AArch64 receipt](results/2026-10-16/image-input-aarch64.json),
  [serial](results/2026-10-16/image-input-aarch64.serial.txt) and
  [QMP](results/2026-10-16/image-input-aarch64.qmp.txt).
- [x86-64 receipt](results/2026-10-16/image-input-x86_64.json),
  [serial](results/2026-10-16/image-input-x86_64.serial.txt) and
  [QMP](results/2026-10-16/image-input-x86_64.qmp.txt).
- [First AArch64 diagnostic failure](results/2026-10-16/image-input-aarch64.first.serial.txt)
  and [first x86-64 diagnostic failure](results/2026-10-16/image-input-x86_64.first.serial.txt).
- [Source/toolchain/artifact ledger](results/2026-10-16/image-input-toolchain.json)
  and [V evidence verifier](results/2026-10-16/image-input-retain.v).

The verifier checks every final guest artifact hash, all report/process markers,
guest shutdown and unchanged kernel hashes from installed-root Software
qualification. This increment changes no kernel code. These checks cover package
input preflight and existing signed maintenance; complete image builds, production
publisher/catalog migration, graphical/runtime integration and broader device/
crash acceptance remain separate roadmap 14 work.

## Reviewed repository index pins

At `c67f4656d5fdfa3ee4cdc7cc045f7ea2d82117af`, `stage.v --require-index`
accepts the repository ID and digest from an offline release check. The input
fixture pins two bundled repositories on both architecture declarations.
It substitutes a newer valid release signed by the same key and confirms
that the pin refuses it before compiler lookup in both staging modes.
Restoring the reviewed release returns the exact original preflight report
with an unchanged target directory.

Normal and production stagers and the ASan/UBSan host suite passed. Process
leak detection was disabled. The application requirements and deployment
export suite also passed. The separate tracked ownership fixture reached
the same existing assertion on the baseline and changed code, with 3,056
retained bytes in 39 allocations in its first complete AArch64 case.

Real AArch64 and x86_64 staging built the target tools, published the pinned
bundle and reported the same readback digest. A second preflight recognized
the preserved destination. Both guests ran the new pin controls and finished
in 56.2 and 66.9 seconds with guest-initiated QMP shutdown. Early attempts exposed a test
process-runtime link mismatch and a Unix socket path limit. The final runs
used the existing process API and short state paths.

The [qualification archive](/Users/alex/.local/state/vinix/r14-staging-index-pins-7VujQQ/qualification.tar.gz)
contains the committed sources, signed inputs, staged roots, host checks,
and guest builds and logs. The independent archive checker verified all
230 sealed entries. Archive SHA-256 is
`7131bc001ce7383f3f62d2f10d1b32d69b7bdcf3f4e1259f84d02734178257f4`.

## Index files in desktop and ISO builds

At `b826b19c8120793c280eefa5d4d36060990a362a`, desktop staging and ISO planning
resolve `VINIX_PACKAGE_IMAGE_INDEXES` and its per-target overrides. The
previous stager admitted a bundle with a mismatched file digest in the
environment. The current stager refuses it on both target declarations.
The production and ASan/UBSan host fixtures also checked malformed, empty,
duplicate and symlinked files, along with explicit CLI precedence. Process
leak detection was disabled.

The cache suite checked effective target selection, opposite-target
isolation, and same-size content edits with restored timestamps. Both
production staging runs used a target-specific pin file, built the native
tools, and published exact signed index and application lock bytes.

ISO preflight refused a mismatched digest and a pin file supplied without
a bundle. Correct pins returned the original plan bytes. All 33 ISO receipt
cases passed for each target with the saved plan, including readback after
selecting a different pin file in the environment. The release script passed
syntax checks and its package-input selector passed the isolated pin-only
controls. ISO readback used fixture images.

Both guest preflight suites exercised the new file controls and recorded
guest-initiated shutdown, completing in 102.3 and 105.3 seconds for AArch64
and x86_64 respectively.

The [qualification archive](/Users/alex/.local/state/vinix/r14-index-file-handoff-NakJsn/qualification.tar.gz)
contains the signed fixtures, source revision, generated code, host and
guest results, and ISO controls. The independent checker verified all 779
sealed entries. Archive SHA-256 is
`1246330a99b163ca1b1d0456c0ac2755afa568b30029fb16aa2763c4f67534c5`.
