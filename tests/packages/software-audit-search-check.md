# Deployment audit search and differences filtering

Software's installed deployment check now searches all report rows by package
ID, status, expected/installed version and changed field name, without case
sensitivity. **Differences only** combines with search; differences appear
before matching rows while preserving canonical report indices. A visible
result count is separate from the header's full generation/package/difference
totals. The fixture exercises the protocol's complete 8,192-row bound.

Selection retains the same canonical package while it remains visible, moves
to the first visible package when necessary, and becomes empty when no rows
match. Details always refer to that package. An empty result still exposes the
global source filename, captured digest and installed generation. Filtering and
window resizing keep selection on a visible page; ordinary redraw preserves
deliberate paging. Compact windows retain the result count and Back/Stop.

The query accepts at most 256 UTF-8 bytes without controls. Select-all,
replacement, complete-character Backspace, Enter and Escape focus handling
remain isolated from catalog search. Invalid UTF-8, controls and oversized
edits preserve the previous field. Search/filter actions are blocked while the
read-only worker runs and while no complete report has been admitted.

Reload, malformed responses and Stop retire the old observation and projection
while retaining query/filter choices. A successful reload builds a fresh list.
Back, a new deployment review and application retirement free the query,
projection, counts and detail pages. Search results never authorize or narrow
reconciliation: even zero visible rows can request a new authenticated review
of the complete captured source file.

The maintained [fixture](software_audit_search_fixture.v) checks all search
fields, interleaved row states, count accuracy, canonical row selection,
resizing/paging, retained detail pages, bounded Unicode editing, invalid input,
reload/stop/error retention, empty and wholly matching reports, catalog
isolation and complete-file review handoff. The `audit-search-memory` mode
measures 1,000 complete 64-row decode/search/filter/select/empty/resize/render/
retirement cycles after warmup with `-gc none -manualfree -d track_heap`.

This changes the host headless UI and leaves the package service and protocol
unchanged. [Service qualification](deployment-audit-check.md) covers comparison
behavior on both guest architectures; [audit presentation
qualification](software-deployment-audit-check.md) covers admission and existing
actions. These checks do not establish ordinary graphical login/display-broker
acceptance or close the wider publisher, catalog and foreign-runtime gates.


## Recorded results, 2026-10-15

All 22 final focused compile/run checks passed: the complete Software functional
fixture and seventeen allocation modes, plus ASan/UBSan functional and search
allocation checks. The maintained Software-only distribution driver passed
independently with all seventeen allocation modes. Search presentation retained
zero tracked bytes across 1,000 complete 64-row decode/search/filter/select/
empty/resize/render/retirement cycles after clearing the live status before
sampling. The functional fixture also passed an 8,192-row report. Sanitizer leak
detection was disabled; this does not measure whole-service allocation freedom.

Both full desktop architecture typechecks passed. Compiler, Software, protocol
and UI inputs, staged sources, binaries and logs are pinned. The initial
allocation failure was traced to a temporary query list in the fixture and is
recorded separately. Final runs use a fixed array. Package service and protocol
behavior are unchanged. No new guest graphical or broader release acceptance is
claimed.

- [focused checks](results/2026-10-15/software-audit-search-host.json)
- [summary](results/2026-10-15/software-audit-search-host.txt)
- [Software and maintained driver](results/2026-10-15/software-audit-search-ui.txt)
- [allocation modes](results/2026-10-15/software-audit-search-memory.txt)
- [sanitizers](results/2026-10-15/software-audit-search-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-audit-search-desktop.txt)
- [initial allocation attempt](results/2026-10-15/software-audit-search-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-audit-search-toolchain.json)
