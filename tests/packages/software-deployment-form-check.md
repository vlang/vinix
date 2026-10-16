# Compact Deployment forms

Software previously required a large window to choose or enter a deployment
file, review release apps or open an installed check. Idle Deployment forms now
keep these actions available at 320×240. The absolute-path field stays visible;
one action and its complete explanation appear at a time, with **Previous**,
**Next**, **Status** and **Back** controls.

Actions include file selection, full-set deployment review, installed-metadata
audit, saving an installed snapshot and reading organization policy. Release
review and release audit appear when the image declaration is available.
Failure details appears when a diagnostic is retained. Navigation skips
unavailable actions, stays at either end and resets an unavailable selection
to file selection. File-dialog requests show **Choosing file…** in place of a
duplicate chooser button.

Left/Right and Page Up/Page Down page through actions after leaving the path
field. Keyboard editing and pasted text keep their existing literal UTF-8 and
4,096-byte bounds; pasted controls cannot navigate or activate anything.
Paging, status/failure views and resizing preserve the filename and selected
action. An intervening navigation event discards a late chooser result.

Each visible action invokes its existing workflow. Review and audit stay
read-only, snapshot selection opens its separate new-filename form, and policy
opens its existing read. Completed reviews still require the full plan and
separate confirmation; approved changes retain their close/cancellation guard.
Below 320×240 the existing compact lifecycle view keeps Back/Cancel/Stop and
available diagnostic controls, with the form available after enlarging.

The [form fixture](software_deployment_form_fixture.v) checks every available
action at 320×240, 639×609, 640×240 and 320×610. It recursively checks element
geometry and reconstructs the native-renderer help lines to require complete
text without truncation. It exercises literal Unicode/metacharacter filenames,
focus-aware keyboard paging, full/compact anchors, missing optional actions,
late picker results, status/failure reports and all workflow transitions.
The earlier [navigation fixture](software_deployment_navigation_fixture.v)
retains its partial/live/complete worker barriers and approved-transaction
protection; failed applies now open diagnostics through the visible pager.

The allocation mode measures 1,000 cycles through all seven normal actions,
full/compact/tiny rendering, keyboard paging, literal edits and rejected/empty
pastes. The maintained [distribution driver](distribution-check.v) runs this
alongside its existing allocation modes and full Software checks.

The [native guest fixture](software_image_fixture.v) uses the actual 320×240
form, keyboard paging and visible release controls with real services. An
ordinary administrator audits the empty release set, reviews its complete
signed deployment, approves it separately and audits the exact install. A
standard account audits the same set without approval. Native launches,
isolated data, updates, rollback, launcher removal and cached reinstall remain
required on both architectures.

Reproduce with the existing [Software image instructions](software-image-check.md)
and `native-catalog-check.v --software`, using new state directories. Run
`distribution-check.v --direct-tests --software-only --desktop` for the host
suite and target typechecks. The pinned V compiler, generated desktop assets,
headless ui2 overlay, target toolchains and matching kernel/sandbox are recorded
with the results. No kernel code changes in this increment.

The guest checks construct headless UI trees. Full graphical login,
compositor/display-broker acceptance, production catalog migration and broader
foreign-runtime/device qualification remain roadmap 14 work.

## Recorded results, 2026-10-17

All sixteen focused compile/run checks passed, including normal and sanitized
Software, the real session-broker chooser check, and form, chooser, release
discovery and deployment navigation allocation checks. UI ASan/UBSan passed
with leak detection disabled. The maintained Software-only driver passed the
full functional suite, all 28 allocation modes, both full Linux desktop target
typechecks and launcher checks. The new warmed form mode retained zero tracked
bytes over 1,000 seven-action cycles; this does not claim whole-service or
broker allocation freedom.

Fresh Software guests passed on AArch64 (30.2 s) and x86-64 (35.3 s). Both used
the production stager, real administration and sandbox/native services, and
the compact form's visible review/audit actions. Each required the complete
workflow and guest-initiated QMP shutdown. The V verifier checks every receipt
artifact hash, the unchanged qualified kernels and copied Software sources.
No new installed-disk or graphical-presentation qualification is claimed.

The initial host functional run passed the new assertions, then caught an old
fixture's expectation that Failure details was always on the first compact
screen. That test now uses the visible pager to open the retained diagnostic.
Its live-worker, error, Back and protected-transaction checks remain required.
The initial output and final compiler/source/artifact hashes are retained.
Final product and fixture sources remained unchanged through successful runs.

- [Summary](results/2026-10-17/deployment-form-summary.txt), [sixteen host checks](results/2026-10-17/deployment-form-host.json)
- [Software checks](results/2026-10-17/deployment-form-ui.txt), [allocation checks](results/2026-10-17/deployment-form-memory.txt), [sanitizers](results/2026-10-17/deployment-form-asan.txt), [maintained driver](results/2026-10-17/deployment-form-driver.txt)
- [AArch64 receipt](results/2026-10-17/deployment-form-aarch64.json), [serial](results/2026-10-17/deployment-form-aarch64.serial.txt), [QMP](results/2026-10-17/deployment-form-aarch64.qmp.txt)
- [x86-64 receipt](results/2026-10-17/deployment-form-x86_64.json), [serial](results/2026-10-17/deployment-form-x86_64.serial.txt), [QMP](results/2026-10-17/deployment-form-x86_64.qmp.txt)
- [Initial attempt](results/2026-10-17/deployment-form-attempts.txt), [compiler/source/artifact ledger](results/2026-10-17/deployment-form-toolchain.json)
- [V guest invocation](results/2026-10-17/deployment-form-guest.v), [focused host runner](results/2026-10-17/deployment-form-checks.v), [evidence verifier](results/2026-10-17/deployment-form-retain.v)
