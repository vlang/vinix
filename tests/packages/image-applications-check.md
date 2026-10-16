# Advertised release-image application catalog

Release staging now accepts repeated `--require-app ID` options in both normal
and `--check` modes. The selected signed offline bundle must supply actual
applications for the selected architecture, and all required roots must resolve
together under the effective image policy before compiler lookup or image writes.
The point-in-time report includes a canonical format-2 deployment lock for the
exact selected roots and full dependency/runtime closure.

This closes an input-validation gap: checking every published version's closure
individually cannot establish that two advertised apps can coexist. A package
called `editor` of kind `data`, including a newer version, also cannot stand in
for an advertised editor application. Configured remote URLs are disclosed but
are not fetched or used to satisfy this offline release gate.

The lock records signed publisher IDs/keys, minimum sequences, exact versions and
architectures, and complete manifest digests. It is metadata for subsequent
ordinary deployment review, with current authentication/policy and fresh
authorization. Preflight neither installs apps nor saves/authorizes a deployment.
Normal bundle admission still checks every payload and declaration, including
policy/license/firmware settings outside the requested closure.

See [the SDK contract](../../tools/packages/SDK.md#require-an-advertised-application-catalog)
and [implementation](../../tools/packages/pkgcore/image_applications.v).

## Assertions and reproduction

The [fixture](../../tools/packages/pkgcore/image_applications_test.v) checks:

- Both target hosts, two signed bundles and a disclosed remote source. Required
  root order produces identical reports. Exact publisher/sequence/digest pins
  cover native apps, an explicit foreign runtime and shared data. A newer data
  variant cannot substitute for the required native app.
- Independent reports after both plans and source exports are removed. Calls
  without requirements explicitly report `applications_checked:false` and an
  empty target lock.
- Individually installable applications with incompatible runtime bounds refuse
  together with a dependency path. Missing IDs, a wrong-host app, runtime/data
  roots, duplicate/invalid/empty IDs, empty/oversized sets and absent bundles
  refuse without image publication; restoring valid inputs permits retry.
- Organization permission/allowlist/version-pin checks still apply during bundle
  admission. Corrupt captured objects refuse before app resolution; restoring
  bytes permits an identical report.
- Saved locks feed the real service's ordinary offline deployment review/apply
  and integrity verification on both target configurations. Installed versions,
  publishers and manifest digests match the report. Existing image trust and
  bundle report as preserved and produce the same lock; staged configuration
  and its consumer-state directory remain unchanged by the separate consumer.
- The actual CLI accepts repeated requirements in different positions. Normal
  staging and check mode reject invalid application sets before attempting a
  compiler; valid check mode requires no compiler, while valid normal staging
  proceeds to compiler admission. Missing bundles cannot pass through remote
  repository configuration alone.

The fixtures use structural native/foreign payloads and **never execute them**.
They qualify metadata installability, not Wine, translation or graphical runtime
behavior. The alternate-root consumer points its file URLs at the published
image export; a booted image uses its staged absolute file URLs directly.

The [host driver](image-applications-check.v) runs 28 build/run checks: the real
stager, eleven assertion suites, ASan/UBSan for the new fixture, real package CLI
and signed CLI maintenance. Sanitizer leak detection is disabled; there is no
whole-plan allocation-retention claim.

The [guest controller](image-applications-runtime-check.v) builds the actual
stager and eight assertion programs. All ten report markers, eight successful
processes and guest-initiated poweroff are required. Each receipt pins twelve
artifacts: kernel, PID 1, nine programs and raw serial output.

```sh
v -o /tmp/image-applications-check tests/packages/image-applications-check.v
V=/path/to/reviewed/v /tmp/image-applications-check /build/new-image-applications-host

v -path '@vlib|@vmodules|.|tests/hardware-platform' \
  -o /tmp/image-applications-runtime-check tests/packages/image-applications-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/image-applications-runtime-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-image-applications-arm
```

Repeat for `x86_64` with its matching kernel and a fresh state directory. Cross
compiler and QEMU prerequisites follow the [hardware controller](../hardware-platform/README.md).
List mode creates no guest; missing inputs and existing state paths refuse.

## Qualification, 2026-10-16

All **28 host checks passed**, including the new fixture under ASan/UBSan and
signed CLI maintenance. Four controller list/input/existing-directory guards
passed. Fresh guests completed all eight programs and every required marker,
then initiated QMP shutdown: **AArch64 43.0 seconds**, **x86-64 39.1 seconds**,
within the 180-second deadline. Both kernel hashes match the installed-system
Software qualification; this increment changes no kernel code.

Two development harness errors were corrected before those final runs. The
initial manual test incorrectly called `State.close()` on a transaction result,
whose fields are borrowed; the documented close contract applies to independent
state/verify observations. ASan identified the fixture's double free. The final
fixture closes only its owned verification result. The first broad drivers then
referenced a nonexistent `resolve_test.v`; they now run `resolve_search_test.v`.
Those build attempts never booted guests or produced passing receipts. Their
diagnostics are retained separately from final passing evidence.

- [Host receipt](results/2026-10-16/image-applications-host.json),
  [28 checks](results/2026-10-16/image-applications-host.txt),
  [app/CLI assertions](results/2026-10-16/image-applications-core.txt),
  [sanitizer](results/2026-10-16/image-applications-asan.txt) and
  [signed CLI regression](results/2026-10-16/image-applications-cli.txt).
- [AArch64 receipt](results/2026-10-16/image-applications-aarch64.json),
  [serial](results/2026-10-16/image-applications-aarch64.serial.txt) and
  [QMP](results/2026-10-16/image-applications-aarch64.qmp.txt).
- [x86-64 receipt](results/2026-10-16/image-applications-x86_64.json),
  [serial](results/2026-10-16/image-applications-x86_64.serial.txt) and
  [QMP](results/2026-10-16/image-applications-x86_64.qmp.txt).
- [Initial fixture ownership diagnostic](results/2026-10-16/image-applications-first-asan.txt),
  [first host build refusal](results/2026-10-16/image-applications-first-host-build.txt),
  [first AArch64 build refusal](results/2026-10-16/image-applications-aarch64.first-build.txt)
  and [first x86-64 build refusal](results/2026-10-16/image-applications-x86_64.first-build.txt).
- [Source/toolchain/artifact ledger](results/2026-10-16/image-applications-toolchain.json)
  and [V evidence verifier](results/2026-10-16/image-applications-retain.v).

The verifier checks all twelve artifacts in each guest receipt, all ten report
markers, all eight successful processes, guest shutdown and unchanged kernel
hashes. The ledger pins the reviewed compiler, source files, generated guest C,
binaries, logs and helpers. Product/test sources were unchanged throughout the
final host and guest runs; documentation was finalized afterward.

Production publisher enrollment, migration of the legacy advertised catalog,
full graphical login/presentation, broader application/runtime compatibility and
firmware/device/crash acceptance remain open in roadmap 14. No kernel code or
default publisher selection changes in this increment.
