# Software Metal mixed-sign GEP paths — 2026-11-14

`28511b07a` extends bounded AIR buffer execution to mixed-sign constant
multi-index GEP paths. Negative paths require zero structure-field offsets:
the planner groups these offsets separately, so nonzero ones remain excluded
when any scaled index is negative. Scaled indexes execute in order during
preflight, checking multiplication/addition/subtraction within the existing
64 MiB limit. Underflow rejects even if a later index could compensate.

The internal GEP helper returns both its final virtual address and the highest
intermediate offset. The profile retains that maximum as a required binding
extent, including for unused results and plain GEPs. Later subtraction cannot
hide a larger prefix. Scalar loads/stores still use only the final address.
Plain, nusw and inbounds (including historical encoding) are supported;
negative nuw, zero-stride negative indexes, scalable layouts, dynamic,
poison/undef and wider indexes reject. Pointer/index widths remain 64 bits.
No owned-array layout, ownership or instruction execution cost changed.

ASan/UBSan `tests/ios/air-memory-multi-index.v` passes 85,536 native LLVM
comparisons across 4,752 functions. Fixtures cover every i1..i64/half/float
value type, four index widths, arrays, nested arrays and zero-offset structure
fields, flags, aliases and exact one-past bound views with historical inbounds.
Native inputs use canonical narrow padding and comparisons mask unused native
output padding. All 47,520 flag, 4,752 budget, 14,256 bounds/writability and
26 additional profile/layout/underflow controls reject before an earlier
store. Dedicated controls check compensated underflow and a 64 MiB positive
prefix followed by subtraction to zero. Guard functions never run natively.

Sanitized regressions pass 114,048 aggregate backward, 93,840 scalar backward
and 59,520 forward GEP comparisons with their controls. The earlier multi-index
rejection fixture now uses a nonzero structure-field offset, preserving the
remaining restriction. All 24 software Metal groups pass with normal and
deterministic Swift hashing. The deferred backward kernel uses an array path,
a zero-offset structure/array path and a byte-addressable vector path, with
mixed index widths and flags. Sparse binding offsets, derived bounds,
sentinels until commit and exact results pass in both drained runtimes.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-multi-index-validation-20261114-r1.tar.zst`

The 199 MiB bundle retains binaries, build receipts, fixtures/results, compiler
snapshots, harness-generated C, LLVM header, selected identities and source.tar
pinned to the feature revision. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`. Receipts and replay evidence
use the same prefix outside Git; original expanded evidence remains.

A fresh extraction replaced the original bundle path while retaining
`original-bundle`. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matches every file byte,
size, type, mode and link target, including the root; selected identities
match. All six restored runs pass: four sanitized reference suites and both
software Metal hashing modes. The full bundle inventory and archive checksum
match after replay. A fresh replay-archive extraction matches its own complete
inventory; both replay trees remain.

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
| Complete `.tar.zst` | `125b067d9c3d28986816ff05593a1ffb51a88e4fa06c2f3d4e7e4dac0ed49f18` |
| `.inventory.json` | `19d7840c5e39a29ad29c6b549089a9fba92bf4c88bedb9b1d5b721227c414eab` |
| `.replay.tar.zst` | `9a0017afea57d3d8ada140a1e11f78c0128036b757b09a8105898494159e4d4e` |
| `.replay-inventory.json` | `1b86eeb928bd1ff3971d36491131de77810695db97c8a1f805d3d4a75b19036b` |
| `source.tar`, revision `28511b07a` | `7da39e4b7acf2b6a3efc452835ca7952dac059acd94f1e6d70e2a7429db8db02` |
