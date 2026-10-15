# Repository read cancellation and compact navigation

Software's Configured repositories view previously lost its controls and
diagnostics in small windows. Its pending configuration and trust-review
workers also ignored Cancel and Escape. The view now exposes Stop for pending
read-only requests, Cancel for completed reviews and Back for the idle form,
with status, progress and failure access after resizing. Compact views expose
no confirmation and retain URL paging and review identity across resize.

Stop, Cancel or Escape can kill only a configuration listing or an unaccepted
enrollment/revocation review. The child is reaped and its pipes and output are
retired, including complete JSON received before exit. Review cancellation
clears the frozen intent, proposal, fingerprint and URL pages. Entered ID, URL
and key, and the previous valid list/selection remain available for a fresh
request. Escape blurs an idle editor first, then returns to the catalog.

Approved enrollment and revocation, and the following authenticated catalog
refresh, ignore these cancellation/navigation actions and retain the normal
close guard. The configuration reload after publication is read-only again.
A failed refresh keeps the distinct message that trust was saved and retains
its failure details. No trust, replay history, administrator or protocol
requirements change.

The maintained [fixture](software_repository_navigation_fixture.v) uses stdin
barriers to hold partial and complete-before-exit lists, enrollment/revocation
proposals, approved writes and catalog refresh. It verifies kill/reap, frozen
input, prior list/selection retention, literal Unicode/metacharacter URLs,
fresh retry, URL confirmation gating after resize, protected apply/refresh,
success/failure diagnostics and editor/catalog navigation. It also stops the
read-only configuration reload after a successful write, preserving the saved
trust result until a fresh reload can display it. The
`repository-navigation-memory` mode measures 1,000 complete configuration,
enrollment/revocation, URL paging, full/compact rendering, cancellation,
failure and retirement cycles after warmup with
`-gc none -manualfree -d track_heap`. It retires the current valid list and
status before sampling; this does not measure whole-service/worker allocation
freedom.

These are host headless UI checks. Existing
[configuration qualification](repository-config-check.md) and
[administration qualification](admin-check.md) retain their scope. Ordinary
graphical sessions, release publisher/catalog migration and broader foreign
runtime acceptance remain separate release gates.


## Recorded results, 2026-10-15

All 24 focused compile/run checks passed: the complete Software functional
fixture and nineteen allocation modes, plus ASan/UBSan functional and repository
navigation allocation checks. The maintained Software-only distribution driver
passed independently with all nineteen allocation modes. Navigation retained
zero tracked bytes across 1,000 complete configuration, enrollment/revocation,
URL paging, full/compact rendering, failure, cancellation and retirement cycles
after closing the current valid list and clearing the live status before
sampling. Sanitizer leak detection was disabled; this does not measure
whole-service or worker-process allocation freedom.

Both full desktop architecture typechecks passed. Compiler, Software/protocol/UI
inputs, staged sources, binaries and logs are pinned. The initial allocation
sample included the still-live final configuration; that fixture sampling error
is recorded separately. Service and protocol behavior are unchanged. No new
guest graphical or broader release acceptance is claimed.

- [focused checks](results/2026-10-15/software-repository-navigation-host.json)
- [summary](results/2026-10-15/software-repository-navigation-host.txt)
- [Software and maintained driver](results/2026-10-15/software-repository-navigation-ui.txt)
- [allocation modes](results/2026-10-15/software-repository-navigation-memory.txt)
- [sanitizers](results/2026-10-15/software-repository-navigation-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-repository-navigation-desktop.txt)
- [initial attempts](results/2026-10-15/software-repository-navigation-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-repository-navigation-toolchain.json)
