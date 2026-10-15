# Policy read cancellation and compact navigation

Software's Organization policy view previously hid its navigation and
diagnostics in small windows, and pending reads/reviews ignored cancellation.
Public policy reads and proposals now expose Stop and accept Cancel or Escape.
The child is killed and reaped, its pipes/output are retired, and any unaccepted
proposal/fingerprint is discarded. Complete JSON received before exit is still
unaccepted output. The literal entered filename survives for fresh retry.

A stopped proposal returns to the known current settings. A stopped reload
leaves policy unavailable for review until a fresh read succeeds, because its
cached document may predate a completed save. The read-only reload after a save
can be stopped while preserving the saved result for the next successful read.
No cached restrictions are restored as current after a stopped reload.

Compact screens retain Back/Stop/Cancel, status, progress and failure access,
without exposing confirmation. Full review section/page state survives resize.
Escape cancels a completed proposal, blurs an idle editor or returns an idle
view to Deployment. Approved saves ignore these cancellation/navigation actions
and retain their close guard. Administrator approval remains cancellable before
submission. Full and compact views display existing progress frames when
emitted. Service, command arguments, authorization and protocol are unchanged.

The maintained [fixture](software_policy_navigation_fixture.v) uses stdin
barriers for partial and complete-before-exit policy reads/proposals, plus a
separate release file after credential submission closes stdin. The parent
publishes complete release bytes by rename. Service completion allows five
seconds of polling while requiring worker exit and unchanged response admission.
It checks kill/reap, frozen literal Unicode/metacharacter filenames, fresh policy
requirements, fresh retry, stable sections/pages, full/compact controls,
approval cancellation, protected approved success/failure, progress,
post-save reload cancellation, retained saved results and failure diagnostics.
It also verifies editor/Deployment navigation and catalog query/filter retention.
The `policy-navigation-memory` mode measures 1,000 complete document/review,
section/page, full/compact render, cancel/failure and retirement cycles after
warmup under `-gc none -manualfree -d track_heap`. The live status is cleared
before sampling; this does not measure whole-service or worker allocation
freedom.

These are host headless UI checks. Existing [policy qualification](policy-ui-check.md)
and [administrator qualification](admin-check.md) retain their scope. Ordinary
graphical sessions, release publisher/catalog migration and broader foreign
runtime acceptance remain separate release gates.


## Recorded results, 2026-10-15

All 26 focused compile/run checks passed: the complete Software functional
fixture and twenty-one allocation modes, plus ASan/UBSan functional and policy
navigation allocation checks. The maintained Software-only distribution driver
passed independently with all twenty-one allocation modes. Navigation retained
zero tracked bytes across 1,000 complete document/review, section/page,
full/compact rendering, cancellation, failure and retirement cycles after
clearing the live status before sampling. Sanitizer leak detection was disabled;
this does not measure whole-service or worker-process allocation freedom.

Both full desktop architecture typechecks passed. Compiler, Software/protocol/UI
inputs, staged sources, binaries and logs are pinned. Initial fixture progress,
synchronization and completion-timeout failures are recorded separately. The
fixture now emits valid activation counters, publishes its release marker by
rename and allows five seconds for service completion, still requiring worker
exit and unchanged response validation. Service, command arguments, administrator
transport and protocol behavior are unchanged. No new guest graphical or broader
release acceptance is claimed.

- [focused checks](results/2026-10-15/software-policy-navigation-host.json)
- [summary](results/2026-10-15/software-policy-navigation-host.txt)
- [Software and maintained driver](results/2026-10-15/software-policy-navigation-ui.txt)
- [allocation modes](results/2026-10-15/software-policy-navigation-memory.txt)
- [sanitizers](results/2026-10-15/software-policy-navigation-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-policy-navigation-desktop.txt)
- [initial attempts](results/2026-10-15/software-policy-navigation-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-policy-navigation-toolchain.json)
