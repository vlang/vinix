# Health report navigation and completion

Software's compact **Health report** keeps Back and Reload available when idle,
with current status and retained failure access. It shows the complete generation
summary when space permits. Pending reads expose Stop inspection, live progress
and status, including the package being inspected. Compact views retain the
loaded query, issues filter, selected row, list position, search focus/selection
and detail page for enlarging the window. Repair still requires the full report
and a fresh authenticated proposal covering all installed packages.

Stop inspection, Cancel and Escape kill/reap a pending read, retire its descriptor,
and discard unaccepted report/progress/error bytes, package counts, detail pages
and truncation state. Reload must obtain a fresh observation. The query/filter,
catalog state and previous diagnostic remain available. A stray Stop or Cancel
after successful admission cannot discard the accepted report.

Completed checks show a waiting status until the service exits. A complete
stdout document and stderr completion frame alone do not admit a report. The
existing exit-zero, both-pipe drain, strict JSON/progress ordering and package
count checks remain in force. A late diagnostic/nonzero exit retains failure
access and no accepted report. Service arguments, authorization, output bounds,
protocol and final admission are unchanged.

The maintained [fixture](software_health_fixture.v) holds real children behind
stdin barriers during partial progress, live package inspection and complete
progress/report output before exit. It checks Stop/Cancel/Escape, kill/reap,
full/compact controls, frozen query/filter, duplicate and external-launch
isolation, fresh reload, late failure, final success and retained accepted
results. It checks compact status/summary/failure geometry, search/filter/row/
scroll/detail state across resizing, empty reports and return to the catalog.

The extended `health-progress-memory` mode measures 1,000 fragmented report,
admission, full/compact rendering, failure, partial/complete/oversized progress,
Stop and descriptor-retirement cycles after warmup. Descriptors in allocation
measurement are never started; functional checks use real children. The
`health-memory` mode also checks retained report detail paging across compact
renders. Both use `-gc none -manualfree -d track_heap` and retire live status before
sampling. This does not measure whole-service or spawned-worker allocation
freedom.

These are host headless checks. Existing [health progress qualification](health-progress-check.md)
retains its signed service/CLI and guest scope. Ordinary graphical sessions,
release publisher/catalog migration and broader runtime acceptance remain
separate release gates.


## Recorded results, 2026-10-15

All 31 focused compile/run checks passed: the complete Software functional
fixture and twenty-five allocation modes, plus ASan/UBSan functional, health
progress and health presentation allocation checks. The maintained Software-only
distribution driver passed independently with all twenty-five allocation modes.
The extended health progress cycles retained zero tracked bytes over 1,000
iterations after clearing live status; the health presentation mode also retained
zero bytes with compact detail-page retention. Allocation checks use unstarted
descriptors and no spawned workers; functional checks use real children.
Sanitizer leak detection was disabled. This does not measure whole-service or
spawned-worker allocation freedom.

Both full desktop architecture typechecks passed. Compiler, Software/protocol/UI
inputs, staged sources, binaries and logs are pinned. No failed execution
attempts were observed. Service arguments, authorization, output bounds, protocol
and final report/count/progress/exit admission are unchanged. No new guest
graphical or broader release acceptance is claimed.

- [focused checks](results/2026-10-15/software-health-navigation-host.json)
- [summary](results/2026-10-15/software-health-navigation-host.txt)
- [Software and maintained driver](results/2026-10-15/software-health-navigation-ui.txt)
- [allocation modes](results/2026-10-15/software-health-navigation-memory.txt)
- [sanitizers](results/2026-10-15/software-health-navigation-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-health-navigation-desktop.txt)
- [execution notes](results/2026-10-15/software-health-navigation-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-health-navigation-toolchain.json)

## Health, progress and registration decoder retention

At `5f13c2659b8bc9910b5d0a0df57f9a1d668eec6d`, health and registration
decoders append records by value. Health, registration and progress
validation and cleanup keep parser temporaries on the stack. The registry
fixture also frees error strings by value to keep its own descriptors out
of the measurement.

At `5dd8bb265`, the health and registration allocation loops reached the
tracker's record limit. The focused progress check retained 360,000 bytes
over 1,000 cycles. After the decoder fixes, the registry fixture still
retained 72,000 bytes in its error message descriptors. The fixture cleanup
removed those allocations.

On 2026-11-24, the final health, progress, registration reader and registry
checks each retained zero tracked bytes over 1,000 cycles. Both Software
health modes also retained zero tracked bytes over 1,000 cycles. All 27
protocol test files and the full host Software fixture passed. ASan/UBSan
passed for the three protocol checks and the registry fixture with process
leak detection disabled. The Software and registry fixtures linked
statically on AArch64 and x86_64.

The [retained archive](/Users/alex/.local/state/vinix/r14-installed-readers-5gOYSo/qualification.tar.gz)
contains the committed sources, baseline and fixed logs, generated code, and
target builds. The independent checker verified all 693 sealed files.
Archive SHA-256 is
`4b3854272a66eba7096c6c45f3c82bd828bbfc109cc14e2897ee03965c1cb794`.

## Maintenance from the compact catalog

At `abf919c408c4b5e3e1df888700ba457b1da7e183`, the idle compact Software
catalog opens Maintenance at 320×240 and larger. The regression check failed
at `ec6d02255` because the entry was missing at that size.

The host fixture drove all seven entries through their existing service
workflows. It checked both size thresholds, bounded controls after resizing,
status and retained failure access, input and active-worker guards, and
preservation of the catalog query, filter and selection on return. The full
host fixture also passed under ASan and UBSan with process leak detection
disabled. The allocation tracker measured zero retained bytes over 1,000
Maintenance open, render, resize and Back cycles. The existing health,
progress and view allocation modes passed. The Software guest fixture
linked statically for AArch64 and x86_64. Interactive checks ran on the host.

The [retained archive](/Users/alex/.local/state/vinix/r14-compact-maintenance-z4MZDb/qualification.tar.gz)
contains the committed sources, baseline and final logs, generated code and
target builds. The independent checker verified all 1,138 sealed files.
Archive SHA-256 is
`581a1b0907750c81db8ddfee2cbd9a0e43b3c3199653c5cbd2644830a2dabc47`.
