# Complete installed health reports

`Service.health()` and `vinix-package [--json] health` inspect every installed
package under one reader lock. Unlike fail-fast Verify, a damaged app does not
hide damage in another runtime, data dependency or launcher. Each owned row
records installed provenance and the first namespace, payload or registration
issue in that package. Complete reports return zero even with issues; fatal
configuration/state/locking errors return nonzero. Verify retains its existing
error behavior. A fresh image's empty observation creates no package state.

The inspection does not need catalog/history authentication or repository
access. It performs no repair, chmod, cache promotion, stage cleanup or personal
data operation. A clean row describes its own tree, not dependency health,
publisher trust, policy admission or permission to launch. Reports are transient
observations of a generation, not repair approval. Same-authority writes after
inspection and extraneous generation-global entries remain outside this scope.

The format-1 response requires complete typed header and row fields, sorted
unique IDs, canonical numbers, known issues and coherent bounded diagnostics.
The dedicated nonrecursive reader retires partial results on refusal. Up to
4,096 maximally escaped rows fit the 8 MiB reply limit. Diagnostics preserve
readable UTF-8, escape controls/invalid bytes and disclose truncation at 384 bytes.

Software lists issues first and pages the complete retained provenance and
diagnostic. It preserves the catalog selection when returning, blocks unrelated
actions while the report is open, refuses malformed/failing responses and
obtains a fresh repair review before authorization. Closing a read-only scan is
safe. Catalog loading and ordinary redraw do not trigger filesystem scans.

The maintained [public probe](health-report-check.v) signs and installs an app,
runtime, data package and utility, then creates simultaneous payload, namespace,
mode and launcher issues. It checks all four results, read-only serialization,
unchanged state/cache/history/recovery/personal data, unavailable/revoked catalog
independence, malformed-state refusal, fresh offline repair and clean uninstall
through both the service and real CLI. The [target controller](health-report-runtime-check.v)
runs core/protocol assertions and that signed lifecycle on both architectures.

Core scan/result retirement measures 128 healthy and 128 multiple-issue cycles.
Protocol tests cover maximum responses, malformed typed metadata and 1,000
complete/partial-invalid decode/retirement cycles. The actual Software fixture
checks asynchronous loading, ordering, pagination, modal isolation, response
refusal, review handoff and safe close; its allocation mode covers 1,000
decode/order/page/render/select/retire cycles. Whole-service allocation freedom,
guest graphical sessions, publisher enrollment and foreign runtime release are
not claimed.

The follow-up [status ownership checks](status-ownership-check.md) qualify
`Service.state()`/`verify()` result retirement and their public reader scratch.
The maintained guest suite also runs that fixture; the historical health-report
results below retain their original scope and artifact counts.


## Recorded results, 2026-10-15

All 42 host compile/run checks passed, together with the maintained Software-only
driver, all ten Software allocation modes and both full desktop architecture
typechecks. Scanner, decoder and Software health cycles retained zero tracked
bytes. Signed service/CLI and Software functional/allocation ASan/UBSan checks
passed with leak detection disabled. Fresh committed-kernel QEMU TCG runs passed
on AArch64 (19.8 seconds) and x86_64 (32.3 seconds), running core/protocol
assertions and the signed service lifecycle before orderly shutdown. These are
package maintenance checks; broader graphical and runtime release gates remain
open. Initial allocation and harness attempts are retained separately.

- [host results](results/2026-10-15/health-report-host.json)
- [host summary](results/2026-10-15/health-report-host.txt)
- [scanner/protocol assertions](results/2026-10-15/health-report-core.txt)
- [signed service](results/2026-10-15/health-report-service.txt)
- [signed CLI](results/2026-10-15/health-report-cli.txt)
- [Software and maintained driver](results/2026-10-15/health-report-ui.txt)
- [allocation modes](results/2026-10-15/health-report-ui-memory.txt)
- [sanitizers](results/2026-10-15/health-report-asan.txt)
- [initial attempts](results/2026-10-15/health-report-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/health-report-toolchain.json)
- [aarch64 receipt](results/2026-10-15/health-report-aarch64.json)
- [aarch64 report](results/2026-10-15/health-report-aarch64.txt)
- [aarch64 serial](results/2026-10-15/health-report-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/health-report-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/health-report-x86_64.json)
- [x86_64 report](results/2026-10-15/health-report-x86_64.txt)
- [x86_64 serial](results/2026-10-15/health-report-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/health-report-x86_64.qmp.txt)
