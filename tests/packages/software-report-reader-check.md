# Compact Software report and receipt details

Health reports, installed-deployment checks and saved-deployment receipts
formerly required full-size windows to inspect their prepared detail pages.
Compact screens now offer **Read report** or **Read receipt** after a complete
result has loaded. A shared read-only modal pages through the loaded metadata
and returns to the same report via Back or Escape.

At 180×220 or larger, three native monospace line labels per short page preserve
the complete prepared UTF-8 text, with at most twelve bytes per line. Provenance,
diagnostics, deployment filenames/digests, drift fields, receipt counts and
metadata-only limitations remain readable. Full-size reader windows show the
canonical page. Resizing retains an exact short-page anchor; navigating to a new
full page anchors its first short fragment. Tiny windows retain Back.

**Prev item**/**Next item**, Up/Down and Tab/Shift-Tab traverse the current
filtered health/audit package projection without wrapping. Changing packages
replaces both prepared caches and keeps the selected row visible on return.
Search queries and filters remain intact. Audit checks with no matching rows
retain global source/summary pages; empty saved deployments retain receipts.
An empty health projection cannot enter the reader because no package is selected.

Returning to a smaller full report keeps the selected package visible when the
list's visible row count changes. Health now uses the same reanchoring rule as
audit reports. Redrawing at the same size preserves deliberate list paging.

While open, the reader accepts only disclosure navigation. Repair, reconciliation,
reload, search/filter editing, saving, offline export, package/failure actions,
application requests and pasted commands cannot pass through it. Captured
deployment paths and receipt/audit digests remain fixed. Pending workers cannot
open the reader. Existing save writers still require successful exit/admission
before a receipt is available and keep their close guard until they finish.

The shared [reader fixture](software_report_reader_fixture.v) reconstructs every
canonical page, traverses every short page through the app dispatcher at 180×220
and 320×240, and checks actual native line labels, geometry, keyboard bounds,
full/compact/tiny resizing and modal isolation. It walks all selected health/audit
packages and verifies filtered/empty results and retained source/digests. The
existing health, audit, audit-search and save fixtures invoke it for decoded
reports, long Unicode paths/diagnostics, both receipt architectures and empty
saved generations. Live health, audit and save barriers refuse reader entry.
An additional real-size regression selects the last package from a large list,
returns from the reader to a smaller report and checks both visible selection
and deliberate paging. It reproduced the health resize bug before the fix.

Four existing allocation modes add reader entry, package changes, resizing,
ignored mutations, Back and cache retirement to 1,000 cycles. All twenty-five
allocation modes remain regression checks. ASan/UBSan covers the functional suite
plus health, audit, audit-search and save allocation modes. Native font metrics,
the independently staged maintained distribution driver and both full desktop
architecture typechecks qualify this host change. Sanitizer leak detection is
disabled; these checks do not establish whole-service or spawned-worker allocation
freedom or new guest graphical acceptance. Broader roadmap 14 publisher/catalog/
runtime release qualification remains open.


## Recorded results, 2026-10-15

All 35 final focused compile/run checks passed: the complete Software functional
fixture, all twenty-five allocation modes, ASan/UBSan functional plus health,
audit, audit-search and save allocation modes, and native font metrics. The
maintained Software-only distribution driver passed independently with the new
shared module/fixture staged explicitly, all twenty-five allocation modes and
the font check. The four extended report modes retain zero tracked bytes over
1,000 input/navigation/render/cache-retirement cycles. Sanitizer leak detection
was disabled; these checks do not establish whole-service or spawned-worker
allocation freedom. Both full desktop architecture typechecks passed.

The initial UI compile refused an invalid while keyword in the new V fixture;
no functional/allocation test ran in that attempt. It was corrected to V for
syntax without changing assertions or production code. The initial compiler log
and fixture are retained and pinned alongside the final compiler, Software/
protocol/UI inputs, staged sources, binaries and logs. Invocations use -nocache
with fallback and automatic compiler error reporting disabled. Service arguments,
authorization, protocol, captured paths and receipt/audit digests are unchanged.
No new guest graphical or wider publisher/catalog/runtime release acceptance
is claimed.


The initial shared reader passed the complete focused suite before selection
review. A dedicated real-size regression then reproduced a hidden health row
when returning from a large list through the reader to a smaller full report.
The selected row now reanchors only when the visible row count changes,
matching audit behavior and preserving same-size deliberate paging. An older
fixture required fixed raw scroll offsets even across full-size changes; its
full-size expectation now requires the unchanged selected row/page to stay
visible. Compact scroll invariance and explicit paging checks remain. The
regression, older-expectation failure logs, original sources and successful
pre-fix binaries/logs are retained and pinned. The final focused suite,
independent driver and both desktop typechecks were rerun after this fix.

- [focused checks](results/2026-10-15/software-report-reader-host.json)
- [summary](results/2026-10-15/software-report-reader-host.txt)
- [Software and maintained driver](results/2026-10-15/software-report-reader-ui.txt)
- [allocation modes](results/2026-10-15/software-report-reader-memory.txt)
- [sanitizers](results/2026-10-15/software-report-reader-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-report-reader-desktop.txt)
- [execution notes](results/2026-10-15/software-report-reader-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-report-reader-toolchain.json)
