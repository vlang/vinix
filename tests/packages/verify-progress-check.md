# Software installation verification with progress

Software now exposes **Verify installed** beside Details. It starts the package
service's read-only Verify worker and streams existing format-1 progress frames.
Verification needs no administrator prompt, repository refresh or usable catalog.
Success preserves the list, filter and selection and stays visible instead of
triggering a reload. Failures retain their final diagnostic and paged Failure
details, including Repair / install guidance for damaged files/launchers.
Review screens do not expose this control. Closing during a scan stops that
reader; it does not start or cancel a package transaction.

`Service.verify` emits a scan-start `verify`, individual payload/launcher check
identities and `complete` only after all checks pass under its reader lock.
`--progress verify` exposes those events with human output. Existing plain and
JSON Verify output remain compatible, and JSON/progress cannot be mixed. Status
emits no verification events. Fresh empty scans do not create package state.
Verification covers installed bytes, canonical modes and generated launcher
records; it grants no publisher authority or launch permissions.

The [signed service/CLI probe](verify-progress-check.v) checks fresh and installed
scans, progress counters/identities, reader exclusion of a writer, legacy
text/JSON, and byte/mode/launcher failures with no completion or partial JSON
state. State, catalog and replay history must survive every failure. Restored
files retry normally. Verification also works offline with a damaged catalog
and replay history, revoked publishers and tighter policy, without rewriting
those records. `--before OLD_CLI` demonstrates the prior service's silent scan
and refusal of the CLI progress option.

[Core assertions](../../tools/packages/pkgcore/verify_test.v) check events and
failure boundaries, including an empty scan; their tracked build requires zero
retained bytes over 128 healthy/failed scan cycles. This measures scan scratch,
not the service's metadata reader, progress serializer or full application.

The [Software fixture](software_verify_fixture.v), compiled beside production
Software sources, checks button layout at the minimum window size, literal
worker arguments, no administrator/catalog prerequisite, progress fragmentation,
selection/filter preservation, success retention, missing or superseded
completion, nonzero exit after a completion frame, bounded output, detailed
failures, hidden review actions and safe close. The existing headless interaction
suite and memory modes remain active. Headless UI and typechecks do not claim
ordinary graphical-session execution.

```sh
vinix-package --progress verify
vinix-package --json verify
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/verify-progress tests/packages/verify-progress-check.v
/tmp/verify-progress /tmp/new-verification-work /path/to/vinix-package
```

The [target controller](verify-progress-runtime-check.v) runs core and signed
service assertions on both architectures using retained kernels. Writer
serialization and controlled parent directories remain required. Same-authority
writes after checks and owner/directory/ACL reconstruction stay outside the scan.
Broader public publisher/catalog, graphical-session and foreign runtime release
gates remain open.

## Recorded results, 2026-10-14

The retained previous service (`9d8068b2e`) emitted no verification progress,
and its CLI refused `--progress verify`. The final public probe passed fresh
and signed installed scans, reader/writer exclusion, canonical frame identities,
legacy text/JSON, and byte/mode/launcher failure/retry without partial state or
completion. Damaged catalogs/history and revoked publishers did not prevent
the read-only integrity scan.

Eight host assertion runners passed: verify, installed health, progress, service,
coordination, payload repair, review and state. Scan scratch retained zero bytes
over 128 healthy/failed cycles. Core/public probe and full headless Software
interaction checks passed clang ASan/UBSan with leak detection disabled and
undefined behavior fatal. The signed CLI lifecycle passed. Both full desktop
target configurations typechecked; 33 host compile/run/typecheck results are
retained. Initial state compilation and x86 ISO assembly exhausted host disk space;
completed unpinned images were retired and only those failed steps repeated.
The first seven passed runner records are retained without original timings.
The maintained Software driver separately passed all interaction checks,
eight existing memory modes and complete launcher fixtures.

Fresh QEMU TCG runs passed on AArch64 (11.7 seconds) and
x86_64 (19.2 seconds), each running core assertions and the
signed service probe before shutdown within 300 seconds. Retained committed
kernels keep concurrent kernel edits out of the tests. Receipts pin kernel, init,
both programs and serial output; generated C/build logs are pinned in the ledger.
Headless interaction/typechecks and service guest runs do not qualify ordinary
graphical sessions or foreign runtime/catalog release acceptance.

Evidence:

- [previous-implementation control](results/2026-10-14/verify-progress-baseline.txt)
- [host results](results/2026-10-14/verify-progress-host.json)
- [host checks](results/2026-10-14/verify-progress-host.txt)
- [core assertions](results/2026-10-14/verify-progress-core.txt)
- [initial disk-limited attempts](results/2026-10-14/verify-progress-attempts.txt)
- [public verification probe](results/2026-10-14/verify-progress-probe.txt)
- [sanitizers](results/2026-10-14/verify-progress-asan.txt)
- [signed CLI lifecycle](results/2026-10-14/verify-progress-cli.txt)
- [source/artifact ledger](results/2026-10-14/verify-progress-toolchain.json)
- [Software suite and memory modes](results/2026-10-14/verify-progress-software.txt)
- [Software sanitizers](results/2026-10-14/verify-progress-software-asan.txt)
- [arm64 desktop types](results/2026-10-14/verify-progress-desktop-arm64.txt)
- [amd64 desktop types](results/2026-10-14/verify-progress-desktop-amd64.txt)
- [aarch64 receipt](results/2026-10-14/verify-progress-aarch64.json)
- [aarch64 report](results/2026-10-14/verify-progress-aarch64.txt)
- [aarch64 serial](results/2026-10-14/verify-progress-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/verify-progress-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/verify-progress-x86_64.json)
- [x86_64 report](results/2026-10-14/verify-progress-x86_64.txt)
- [x86_64 serial](results/2026-10-14/verify-progress-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/verify-progress-x86_64.qmp.txt)
