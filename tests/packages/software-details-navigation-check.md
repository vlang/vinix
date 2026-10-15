# Compact Software package details

Package details previously showed only Back in a compact window. At least
180 by 220 pixels now provides a title, three individual monospace lines,
Previous/Next page controls and Previous/Next section controls. Short pages
use twelve-byte UTF-8 fragments and preserve all prepared facts and their
bullet/continuation prefixes. Smaller windows retain Back and an enlargement
hint. Full-size details retain the existing six tabs and full prepared pages.

The model prepares an owned short-page cache when opening package details,
using the same UTF-8 pagination and page anchors as service failure details.
Redraw borrows text from the cache and allocates no line strings. Section
changes select the corresponding canonical page; resizing preserves the short
page while its canonical page is unchanged. Moving to another full page selects
its first short page on the next compact redraw. Clear, Back, Escape, reload
and review retirement free both caches and their page labels.

Left/Right and PageUp/PageDown turn pages within the selected section. Up/Down
and Shift-Tab/Tab select previous/next sections. Page and section boundaries do
not wrap. Paste remains ignored, including pasted escape sequences. Compact
details use the same modal event guard as full details; review confirmation and
catalog actions remain inaccessible until returning to the original view.

The maintained [fixture](software_details_fixture.v) reconstructs every full
page from its short fragments, then traverses and renders every short page at
180 by 220 and 320 by 240. It checks actual drawn lines, UTF-8 byte budgets,
counter/title/control presence and frame bounds. It repeats this for catalog
facts and install, remove, upgrade, repair, deployment, rollback and mirror
reviews. Deployment and mirror modes remain set, so checks exercise modal
dispatch before their ordinary compact builders. Full/compact/tiny resizing,
page and section keyboard actions, end boundaries, ignored paste/actions,
unchanged selection/fingerprint/row count and worker absence are checked.

The existing details allocation mode now exercises compact sections, key input,
resizing and both cache lifetimes on each of 1,000 catalog/review cycles. All
twenty-five allocation modes remain regression checks. ASan/UBSan also covers
details and package/deployment/mirror navigation allocation modes. These are
headless host checks and full desktop architecture typechecks; no new guest
graphical acceptance, whole-service or spawned-worker allocation freedom is
claimed. Ordinary graphical sessions and publisher/catalog/runtime release
qualification remain open.


## Recorded results, 2026-10-15

All 35 focused compile/run checks passed: complete Software functional checks,
all twenty-five allocation modes, ASan/UBSan functional plus four affected
allocation modes, and the existing native font metrics compile/run check. The
maintained Software-only distribution driver passed independently with the font
check and all twenty-five allocation modes. The extended details mode retains
zero tracked bytes over 1,000 catalog/review prepare, section, full/compact, key,
resize, Back and retirement cycles. Sanitizer leak detection was disabled.
These measurements do not establish whole-service or spawned-worker allocation
freedom. Both full desktop architecture typechecks passed.

An initial allocation batch was interrupted by host errno 28 while opening a
log, after functional and the first ten allocation modes had passed. Retired,
unpinned generated C files belonging to this package thread were identified by
source paths and removed. Its recovery log and initial functional result are
pinned. The complete rerun passed without source or assertion changes. Compiler,
Software/protocol/UI inputs, staged sources, binaries and logs are pinned. No
service, argument, authorization or protocol changes, new guest graphical
acceptance or complete publisher/catalog/runtime release qualification are
claimed.

- [focused checks](results/2026-10-15/software-details-navigation-host.json)
- [summary](results/2026-10-15/software-details-navigation-host.txt)
- [Software and maintained driver](results/2026-10-15/software-details-navigation-ui.txt)
- [allocation modes](results/2026-10-15/software-details-navigation-memory.txt)
- [sanitizers](results/2026-10-15/software-details-navigation-asan.txt)
- [desktop architecture checks](results/2026-10-15/software-details-navigation-desktop.txt)
- [execution notes](results/2026-10-15/software-details-navigation-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/software-details-navigation-toolchain.json)
