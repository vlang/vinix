# Organization policy in Software

Open **Deployment → Organization policy** to browse the current offline setting,
allowed IDs, version pins, permissions, explicitly accepted proprietary licenses,
firmware permission and disk reserve. Empty allowlists mean unrestricted IDs
within trusted publishers; empty permissions and license lists mean no grants
and no proprietary license acceptance. Firmware permission permits packaged
payloads; it does not flash hardware.

**Review policy** reads an absolute file path through the existing public
`policy-review FILE` command. The review starts with the frozen complete filename
and supplies all previous/proposed settings and installed-app effects. Each
installed package includes its ID, name, version, kind, requested/dependency
status, publisher repository/key, license, proprietary/firmware flags and
before/after dependency-closure diagnostics. All values are available across
UTF-8-safe pages of at most fourteen 48-byte chunks. Tabs and previous/next
navigation preserve the complete review without formatting on every redraw.

**Confirm policy** sends the exact `policy-apply FINGERPRINT FILE` arguments;
ordinary sessions use the existing peer-bound administrator approval transport.
The UI checks the encoded request limit before asking for credentials. No shell
interprets filenames. Read/review require no password. Path editing, catalog and
external-launch actions cannot replace a pending review. Cancel before approval
writes nothing; an approved mutation blocks normal window close. A handed-off
review cannot be confirmed again. Apply errors invalidate cached policy and
require reload/review; success reloads persistent settings. The service rechecks
the file, configuration and installed state under its writer lock, and saves only
policy. Package generations, repository trust and personal data are retained;
deployment remains a separate reviewed operation.

Qualification covers:

- [Protocol assertions](../../tools/packages/pkgprotocol/policy_test.v): complete
  owned format-1 documents/reviews, provenance and flags, canonical sets/ranges,
  unknown/missing/duplicate/escaped keys, coerced fields, unsigned overflow,
  Unicode/UTF-8, trailing input and scalar/array bounds. The extracted common
  schema reader also passes the existing personal-data assertions. Clang
  ASan/UBSan pass with leak detection disabled.
- [Service assertions](../../tools/packages/pkgcore/policy_test.v): unchanged
  read-only review, dependency effects, explicit licenses/firmware, stale
  refusal and persistence checks, with added actual-producer/presentation-decoder
  contract assertions.
- [Actual Software fixtures](software_policy_fixture.v), compiled beside the
  production page and worker: public read/review, literal filenames, complete
  long-value paging, frozen confirmation, administrator approval/cancel/wipe,
  encoded request-size refusal, stale/invalid/error responses, reload and close
  guard. The existing Software suite passes. With
  `-gc none -manualfree -d track_heap`, 1000 wide-document, valid/invalid-review,
  page, redraw, cancellation and retirement cycles retain **zero tracked bytes**.
  The existing administrator, personal-data and window memory fixtures also
  retain zero. Both Linux target frontends accept the final Software sources.
- [Guest policy assertions](../accounts/guest/package_policy_admin.v): actual
  ordinary administrator and standard accounts can read/review; the standard
  role and wrong password cannot apply; changed policy files invalidate review;
  authorized apply returns the new policy with root-owned configuration and
  unchanged package state/repositories. Restoring the canonical original policy
  precedes the existing install/remove/rollback/disconnected-client/trust/audit
  assertions. Socket directories remain clean and passwords stay out of output.
  The [controller](admin-check.v) requires every marker and clean guest shutdown.

Run host fixtures with the pinned compiler and staged headless UI module through
[distribution-check.v](distribution-check.v), using `--software-only --direct-tests`
for the UI suite. Guest commands use fresh state directories and retained
production kernels as in [administrator qualification](admin-check.md). The
additional required marker is:

`PACKAGE POLICY ordinary-admin-standard public-read complete-impact literal-path password-role stale-file-refusal atomic-policy-only reload clean-runtime PASS`

These checks qualify service/protocol and headless page behavior. Ordinary
graphical login/display integration, real publisher enrollment and the complete
compatibility-runtime catalog remain roadmap release gates.

Both QEMU TCG guests passed: AArch64 **35.805 seconds**, x86_64 **128.282 seconds**, each with clean guest shutdown and eight verified input/serial hashes. Deadlines are functional, not performance qualification.

The initial ARM fixture incorrectly compared the canonical permission order with the unsorted default; it now compares the canonical original policy. The second ARM run passed policy assertions but missed the existing five-second detached-worker completion bound. Its final retry allows thirty seconds with the same state/verification assertions. The x86_64 passing fixture predates only that test deadline change. The first x86_64 attempt timed out at 600 seconds; the passing retry used a 900-second limit. Exact generated C witnesses preserve both passing fixtures.

- [AArch64 receipt](results/2026-10-13/policy-ui-aarch64.json), [serial](results/2026-10-13/policy-ui-aarch64.serial.txt), [QMP](results/2026-10-13/policy-ui-aarch64.qmp.txt).
- [x86_64 receipt](results/2026-10-13/policy-ui-x86_64.json), [serial](results/2026-10-13/policy-ui-x86_64.serial.txt), [QMP](results/2026-10-13/policy-ui-x86_64.qmp.txt).
- [Failed attempts](results/2026-10-13/policy-ui-attempts.txt), [host checks](results/2026-10-13/policy-ui-host.txt), [source/toolchain/artifact ledger](results/2026-10-13/policy-ui-toolchain.json).
