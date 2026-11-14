# Software Metal backward aggregate strides — 2026-11-14

`c50466543` extends bounded negative constant GEPs to a single index over a
nonempty fixed array, structure or vector allocation. The existing layout
planner supplies the allocation stride; checked magnitude/division/subtraction
keeps the result at or above the binding's logical base. All earlier pointer
extents remain required. Scalars retain their previous profile. No ownership,
runtime value representation or execution cost changed.

Plain, nusw and inbounds forms (including historical encoding) are supported.
Negative multi-index paths, zero-sized/scalable aggregates, nuw, dynamic,
poison/undef and wider-than-i64 indexes still reject. Aggregate loads/stores
remain unsupported. Pointer/index widths remain 64 bits and offsets, source
allocations and strides remain bounded by 64 MiB.

ASan/UBSan `tests/ios/air-memory-backward-aggregate.v` passes 114,048 native
LLVM comparisons across 6,336 functions: arrays, packed/unpacked structures and
fixed vectors containing each i1..i64/half/float type, four index widths,
plain/nusw/inbounds flags, bounded distances, aliasing and exact one-past bound
views with historical inbounds. Scalar loads/stores use canonical input
padding; comparisons mask unused native output padding. All 63,360 flag,
6,336 budget, 19,008 bounds/writability and 24 additional profile/layout/scaled
underflow controls reject before an earlier store. Guard functions never run
natively.

The initial reference fixture omitted explicit i64 alignment. The interpreter
used LLVM's default 4-byte alignment while native ARM64 used 8 bytes, producing
different structure strides starting at i33 fields. Both failed attempts and
their fixtures remain in the bundle. The final fixture explicitly sets
`i64:64`, alongside `i24:32`, to match native field allocation. Production
layout arithmetic was unchanged.

Sanitized regressions pass 93,840 scalar backward and 59,520 forward GEP
comparisons, their controls, all four type-layout unit groups and all three
GEP-layout unit groups. The scalar checker's newly supported aggregate guards
now use empty array/structure and oversized vector layouts to retain rejection
coverage. All 24 software Metal groups pass with normal and deterministic
Swift hashing. Its deferred backward kernel uses array, structure and vector
strides with mixed index widths and flags, checking sparse binding offsets,
derived bounds, the unchanged sentinel before commit and the exact sum after
commit in both drained runtimes.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-backward-aggregate-validation-20261114-r1.tar.zst`

The 204 MiB bundle retains binaries, build receipts, failed/final fixtures and
results, compiler snapshots, harness-generated C, LLVM header, selected
identities and source.tar pinned to the feature revision. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`. Original expanded evidence
is retained; receipts and replay evidence share the same prefix outside Git.

A fresh extraction replaced the original bundle path while retaining
`original-bundle`. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matches every file byte,
size, type, mode and link target, including the root. Selected identities
match. All seven restored runs pass: three sanitized reference suites, two
sanitized layout unit suites and both software Metal hashing modes. The full
bundle inventory and archive checksum still match after replay. A fresh
extraction of the replay archive matches its own complete inventory; both
replay trees remain.

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
| Complete `.tar.zst` | `16c223c2b86fd6293d6829587fcdd542e6fe0e3f6c0bad6adac64fcbdc771f3c` |
| `.inventory.json` | `ab3182858c527d36fcfb96d176f4e2a84c39d33c0a6d908f3548a0107b128795` |
| `.replay.tar.zst` | `d17cf010a501043dec5f5114d9b3bc6d5e2c7bfc03a108cb072608cd44e64ffb` |
| `.replay-inventory.json` | `fb1fb3ff6164748b30ccae3c755183ce9a89a349ba90a6a405fd975732b48271` |
| `source.tar`, revision `c50466543` | `be3aa29c7c07b715e02c63a22ee67e5a3a20074dc41eceea8ad745550bc0cf09` |
