# Dispatch layout requests through parent overrides

Source baseline: `9a49b841d82479e282c99b5502a06687face1c3b`.
The old runtime is the sealed [Framework332](layout-request332.md) build.

`View.requestLayout()` previously marked ancestor fields directly, bypassing
overrides that intercept or defer descendant requests. It now marks itself and
invokes its parent's `requestLayout()` through `ViewParent`, including repeated
requests from an already-pending child. Native scheduling and the 332 callback
retention remain intact. The provider interface gains the missing abstract
entry, and its non-View `WindowManagerImpl$WindowViewParent` gains a no-op since
Views already schedule native traversal.

The [runner](layout-parent-dispatch-run.v) assembles and disassembles the complete
2,068-class framework. Exactly three classes change: View's one method and the
two parent ABI additions. All other View methods remain identical. The only
direct ViewParent implementors are ViewGroup and this window parent. Four
malformed/duplicate parent inputs are rejected without either parent file
changing.

The same signed six-class APK runs against both frameworks. The unchanged 332
callback/cache probe passes first. The old run then fails at exactly
`AssertionError: descendant request bypassed parent override`. The new run
passes interception, repeated pending requests, two-parent forwarding and next
measurement, prints `PARENT-DISPATCH-PASS`, and retains a live window through
45 seconds without runtime error markers. The [fixture](startupfixture/layout_parent_dispatch.v)
also calls the actual private non-View window-parent class, constructed by
reflection and assigned to a detached View. This proves its ABI, not attachment.

The earlier v2 fixture reached those dispatch assertions but then failed at the
unrelated unsupported `WindowManagerImpl.native_addView(JIIIII)` setup entry.
Its complete 7,416-file bundle remains at
`/Users/alex/.local/state/vinix/android/layout-parent-dispatch336-v2-2026-10-25`,
manifest SHA256
`7a7d209ed0e4037d2a43481b3a138d17c3958a6cafe267da0d55125dfb90dc53`;
independent complete-file/hash readback passed. The final fixture uses the
constructed parent above.

The final runner initially counted the overall PASS marker as a substring of
the detailed marker. A separately frozen qualifier checks exact serial lines
against the unchanged completed raw runs; the original runner and failure are
retained.

The complete 8,718-file bundle is retained at
`/Users/alex/.local/state/vinix/android/layout-parent-dispatch336-v3-2026-10-25`,
manifest SHA256
`a583f89a37bc7d59a275fef01396a864efe04915dd070227631599058ae46762`.
It includes the full before/after DEX, frozen source/compiler closures, generated
C, runtime inputs, signed APK and raw ART evidence. Both semantic qualification
receipts report `expected-result-pass`. The final runner is retained separately
at `qualification/source/layout-parent-dispatch-run.v`, SHA256
`90aa7dd74ec5492b2e4a0b4d13d1c0543dd147b7861e92bbf625ed897bebdc59`.
Root and peer independently verified all 8,718 files with the existing complete
bundle checker. Their sibling receipts are
`layout-parent-dispatch336-v3-root-readback-2026-10-25.json` and
`layout-parent-dispatch336-v3-peer-readback-2026-10-25.json`.

These checks qualify the framework contract. They do not establish that this
defect causes Maps' Attractions loading sheet or qualify navigation.
