# Software Metal invariant pointer PHIs — 2026-11-14

`6b55f2464` supports pointer PHIs in bounded AIR buffer execution and opt-in
software Metal compute when all incoming operands have the same pointer type
and resolve to the same argument identity and byte offset. Direct arguments,
earlier GEPs with different SSA names and earlier invariant pointer PHIs may
converge. Every incoming value is checked, including inactive paths. Different
arguments reject even when their borrowed buffers alias; different offsets,
null, poison and undef pointer constants remain unsupported.

Preflight records the resolved pointer in its existing temporary pointer table.
Runtime checks the executed predecessor and charges one step per pointer PHI,
then skips scalar reads/publication for that slot. Scalar and overflow-pair
PHIs still collect their values before publishing, including when interleaved
with pointer PHIs. No runtime pointer value format or owned-array layout was
added. Existing extents, permissions, forward control flow and budgets apply;
varying pointer PHIs, pointer selects and loops remain unsupported.

ASan/UBSan `tests/ios/air-memory-pointer-phi.v` passes 54,712 native LLVM
comparisons across 792 main functions and an additional nested fixture. It
covers i1..i64/half/float values, branch/switch joins, direct and GEP-equivalent
incoming pointers, three mixed pointer/scalar PHI orders, aliases and nested
pointer-PHI/GEP dependencies. Exact binding extents and executed costs pass:
branch bodies use a 25-step bound and execute 22 steps; switch bodies use a
29-step bound and execute 22 or 23; the nested fixture has a 15-step bound and
executes 12. Native inputs use canonical narrow padding; comparisons mask
unused native output padding. Independent scalar tags check predecessor choice.

All 9,504 instruction/type/operand/predecessor controls, 792 short budgets and
3,168 binding/permission controls reject before an earlier store; restored
baselines pass. Five guard bodies reject unequal or invalid incoming pointers
even on an unchosen branch, including distinct argument identities sharing one
backing array. Two poison/undef condition controls still reject dynamically
and retain exactly the earlier write. Guard bodies never run natively.

Sanitized regressions pass all 144,320 branch/PHI and 286,400 switch comparisons
and their metadata/type/budget/poison controls. The earlier pointer-PHI rejection
fixture now uses different incoming offsets. All 24 software Metal groups pass
with normal and deterministic Swift hashing. The deferred branch kernel mixes
an invariant address-space-1 pointer PHI with overflow-pair and scalar PHIs,
then uses it for stores and derived GEPs. All seven dispatch scenarios, exact
results, sentinels until commit and both drained runtimes pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-pointer-phi-validation-20261114-r1.tar.zst`

The 192 MiB bundle retains binaries, build receipts, fixtures/results, compiler
snapshots, harness-generated C, LLVM header, selected identities and source.tar
pinned to the feature revision. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`. Receipts and replay evidence
use the same prefix outside Git; original expanded evidence remains.

A fresh extraction replaced the original bundle path while retaining
`original-bundle`. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matches every file byte,
size, type, mode and link target, including the root; selected identities
match. All five restored runs pass: three sanitized reference suites and both
software Metal hashing modes. The complete bundle inventory and archive
checksum match after replay. A fresh replay-archive extraction matches its
own complete inventory; both replay trees remain.

The standalone compiler snapshot was saved after builds; the harness captured
its compiler before generation. External SDKs, assembler, library symlinks and
dylibs remain unsealed prerequisites. Native MCJIT code is not sanitizer
instrumented. Leak detection is disabled; retained heap was not measured.
The ordinary runner was not rebuilt. This remains single-thread CPU execution
of synthetic valid LLVM fixtures. No Apple-produced shader, GPU rendering,
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `430bbfaf62556cb2b35a5d6b59bbfb2f87d8c00fc62877c4e3e82e2a09ee73c3` |
| `.inventory.json` | `172148dcac42d2800838c395a934e4e644224502c0945ee47510014746f0168f` |
| `.replay.tar.zst` | `b231a7e9836745378632af5ea9e8637d25449f86121d9606fd6b2449e113e949` |
| `.replay-inventory.json` | `631fb8a6d23a563c0ee368ac7c7679ee0c5023466f453b50b877af7dd8a57969` |
| `source.tar`, revision `6b55f2464` | `5557b7a889d32e469672717f8cef36ea131a07c9cd457b4979f00fb2a4407957` |
