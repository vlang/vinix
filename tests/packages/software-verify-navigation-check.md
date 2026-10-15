# Verification cancellation and completion admission

Software's dedicated Verify installed scan now supports Stop verifying, Cancel
and Escape in full and compact windows. Stopping kills/reaps the read-only
worker, retires its pipes/descriptor, clears unaccepted progress and pending
bytes/output, and reports that no complete result was accepted. The catalog,
query/filter/selection, diagnostics and previous failure remain available for a
fresh scan. Starting verification leaves search focus, so pasted Escape cannot
trigger its cancellation.

A complete progress frame is provisional until service exit. The waiting status
survives subsequent human success text; that output and any late diagnostic are
retained for final admission. Existing exit-zero/final-completion checks admit
success; nonzero or incomplete results preserve failure diagnostics. A stray
Stop after retirement cannot discard an accepted result. Transaction and launch
workers can emit verify-phase frames without gaining these stop controls or
losing their close guards. Arguments, authorization, scan behavior and protocol
are unchanged.

The maintained [fixture](software_verify_navigation_fixture.v) holds real child
workers behind stdin barriers for fragmented initial progress, live scan and
complete-before-exit progress plus human success output. It checks Stop/Cancel/
Escape, kill/reap and buffer retirement, full/compact status/progress controls,
frozen catalog state, duplicate and external launch isolation, fresh retry, late
failure and final success, failure navigation and retained accepted results.
Refresh, reviewed apply and running-app workers emit verification frames while
Stop/Cancel/Escape remain ineffective and close guards remain active.

The `verify-navigation-memory` mode measures 1,000 fragmented/live/complete/wait/
full/compact/stop/failure/descriptor-retirement cycles after warmup under
`-gc none -manualfree -d track_heap`. It creates unstarted process descriptors
and never launches a child during allocation measurement; the functional checks
use real children. The live status is cleared before sampling. This does not
measure whole-service or spawned-worker allocation freedom.

These are host headless UI checks. Existing [Verify qualification](verify-progress-check.md)
retains its signed service/CLI and guest scope. Ordinary graphical sessions,
release publisher/catalog migration and broader runtime acceptance remain
separate release gates.


## Recorded results, 2026-10-15

All 30 focused compile/run checks passed: the complete Software functional
fixture and twenty-five allocation modes, plus ASan/UBSan functional and Verify
navigation allocation checks. The maintained Software-only distribution driver
passed independently with all twenty-five allocation modes. Navigation retained
zero tracked bytes across 1,000 fragmented/live/complete/wait/full/compact/stop/
failure/descriptor-retirement cycles after clearing the live status. Allocation
checks use unstarted descriptors; functional checks use real child processes.
Sanitizer leak detection was disabled. These checks do not measure whole-service
or spawned-worker allocation freedom.

Both full desktop architecture typechecks passed. Compiler, Software/protocol/UI
inputs, staged sources, binaries and logs are pinned. No failed execution
attempts were observed. Dedicated Verify cancellation and provisional completion
change only the UI lifecycle; service arguments, authorization, scan behavior,
protocol and final exit/completion admission are unchanged. No new guest
graphical or broader release acceptance is claimed.

- [focused checks](results/2026-10-15/software-verify-navigation-host.json)
- [summary](results/2026-10-15/software-verify-navigation-host.txt)
- [Software and maintained driver](results/2026-10-15/software-verify-navigation-ui.txt)
- [allocation modes](results/2026-10-15/software-verify-navigation-memory.txt)
- [sanitizers](results/2026-10-15/software-verify-navigation-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-verify-navigation-desktop.txt)
- [execution notes](results/2026-10-15/software-verify-navigation-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-verify-navigation-toolchain.json)
