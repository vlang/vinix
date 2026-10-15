# Deployment review cancellation and compact navigation

Software's Deployment form and proposals previously lost their controls and
diagnostics in small windows, and pending read-only proposals had no working
Stop action. The compact view now retains status, progress and failure access,
with Back to catalog for the form, Stop review for the pending proposal, Cancel
review for a complete proposal, and Back to review from package details. It
exposes no confirmation control; enlarging preserves the reviewed plan.

Stop review, Cancel and Escape can kill only a pending read-only
`deployment-review` worker. They reap it, close its pipes, discard partial or
complete-but-unaccepted output, and retire the proposal/fingerprint. The form's
literal filename survives for a fresh review. A stopped worker cannot later
publish a proposal or trigger a deployment.

Approved installs, updates, repairs and removals keep running until they finish.
Stop, Cancel, Back and Escape cannot kill `deployment-apply`, and its close guard
stays active after resizing. Both ordinary deployments and empty deployments
with complete removals use these rules. Failures retire confirmation state and
retain useful diagnostics and Back/Failure details controls. Snapshot saving
and installed-audit views retain their own controls and routing priority.

The maintained [fixture](software_deployment_navigation_fixture.v) uses explicit
stdin barriers to hold partial and complete-before-exit review output and active
transactions. It exercises Stop/Cancel/Escape and child retirement, frozen
literal Unicode/metacharacter filenames, fresh retry, full and compact views,
empty removal plans, nested details, active-transaction protection, failures,
success and catalog reload, and snapshot/audit routing. The
`deployment-navigation-memory` mode measures 1,000 cycles covering normal and
empty plans, including full and compact form/review/details/failure rendering,
cancellation and retirement, after warmup with `-gc none -manualfree -d track_heap`.
The full form now reserves space for all four actions and its progress/failure
controls; the measured redraw path caught and eliminated retained frame buffers
when the previous ten-element array grew.

This changes the host headless UI and leaves the service and protocols
unchanged. [Deployment UI qualification](deployment-ui-check.md) and
[service/runtime qualification](linux-runtime-check.md) retain their existing
coverage. These checks do not establish ordinary graphical
login/display-broker acceptance or close wider publisher, catalog and
foreign-runtime release gates.


## Recorded results, 2026-10-15

All 23 focused compile/run checks passed: the complete Software functional
fixture and eighteen allocation modes, plus ASan/UBSan functional and deployment
navigation allocation checks. The maintained Software-only distribution driver
passed independently with all eighteen allocation modes. Navigation retained
zero tracked bytes across 1,000 cycles covering normal and empty deployments,
full and compact idle-form/review rendering, nested details, failure access,
cancellation and retirement after clearing the live status before sampling.
Sanitizer leak detection was disabled; this does not measure whole-service or
worker-process allocation freedom.

Both full desktop architecture typechecks passed using the current checkout.
The initial full-form frame-buffer leak was fixed by reserving space for every
control. That failure and an unrelated transient main.v missing-import error
are recorded separately; main.v was left untouched by this change. Compiler,
Software/protocol/UI inputs, staged sources, binaries and logs are pinned.
Service and protocol behavior are unchanged. No new guest graphical or broader
release acceptance is claimed.

- [focused checks](results/2026-10-15/software-deployment-navigation-host.json)
- [summary](results/2026-10-15/software-deployment-navigation-host.txt)
- [Software and maintained driver](results/2026-10-15/software-deployment-navigation-ui.txt)
- [allocation modes](results/2026-10-15/software-deployment-navigation-memory.txt)
- [sanitizers](results/2026-10-15/software-deployment-navigation-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-deployment-navigation-desktop.txt)
- [initial attempts](results/2026-10-15/software-deployment-navigation-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-deployment-navigation-toolchain.json)
