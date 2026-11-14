# Software Metal ordered structure GEPs — 2026-11-14

`dcf33a214` adds mixed-sign constant GEP paths with nonzero structure-field
offsets to bounded AIR buffer execution and opt-in software Metal compute.
The memory helper replays the numeric planner's validated type path, applying
each field offset and scaled index in traversal order. Field kind/range and
layout bounds are checked by the planner first; scalar term operand identities
are checked during replay. The numeric planner and its public layout are
unchanged. Owned-array layouts, ownership and instruction costs are unchanged.

Every prefix must remain within the binding's logical base and extent, under
the existing 64 MiB limit. A later field cannot rescue earlier underflow;
subtraction cannot hide a larger field prefix. The profile retains the highest
intermediate offset, while scalar loads/stores use only the final address.
Plain, nusw and inbounds, including historical encoding, are supported.
Negative nuw, zero-stride negative indexes, scalable layouts, dynamic,
poison/undef and wider-than-i64 indexes remain excluded. Pointer/index widths
remain 64 bits; aggregate loads/stores remain unsupported.

ASan/UBSan `tests/ios/air-memory-structured-gep.v` passes 85,536 native LLVM
comparisons across 4,752 functions: packed, unpacked and nested nonzero fields,
all i1..i64/half/float value types, four index widths, plain/nusw/inbounds flags,
aliases and historical inbounds with exact one-past bound views. The final
checker independently asserts each exact required extent from the fixture's
explicit ABI instead of inferring its scalar stride from the profile. Native
inputs use canonical narrow padding; comparisons mask unused native padding.
All 47,520 flag, 4,752 budget, 14,256 bounds/writability and 27 additional
profile/layout/underflow controls reject before an earlier store. Dedicated
guards cover underflow before a compensating field and an oversized field
prefix followed by subtraction to zero. Guard functions never run natively.

Sanitized regressions pass 85,536 array/multi-index, 114,048 aggregate backward,
93,840 scalar backward and 59,520 forward GEP comparisons with their controls,
plus all three GEP layout unit groups. Earlier nonzero-field rejection fixtures
now test genuine early underflow that later fields would compensate, retaining
the required rejection behavior. All 24 software Metal groups pass with normal
and deterministic Swift hashing. Deferred compute uses nonzero structure
fields before negative indexes at mixed widths, checking sparse bindings,
derived extents, unchanged sentinels until commit and exact sums afterward
in both drained runtimes.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-structured-gep-validation-20261114-r1.tar.zst`

The 206 MiB bundle retains binaries, build receipts, fixtures/results, compiler
snapshots, harness-generated C, LLVM header, selected identities and source.tar
pinned to the feature revision. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`. Receipts and replay evidence
use the same prefix outside Git; original expanded evidence remains.

A fresh extraction replaced the original bundle path while retaining
`original-bundle`. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matches every file byte,
size, type, mode and link target, including the root; selected identities
match. All eight restored runs pass: five sanitized reference suites, GEP
layout units and both software Metal hashing modes. The complete bundle
inventory and archive checksum match after replay. A fresh replay-archive
extraction matches its own complete inventory; both replay trees remain.

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
| Complete `.tar.zst` | `18607d655986b6de796d80954bbe92655a4d528acff6f8058183bebf1b1c4038` |
| `.inventory.json` | `0ab4c7c3162eccd75109349237b63ff9871f8c82a5106e85f95408bad41724a3` |
| `.replay.tar.zst` | `6e72757bc573d018374c34c2d12157b24c717e01fe41ba77d7540bade8a842b3` |
| `.replay-inventory.json` | `092986a66c9e651088fbecfa90df757e52f53bf7d0ef4093e2df37de29a92206` |
| `source.tar`, revision `dcf33a214` | `877dfe894361abecca4abebb1ddd4cb759a02102000b2446d2c01dd060c9d800` |
