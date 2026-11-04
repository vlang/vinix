# A4 retained fixture alias diagnosis

Editing the matched-kernel helper in the isolated preparation worktree also
changed four historical preparation fixtures through retained hardlinks. The
independent as-run source snapshots remained intact; those copies did not
isolate the historical fixture aliases. Earlier unchanged-history assumptions
in receipt `87c2d627fbf20fe1e08bd0a7a58342f670d30001a6618e23b9ad8d7af563b8b6`
and its bootstrap/plan are superseded by the external correction below.

The affected paths are under the preserved historical root
`/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/a4-matched-host-01`:
`qualification-{03,04,06,07}/prepare-controls/preparation/inputs/source/tests/packages/audiokernel/kernel.v`.
All four originally had SHA-256
`f5750020a869c5cf0e4f76e748dd5c416e97ef4fdc006d3ec4048e2a94679dd2`;
their current bytes have SHA-256
`6631cf071ead5f4aee4f263b6cbc88a0795802a5c73732a4563a3fb47db6621a`.
Together with the current source and fresh fixture, they account for all six
current links to inode `381131980`. The other two edited binding files each
have one current link. The saved device `16777233` differs from current device
`16777230`; this is recorded without normalization or historical admission.

The maintained read-only V diagnostic was checked from source baseline
`8845bddd3d72a8980ac646efcad18dfd3f22f81d` plus this accompanying source,
individually pinned at
`187c52eb653903ff0affb61e9f38d8493c4a50f4170bfda2fd7d088145891c0a`.
Pinned V `ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`
and LLVM 23 compiled it with `-prod -nocache -keepc -backend c` and
`-Werror=incompatible-pointer-types`. Compilation and diagnosis returned actual
exit 0 under separate 120-second bounds. The diagnostic consumed all 47,247
recorded inventory entries, compared the three edited bindings and independent
snapshots, accounted for their complete current link sets, and confirmed the
four constrained byte changes. Its successful exit establishes diagnosis
coverage; it supplies no historical qualification.

Complete raw output, literal commands/environment, source archive, generated C,
pin checks and endpoint resource observations remain outside Git at
`/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/a4-binding-alias-diagnostic-20261104-01`.
`diagnosis-01/diagnosis.json` has SHA-256
`aab1739a779b9e38b6b0e484d1c60c5046be81b6ea9a34fcab9dfec80d0f56be`;
`historical-fixture-correction-01.json` has SHA-256
`202eac591e096ac3218c68934c9a1e493747a6c6569782d7d07b37b0fa289420`.
All 18 input pins and four compiled-artifact pins verified unchanged. Resource
observations cover command admission/completion only.

No historical file, alias or metadata was restored or repaired. Original
inventories, independent snapshots and recorded refusals remain preserved. The
old history remains refused; the fresh 149-control host run retains its limited
as-run result, and its whole-host audit remains suspended. Keep the original
source worktree, fresh host history and legacy aliases fixed. Independent-copy
fixture changes and their 151 controls require separate validation. No target,
guest, audio backend or hermetic toolchain qualification is claimed here.
