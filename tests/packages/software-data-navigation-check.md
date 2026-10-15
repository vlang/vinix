# Personal-data inventory cancellation and compact navigation

Software's Personal data page now keeps navigation and diagnostics in small
windows. Read-only inventory workers expose Stop and accept Cancel or Escape.
The child is killed and reaped, its pipes/output are retired, and partial or
complete-before-exit JSON is discarded. A stopped read leaves the inventory
unavailable for deletion review until a fresh successful read. The cached list
may predate a purge. Stopping a post-purge reload preserves the completed
deletion result for the next successful read.

Compact views keep Back/reload, cancellation of an idle confirmation, status
and failure access. Permanent deletion requires the full confirmation with its
exact ID, account scope and irreversible-loss warning. Selection/scroll survive
resize. Escape cancels an idle confirmation or returns an idle page to the
catalog. Full and compact views hide cancellation/navigation while an approved
purge is running, ignore injected actions and retain the existing close guard.
Purge failures retain their frozen confirmation and useful diagnostics for
retry/cancel. Root still cannot choose another account's data. Service,
arguments, authorization and protocol are unchanged.

The maintained [fixture](software_data_navigation_fixture.v) uses explicit stdin
barriers for partial/complete-before-exit inventories and approved purges. It
checks Stop/Cancel/Escape, kill/reap, output retirement, fresh-read requirements,
nonzero-exit refusal of complete inventory JSON, full/compact controls, stable
selection, protected purge success/failure, post-purge reload cancellation and
retained results, failure navigation, root
refusal and catalog query/filter retention. The `data-navigation-memory` mode
measures 1,000 complete wide inventory/select/full/compact render/confirm/cancel/
failure/progress/retirement cycles after warmup under `-gc none -manualfree
-d track_heap`. Existing progress frames are displayed when present; the purge
service's reporting is unchanged. The live status is cleared before sampling;
this does not measure whole-service or worker-process allocation freedom.

These are host headless UI checks. Existing [purge qualification](purge-data-check.md)
and [personal-data manager qualification](personal-data-check.md) retain their
scope. Ordinary graphical sessions, release publisher/catalog migration and
broader foreign-runtime acceptance remain separate release gates.


## Recorded results, 2026-10-15

All 27 focused compile/run checks passed: the complete Software functional
fixture and twenty-two allocation modes, plus ASan/UBSan functional and personal
data navigation allocation checks. The maintained Software-only distribution
driver passed independently with all twenty-two allocation modes. Navigation
retained zero tracked bytes across 1,000 complete wide inventory/select/full/
compact render/confirm/cancel/failure/progress/retirement cycles after clearing
the live status before sampling. Sanitizer leak detection was disabled; this
does not measure whole-service or worker-process allocation freedom.

Both full desktop architecture typechecks passed. Compiler, Software/protocol/UI
inputs, staged sources, binaries and logs are pinned. Initial fixture attempts
are retained separately. Service, command arguments, own-account authorization
and protocol behavior are unchanged. No new guest graphical or broader release
acceptance is claimed.

- [focused checks](results/2026-10-15/software-data-navigation-host.json)
- [summary](results/2026-10-15/software-data-navigation-host.txt)
- [Software and maintained driver](results/2026-10-15/software-data-navigation-ui.txt)
- [allocation modes](results/2026-10-15/software-data-navigation-memory.txt)
- [sanitizers](results/2026-10-15/software-data-navigation-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-data-navigation-desktop.txt)
- [initial attempts](results/2026-10-15/software-data-navigation-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-data-navigation-toolchain.json)
