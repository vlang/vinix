# Cleanup review cancellation and compact navigation

Software's Clean up versions page now exposes Stop for a pending read-only
review and accepts Cancel or Escape. It kills/reaps the child, retires its
pipes/output and discards the unaccepted list and fingerprint. Even complete
JSON received before worker exit is unaccepted output. Confirmation requires a
fresh successful review. Escape returns an idle page to the catalog.

Compact views retain Back/reload, status and failure access, without permanent
deletion confirmation. Full views keep the first visible generation when the
number of rows changes on resize. Approved deletion retains its administrator
authorization and close guard, ignoring Stop/Cancel/Escape and navigation until
exit. Approval itself remains cancellable before credential submission. Existing
progress frames are displayed when present; service reporting is unchanged.

A stopped or failed post-cleanup review reload preserves the completed result.
The next successful review displays and consumes that result; a later reload
returns to ordinary guidance. This avoids losing completion information while
requiring fresh eligibility and its current fingerprint before another deletion.
Service arguments, protocol, authorization and deletion semantics are unchanged.

The maintained [fixture](software_cleanup_navigation_fixture.v) uses stdin
barriers for partial/complete-before-exit reviews, including all 4,096 allowed
generation IDs. Its wait requires the complete expected byte count before
cancelling the complete-output case. A separate file barrier, published by
rename after administrator credential submission closes stdin, holds approved
deletion. It checks Stop/Cancel/Escape, kill/reap and output retirement, fresh
review requirements, stable resize anchor, compact diagnostics, approval
cancellation, protected deletion success/failure, stopped and failed post-cleanup
reloads, retained/consumed results, empty-set refusal and catalog state retention.

The `cleanup-navigation-memory` mode measures 1,000 complete 4,096-generation
and empty review/decode/full/compact/resize/failure/progress/result/Back/retirement
cycles after warmup under `-gc none -manualfree -d track_heap`. The live status
is cleared before sampling. This does not measure whole-service or worker-process
allocation freedom.

These are host headless UI checks. Existing [reviewed cleanup qualification](reviewed-cleanup-check.md)
retains its real service and guest scope. Ordinary graphical sessions, release
publisher/catalog migration and broader runtime acceptance remain separate gates.


## Recorded results, 2026-10-15

All 29 focused compile/run checks passed: the complete Software functional
fixture and twenty-four allocation modes, plus ASan/UBSan functional and cleanup
navigation allocation checks. The maintained Software-only distribution driver
passed independently with all twenty-four allocation modes. Navigation retained
zero tracked bytes across 1,000 complete 4,096-generation and empty review/
full/compact/resize/failure/progress/result/Back/retirement cycles after clearing
the live status before sampling. Sanitizer leak detection was disabled. These
checks do not measure whole-service or worker-process allocation freedom.

Both full desktop architecture typechecks passed. Compiler, Software/protocol/UI
inputs, staged sources, binaries and logs are pinned. No failed execution
attempts were observed. Service arguments, administrator authorization, review
fingerprint and deletion semantics are unchanged. No new guest graphical or
broader release acceptance is claimed.

- [focused checks](results/2026-10-15/software-cleanup-navigation-host.json)
- [summary](results/2026-10-15/software-cleanup-navigation-host.txt)
- [Software and maintained driver](results/2026-10-15/software-cleanup-navigation-ui.txt)
- [allocation modes](results/2026-10-15/software-cleanup-navigation-memory.txt)
- [sanitizers](results/2026-10-15/software-cleanup-navigation-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-cleanup-navigation-desktop.txt)
- [execution notes](results/2026-10-15/software-cleanup-navigation-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-cleanup-navigation-toolchain.json)
