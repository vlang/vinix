# Compact Software catalog browser

Idle compact catalog screens offer **Browse catalog**, including for an empty
catalog. From 180×220, the browser provides the existing Unicode search field,
a cycling Catalog/Installed/Updates filter, Previous/Next package controls,
position/count and a wrapped name preview. **Details** opens the complete paged
package presentation; Back returns to the same browser. Smaller windows retain
Back. Search rejection and unavailable update/details messages appear in the
preview; Back returns to catalog status and failure controls.

Tab focuses search. Enter leaves search; when unfocused, Enter opens Details
and arrow/Page keys select packages. Escape leaves Details, then the browser.
Search/filter changes retain a matching selection or select the first match;
empty matches clear selection. Back retains the query, filter and selection.
Selection is visible on return to the full list, including after a resize,
without overriding deliberate paging on subsequent same-size builds.

At 320×240, **Review install**, **Review uninstall**, and **Review updates**
start read-only proposals when the selected row permits them. Uninstall applies
to a requested installation. Updates resolves the complete installed set.
Starting a proposal leaves the browser and shows the existing plan. Use the
full review to confirm and request administrator approval. Pending workers,
frozen proposals and other forms refuse browser entry.

The V Software fixture checks both architectures, all six package kinds,
all 4,096 catalog entries, installed/update subsets, Unicode and rejected
searches, empty catalogs/matches, complete Details, control geometry at
180×220/320×240/full sizes, tiny Back, resize selection and ignored writes.
The existing view allocation mode includes 1,000 browser search/filter/select/
Details/render/resize/Back and retirement cycles. This is host UI qualification;
guest graphical acceptance and roadmap 14 release completion remain open.


## Recorded results, 2026-10-16

All fourteen final focused compile/run checks passed: full Software functional
assertions, six affected allocation modes, ASan/UBSan functional and view/Details
allocation modes, and native font metrics. Both full desktop architecture
typechecks passed. The view mode retains zero tracked bytes across 1,000 browser
search/filter/select/Details/render/resize/ignored-write/Back and retirement
cycles; shared Details remains flat. Sanitizer leak detection was disabled.

Both architectures, all six kinds, 4,096 catalog entries, installed/update
subsets, Unicode/rejected/empty search, update/details diagnostics, native
controls, resize selection, modal isolation and pending-worker admission passed.
The initial functional run rejected incomplete installed launch fields in new
maximum-catalog fixture data; the fixture was corrected without relaxing the
protocol. The next functional run passed, but allocation checks found a 39-byte
array allocation per cycle in a new assertion. A one-cycle diagnostic and
generated C identified it; equivalent length/element checks remove it. Pre-fix
logs, fixtures, binaries and C are retained and pinned. A private diagnostic
compile first placed declarations before imports; that log is retained and its
helper was corrected. No assertion was removed.

The unchanged maintained staging list needs no new filenames and was not rerun.
Frozen compiler, Software/protocol/UI inputs, staged copies, binaries, generated
C, helper sources and logs are pinned. Cache, fallback and automatic compiler
error reporting were disabled. Service authorization, protocol, frozen apply
arguments, successful-exit admission and approved-write guards are unchanged.
No whole-service/spawned-worker allocation freedom, guest graphical or broader
roadmap release acceptance is claimed.

The pre-fix ASan/UBSan functional run also passed, then its view allocation
run reproduced the same 39,000-byte fixture allocation. Those logs and the
pre-fix binary/C/fixture are retained and pinned.

- [focused checks](results/2026-10-16/software-catalog-browser-host.json)
- [summary](results/2026-10-16/software-catalog-browser-host.txt)
- [functional assertions](results/2026-10-16/software-catalog-browser-ui.txt)
- [allocation checks](results/2026-10-16/software-catalog-browser-memory.txt)
- [sanitizers](results/2026-10-16/software-catalog-browser-asan.txt)
- [desktop architecture checks](results/2026-10-16/software-catalog-browser-desktop.txt)
- [execution notes](results/2026-10-16/software-catalog-browser-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-16/software-catalog-browser-toolchain.json)

## Maintenance reviews from the compact browser

At `74dab654224e98d729ecf150d0f7a283e82fefae`, the 320×240 browser can
review install or uninstall for the selected package, or resolve updates for
the entire installed set. The host fixture checks both size cutoffs, control
geometry, stale actions, dependency uninstall refusal and exact worker
arguments. It then checks compact plan reading, full confirmation visibility
and preserved catalog selection after cancellation. The same test at
`0df507615` failed at the missing review control.

On 2026-11-24, the complete Software fixture passed in normal and ASan/UBSan
builds with sanitizer process leak detection disabled. The compact mirror
driver passed all five focused host modes, both Linux production C-generation
checks and its supplementary complete Software fixture. The 1,000-cycle
package navigation and plan reader checks retained zero tracked bytes. The
broader `view-memory` mode hit the allocation tracker limit while decoding
installed dependencies on both revisions.

AArch64 and x86_64 headless QEMU tests drove the actual compact controls and
completed the reviewed upgrade, rollback, Memo uninstall and cached
reinstall with separate administrator approval. Memo kept its private data.
Both guests initiated shutdown and all 60 receipt entries matched per target.

The [retained archive](/Users/alex/.local/state/vinix/r14-compact-package-reviews-rZG2L4/qualification.tar.gz)
contains the baseline, committed changes, generated code, host checks and
guest receipts. The independent checker verified all 1,818 sealed files and
symlinks. Archive SHA-256 is
`3020930524f6b51991a0eb4b11df449090ac6f81bdbf2a3311460f78549931b3`.
