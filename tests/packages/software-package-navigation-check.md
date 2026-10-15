# Package review cancellation and compact navigation

The catalog's install, uninstall, update-all, repair and rollback reviews
previously ignored cancellation while their worker was running. Small windows
also hid navigation and diagnostics behind an enlarge-window message. Pending
read-only proposals now expose Stop review and accept Cancel or Escape. The
worker is killed and reaped; its pipes, unaccepted output, intent, proposal and
fingerprint are retired. Complete JSON received before child exit is still
unaccepted output. No changes can begin from a stopped proposal.

Catalog query, filter, selection and scroll survive for fresh retry. Completed
reviews accept Cancel or Escape. Escape from package details returns to the
same proposal/selection before canceling the review. Compact screens expose
Stop or Cancel, Back from catalog/review package details, catalog Reload when
idle, status, progress and failure access. They expose no confirmation control;
enlarging preserves the full proposal and selection. Search input cannot alter
catalog state during reviews or approved operations.

Approved apply workers and repository refresh ignore Stop/Cancel/Escape/Reload
and retain their normal close guard. Success reloads the catalog; failure
retires confirmation state and retains failure details. Read-only catalog loads
and other Software subflows keep their existing lifecycle rules. Authorization,
service and protocol contracts are unchanged.

The maintained [fixture](software_package_navigation_fixture.v) uses stdin
barriers for partial/complete-before-exit proposals and approved transactions.
It exercises all five operations, kill/reap, preserved catalog state, blocked
hidden search/confirmation, fresh retry, full/compact review/details navigation,
frozen apply intent despite selection changes, protected successful/failed
transactions and refresh, diagnostics and catalog reload. The
`package-navigation-memory` mode measures 1,000 complete cycles, each including
the catalog and all five operation reviews, full/compact rendering, nested
details, cancellation, failure access and retirement, after warmup under
`-gc none -manualfree -d track_heap`. The live status is cleared before sampling.
This does not measure whole-service or worker-process allocation freedom.

These are host headless UI checks. Existing
[administrator qualification](admin-check.md) and
[transactional rollback qualification](rollback-check.md) retain their scope.
Ordinary graphical sessions, release publisher/catalog migration and broader
foreign-runtime acceptance remain separate release gates.


## Recorded results, 2026-10-15

All 25 focused compile/run checks passed: the complete Software functional
fixture and twenty allocation modes, plus ASan/UBSan functional and package
navigation allocation checks. The maintained Software-only distribution driver
passed independently with all twenty allocation modes. Navigation retained zero
tracked bytes across 1,000 complete cycles, each covering the catalog and all
five operation reviews, full/compact rendering, nested details, cancellation,
failure and retirement after clearing the live status before sampling. Sanitizer
leak detection was disabled; this does not measure whole-service or worker-process
allocation freedom.

Both full desktop architecture typechecks passed. Compiler, Software/protocol/UI
inputs, staged sources, binaries and logs are pinned. An initial fixture assertion
for the old two-element compact placeholder was replaced with behavioral recovery
checks and is recorded separately. Service and protocol behavior are unchanged.
No new guest graphical or broader release acceptance is claimed.

- [focused checks](results/2026-10-15/software-package-navigation-host.json)
- [summary](results/2026-10-15/software-package-navigation-host.txt)
- [Software and maintained driver](results/2026-10-15/software-package-navigation-ui.txt)
- [allocation modes](results/2026-10-15/software-package-navigation-memory.txt)
- [sanitizers](results/2026-10-15/software-package-navigation-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-package-navigation-desktop.txt)
- [initial attempts](results/2026-10-15/software-package-navigation-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-package-navigation-toolchain.json)
