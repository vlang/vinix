# Offline export navigation and review cancellation

Shrinking Software below the full export view previously replaced its controls
and diagnostics with a generic enlarge-window message. A pending read-only
review also had no working Stop action. Offline export now has a compact view
with current status, progress and failure access, plus phase-appropriate
navigation: Back to catalog for the form, Stop review for the resolving worker,
Cancel review for a completed proposal, or Back to review from package details.
Compact views expose no confirmation controls. Enlarging the window preserves
the proposal, full path disclosure and package review state.

Stop, Cancel and Escape may kill only an active read-only export review. They
reap the child, close its pipes, clear incomplete or unaccepted output, retire
review pages and fingerprints, and retain the destination and optional saved
deployment filename/digest. Retry invokes a fresh service review. A complete
JSON document received before process exit is still unaccepted and discarded
on Stop. A stopped worker cannot later supply a proposal or trigger export.

Approved exports remain protected by the existing close guard. Stop, Cancel,
Back and Escape cannot kill publication, even after resizing. Compact windows
show progress and status until success or failure, then restore Back and access
to retained failure details. Errors after publication preserve diagnostics that
the complete mirror exists and needs storage inspection.

The maintained [fixture](software_mirror_navigation_fixture.v) uses explicit
stdin barriers to hold workers at deterministic phases. It checks catalog and
saved-lock reviews, partial and complete-before-exit output, Stop/Cancel/Escape,
child retirement, frozen source/digest and destination retention, fresh retry,
path and package review, nested details, compact failure navigation, protected
publication and postpublication diagnostics. It preserves catalog search,
filter and selection. Its `mirror-navigation-memory` mode measures 1,000 compact
form/path/package/details/failure render, cancel and retirement cycles after
warmup with `-gc none -manualfree -d track_heap`.

This is a host headless UI change; the package service and protocols are
unchanged. [Locked export](locked-mirror-check.md) and
[saved export](software-snapshot-export-check.md) qualifications cover the
underlying publication and handoff behavior. These checks do not establish
ordinary graphical login/display-broker acceptance or close the wider
publisher, catalog and foreign-runtime release gates.


## Recorded results, 2026-10-15

All 21 final focused compile/run checks passed: the complete Software functional
fixture and sixteen allocation modes, plus ASan/UBSan functional and navigation
allocation checks. The maintained Software-only distribution driver passed
independently with all sixteen allocation modes. The navigation presentation
retained zero tracked bytes across 1,000 compact form/path/package/details/
failure render, cancel and retirement cycles after clearing the live status
before sampling. Sanitizer leak detection was disabled; this does not measure
whole-service or worker-process allocation freedom.

Both full desktop architecture typechecks passed. Compiler, Software, protocol
and UI inputs, staged sources, binaries and logs are pinned. An initial passing
run was followed by review adding nested package-details navigation; all final
checks use that complete implementation. Package service and protocol behavior
are unchanged. No new guest graphical or broader release acceptance is claimed.

- [focused checks](results/2026-10-15/software-mirror-navigation-host.json)
- [summary](results/2026-10-15/software-mirror-navigation-host.txt)
- [Software and maintained driver](results/2026-10-15/software-mirror-navigation-ui.txt)
- [allocation modes](results/2026-10-15/software-mirror-navigation-memory.txt)
- [sanitizers](results/2026-10-15/software-mirror-navigation-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-mirror-navigation-desktop.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-mirror-navigation-toolchain.json)
