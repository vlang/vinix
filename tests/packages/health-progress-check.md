# Installed health progress and cancellation

`vinix-package --progress health` sends flushed format-1 `verify` package frames
and a final `complete` frame to stderr. Stdout remains the complete human report.
`--json --progress health` retains the same JSON stdout response as `--json health`.
Integrity issues are rows in a successful complete report; fatal configuration,
state and locking errors still return nonzero with stderr diagnostics.

Software drains stdout and stderr independently in bounded batches, including
after child exit. It displays the current package and indeterminate progress.
The report is admitted only after exit 0, a complete typed report, an initial
scan frame followed by package frames and completion, and a package-frame count
matching the report. Unexpected, malformed, incomplete, out-of-order and
oversized stderr, or diagnostics after completion, refuse the report. Failure
details retain a bounded diagnostic tail separately from the JSON response.

**Stop inspection** and Escape kill and reap only this read-only worker. Partial
results and progress are discarded; Reload remains available, retaining search
and filter controls. Compact windows expose Stop. Window close also safely
retires the reader. No repair, package transaction or administrator approval is
started by inspection or cancellation. A report still leads to a fresh review
of the complete installed set before any repair is authorized.

The existing generic progress decoder retained 560 bytes in a measured 16-cycle
progress/report probe. The owned nonrecursive metadata reader now handles
progress, including partial-result retirement, strict types, escaped duplicate
keys, canonical counters and UTF-8. Path validation walks borrowed bytes without
allocating components. Format-1 valid frame shapes and phase meanings remain
unchanged for other package operations.

The [signed lifecycle probe](health-report-check.v) exercises real CLI stdout
and stderr on empty, healthy, simultaneously damaged, offline/revoked and
uninstalled states, plus fatal-state refusal. The [Software fixture](software_health_fixture.v)
checks split frames, live status, both-pipe completion, malformed/partial/late and
flooded output, mismatched counts, Stop/Escape process retirement, retry and
compact controls. `health-progress-memory` measures 1,000 fragmented
progress/report/render and invalid-progress/failure/retirement cycles after
warmup; the maintained [V driver](distribution-check.v) runs it alongside the ten
existing Software allocation modes. The [decoder tests](../../tools/packages/pkgprotocol/progress_test.v)
measure 1,000 valid, invalid and partially decoded events.

The [guest controller](health-progress-runtime-check.v) runs the actual CLI and
signed lifecycle on both committed-kernel architectures, together with core and
health-protocol assertions. It records seven artifacts per target, including
the CLI, probe and serial log. These checks establish package CLI behavior and
headless Software behavior. Publisher enrollment, broader catalog/runtime
release and an ordinary graphical guest session remain separate acceptance
gates in roadmap section 14.


## Recorded results, 2026-10-15

All 30 host compile/run checks passed, along with the independent maintained
Software-only driver, all eleven Software allocation modes and both full desktop
architecture typechecks. Progress protocol and complete Software progress/report
cycles retained zero tracked bytes over 1,000 iterations. Decoder and Software
functional/allocation ASan/UBSan checks passed with leak detection disabled.
Fresh committed-kernel QEMU TCG runs passed on AArch64 (20.2 seconds) and x86_64
(47.3 seconds), running the real CLI with separate stdout/stderr channels and
the signed lifecycle before orderly shutdown. These are CLI/headless Software
checks; ordinary guest graphical and runtime release gates remain open.

- [host results](results/2026-10-15/health-progress-host.json)
- [host summary](results/2026-10-15/health-progress-host.txt)
- [progress decoder](results/2026-10-15/health-progress-protocol.txt)
- [signed service](results/2026-10-15/health-progress-service.txt)
- [signed CLI channels](results/2026-10-15/health-progress-cli.txt)
- [Software and maintained driver](results/2026-10-15/health-progress-ui.txt)
- [allocation modes](results/2026-10-15/health-progress-memory.txt)
- [sanitizers](results/2026-10-15/health-progress-asan.txt)
- [initial allocation probe](results/2026-10-15/health-progress-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/health-progress-toolchain.json)
- [aarch64 receipt](results/2026-10-15/health-progress-aarch64.json)
- [aarch64 report](results/2026-10-15/health-progress-aarch64.txt)
- [aarch64 serial](results/2026-10-15/health-progress-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/health-progress-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/health-progress-x86_64.json)
- [x86_64 report](results/2026-10-15/health-progress-x86_64.txt)
- [x86_64 serial](results/2026-10-15/health-progress-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/health-progress-x86_64.qmp.txt)
