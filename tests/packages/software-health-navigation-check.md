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
