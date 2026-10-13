# Personal application data in Software

Software’s **Personal data** page lists the calling ordinary account’s retained
application data, including valid IDs absent from repositories. Installed apps
require uninstall; unsafe app directories carry diagnostics and cannot be
selected for deletion. Root receives a sign-in explanation without an account
selector or cleanup controls. The underlying `--json data-list` / SDK 1
`Service.personal_data()` inventory uses installed state and captured home/data
directory descriptors, without refreshing repositories or following links.

**Review deletion** freezes the selected ID. Its confirmation explains the
account-local scope and permanent loss; catalog actions, row selection, reload
and external launches cannot change the pending ID. **Delete permanently** calls
`purge-data` directly as the owner, without package administrator transport or a
password. A live-generation failure retains that confirmation and its diagnostic
for retry/cancel. Success reloads the list; malformed/failed inventory replies
disable deletion until a successful reload. Normal window close is refused
during purge. Forced process retirement can leave partial cleanup; reload and
retry after resolving the reported problem.

The service’s inventory streams at most 4096 directory entries, returns sorted
valid IDs and distinguishes installed/uninstalled state independently of catalog
availability. Unsafe parents fail the whole request; absent parents return an
empty inventory. App aliases, special files, shared/foreign ownership and
filesystem crossings produce diagnostic rows. Arbitrary names outside the
package ID grammar are ignored but count towards the directory-entry bound.
The existing purge rechecks installed state, all relevant retained generation
leases, ownership and identities while holding the package reader lock.

The complete format-1 JSON decoder rejects missing/unknown/duplicate fields,
duplicate IDs, wrong types, invalid UTF-8/Unicode escapes, trailing input and
excessive bounds. It releases partial rows/strings on failure and array buffers
on growth. Initial memory checks exposed the pinned generic decoder’s old array
buffers and per-string allocations; the final bounded schema/string reader
replaces those repeated allocations with explicitly owned buffers.

Qualification covers:

- [Backend assertions](../../tools/packages/pkgcore/personal_data_test.v): sorted
  installed/retained/uncatalogued entries, safe aliases/FIFOs, missing parents,
  unsafe home/parents, ownership, shared modes and the entry-count bound. Existing
  [purge assertions](../../tools/packages/pkgcore/purge_test.v) still pass after
  sharing the anchored home-parent traversal.
- [Protocol assertions](../../tools/packages/pkgprotocol/personal_data_test.v):
  strict schema, duplicates/types/bounds, escaping, Unicode, field order, array
  growth and owned field retirement. Backend/protocol/purge assertions pass
  clang ASan/UBSan with leak detection disabled.
- [Actual Software fixtures](software_data_fixture.v), compiled beside the
  production page and worker implementation: literal inventory/purge arguments,
  root refusal, installed/unsafe refusal, frozen confirmation, cancellation,
  hidden-action refusal, paging, live-lease failure, successful reload, invalid
  metadata and close guard. The existing Software suite also passes. Under
  `-gc none -manualfree -d track_heap`, 1000 wide/invalid/valid decode, select,
  redraw, confirmation, cancellation and retirement cycles retain **zero tracked
  bytes**. Both Linux target frontends accept the current Software sources.
- [Guest inventory/purge checks](../accounts/guest/package_purge.v): actual
  administrator/standard account inventories expose only their own data,
  distinguish installed versus retained data, include uncatalogued IDs, diagnose
  aliases, refuse unsafe parents/root, and reflect successful deletion. All
  existing launch, document, lease, PTY, window and trust/tamper assertions remain
  required by [the guest controller](isolated-launch-check.v).

Run the host fixtures with the pinned V compiler and staged headless UI module
through [distribution-check.v](distribution-check.v) (`--direct-tests`, or
`--software-only --direct-tests` for the UI suite). Guest commands use fresh state
directories and retained production kernels/sandboxes as documented in
[isolated-launch-check.md](isolated-launch-check.md). The additional marker is:

`PACKAGE DATA ordinary-admin-standard own-inventory installed-removed uncatalogued safe-links root-refusal post-purge-reload PASS`

These checks qualify the service and headless page behavior. They do not qualify
ordinary graphical login/display integration, real publisher enrollment or the
full compatibility-runtime catalog; those remain roadmap release gates.

Both QEMU TCG guests passed: AArch64 **237.963 seconds**, x86_64 **594.716 seconds**, each with clean guest shutdown and nine verified input/serial hashes. The first x86_64 run timed out at 300 seconds before the inventory assertions; the fresh retry used a 600-second deadline. Times are functional deadlines, not performance qualification.

The AArch64 fixture’s scalar-reader variant predates the final parser memory refinement; that reader is absent from production package-service C. The final bounded reader is qualified by the host assertions, heap check, sanitizers and both Linux Software frontends; the x86_64 retry uses it in the guest too. Generated C witnesses preserve the exact compiled variants.

- [AArch64 receipt](results/2026-10-13/personal-data-aarch64.json), [serial](results/2026-10-13/personal-data-aarch64.serial.txt), [QMP](results/2026-10-13/personal-data-aarch64.qmp.txt).
- [x86_64 receipt](results/2026-10-13/personal-data-x86_64.json), [serial](results/2026-10-13/personal-data-x86_64.serial.txt), [QMP](results/2026-10-13/personal-data-x86_64.qmp.txt).
- [First x86_64 timeout](results/2026-10-13/personal-data-x86_64-timeout.txt), [host checks](results/2026-10-13/personal-data-host.txt), [source/toolchain/artifact ledger](results/2026-10-13/personal-data-toolchain.json).
