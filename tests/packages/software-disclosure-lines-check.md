# Native Software disclosure rendering

The native desktop draws one line for each label. Package details, organization
policy, health reports, deployment checks and saved deployment receipts formerly
placed a whole prepared page into one multiline label. They now share the failure
view's individual-line renderer. Every prepared line is a separate borrowed
monospace label; redraw creates no text copies. The frame buffers include all
fourteen lines and their controls, so extra labels do not grow an unretired frame
allocation under manualfree.

Full-width package, policy and receipt pages keep their existing 48-byte payload
fragments and bullet/continuation prefixes. Health and deployment-check side
panels prepare 24-byte UTF-8 fragments plus prefixes, fitting the narrower
minimum-width panel. Complete descriptions, keys, permissions, licenses, paths,
counts and diagnostics remain available across pages. Row identity, selection,
filters, reviewed fingerprints, confirmation controls, captured filenames,
service arguments, authorization, output admission and protocol are unchanged.

The maintained [fixture](software_details_fixture.v) checks all catalog pages
and every package-detail section for install, remove, upgrade, repair, deployment,
rollback and mirror reviews at both minimum and wider full-window sizes. Each
rendered line must exactly match the prepared page, be valid UTF-8, fit its byte
budget and occupy the expected single-line frame. It checks every selected-row
health/deployment page, saved receipt page and current/proposed policy page,
including the installed-app effects. Existing reconstructed-value checks retain
complete descriptions, provenance, permission distinctions, licensing and
diagnostics. Building pages cannot start a worker or replace the review state.

Existing `details-memory`, `health-memory`, `audit-memory`, `snapshot-memory`,
`policy-memory` and `failure-memory` modes exercise the affected builders and
the shared renderer for 1,000 cycles after warmup under
`-gc none -manualfree -d track_heap`. All twenty-five allocation modes remain
part of the regression suite. Allocation measurement does not establish
whole-service or spawned-worker allocation freedom.

These are host headless rendering checks and full desktop architecture
typechecks. The individual-line layout matches the native renderer's label
contract, but no new guest graphical acceptance is claimed. Ordinary graphical
sessions and release publisher/catalog/runtime qualification remain open.


## Recorded results, 2026-10-15

All 35 focused compile/run checks passed: the complete Software functional
fixture and twenty-five allocation modes, plus ASan/UBSan functional and six
affected allocation modes (details, health, audit, snapshot, policy and failure).
The maintained Software-only distribution driver passed independently with all
twenty-five allocation modes. Each affected presentation mode retained zero
tracked bytes over 1,000 cycles after warmup and its existing retirement steps.
Sanitizer leak detection was disabled. These checks do not measure whole-service
or spawned-worker allocation freedom.

Both full desktop architecture typechecks passed. Compiler, Software/protocol/UI
inputs, staged sources, binaries and logs are pinned. An initial repair-fixture request
was corrected to the existing whole-installed-set review contract; its source
and diagnostic are retained in the execution notes. Service arguments, authorization, protocol and final
response admission are unchanged. No new guest graphical or broader release
acceptance is claimed.

- [focused checks](results/2026-10-15/software-disclosure-lines-host.json)
- [summary](results/2026-10-15/software-disclosure-lines-host.txt)
- [Software and maintained driver](results/2026-10-15/software-disclosure-lines-ui.txt)
- [allocation modes](results/2026-10-15/software-disclosure-lines-memory.txt)
- [sanitizers](results/2026-10-15/software-disclosure-lines-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-disclosure-lines-desktop.txt)
- [execution notes](results/2026-10-15/software-disclosure-lines-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-disclosure-lines-toolchain.json)
