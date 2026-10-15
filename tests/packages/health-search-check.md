# Searching installed health reports

Software's Health report searches the loaded generation by package ID, name,
installed version, kind, repository, publisher key, issue category/label and
diagnostic. Matching uses the existing Unicode scalar lowercase helper. Search
is a literal substring within a field; it does not interpret commands or fetch
metadata. **Issues only** combines with search and retains issue-first order.

Filtering keeps the selected package when it still matches and brings it onto
the visible page. Otherwise it selects the first matching row. Empty results
clear selection and paged details, show an explicit message, and retain the full
generation's inspected/issue totals beside the separate visible count. Rows
label payload, namespace and launcher issues; detail pages include architecture.

Search has its own bounded 256-byte editor, focus and select-all state. Reload
retains search/filter while retiring the old report and detail pages before the
worker starts. Failed reloads cannot present stale rows as current results.
Back retires report controls without changing the underlying catalog query,
filter or selection. Escape first leaves search focus; outside the search field
it returns to packages. Small windows retain Back after a scan finishes.

**Review all repairs** always requests a fresh review for the complete installed
set, including when filters hide every package. Search does not select a repair
target or authorize changes. Existing trust, policy, administrator approval and
transaction checks apply.

The maintained [Software fixture](software_health_fixture.v) covers matching in
every supported field, Unicode case matching/editing, the input bound, combined
filtering, stable visible selection, no results, reload success/refusal, small
window navigation, catalog isolation and full-set repair handoff. It runs with
the actual Software sources through
`tests/packages/distribution-check.v --software-only --direct-tests` (set
`VINIX_PACKAGE_TEST_UI2` to the parent of a staged headless `ui2` module).
Its `health-memory` mode measures 1,000 complete decode, page, render, search,
filter, empty-result and retirement cycles after warmup with `-gc none
-manualfree -d track_heap`.

Recorded host checks, sanitizers and full desktop architecture typechecks are
linked below. These exercise headless Software behavior; they do not establish
graphical guest acceptance or complete the publisher/catalog/runtime release
gates in roadmap section 14.


## Recorded results, 2026-10-15

All 15 focused compile/run checks passed, including the complete Software
functional fixture and all ten allocation modes. The maintained Software-only
driver passed independently. Health search/filter/render/retirement cycles
retained zero tracked bytes. Functional and health allocation checks also passed
under ASan/UBSan with leak detection disabled. Full desktop typechecks passed
for AArch64 and x86_64. Package-service behavior and protocol were unchanged; no
new guest graphical or runtime acceptance is claimed.

- [host results](results/2026-10-15/health-search-host.json)
- [summary](results/2026-10-15/health-search-host.txt)
- [Software and maintained driver](results/2026-10-15/health-search-ui.txt)
- [allocation modes](results/2026-10-15/health-search-memory.txt)
- [sanitizers](results/2026-10-15/health-search-asan.txt)
- [desktop typechecks](results/2026-10-15/health-search-desktop.txt)
- [initial attempt](results/2026-10-15/health-search-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/health-search-toolchain.json)
