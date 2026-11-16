# Software Metal AIR vector bit operations checkpoint — 2026-11-17

Source revision: `cacb4fccc5b369ff044edd3644ffb71165f5185f`.

Prepared compute pipelines execute unary `air.popcount.vNi32` and `air.reverse_bits.vNi32` for matching fixed 1..16-lane i32 vectors. The [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go) supplies names without sign suffixes, vector suffixes, unary signatures and pure attributes; its source is retained with a URL and checksum. Fixtures are synthetic. Apple compiler emission and upstream compiler comparisons were not run.

The change adds exact declaration decoding and 32 separate AIR identities at keys 61940..61971. Vector entries total 61,972; scalar entries remain 2,179, and previous AIR/LLVM keys stay stable. Existing population count and reversal evaluators, source/result type checks, ordinary pure calls, duplicate checks, poison/undef/freeze handling, checked address projections and resource limits are reused. Other AIR integer vector widths remain excluded.

`tests/ios/air-native-vector-bits.v` passes under ASan/UBSan with LLVM 23.1.5 MCJIT on arm64 Darwin. Saved native disassembly confirms 32 reference bodies calling only LLVM vector ctpop/bitreverse, with no native AIR calls. A separate V reference clears one set bit per population-count iteration and reverses through parallel bit swaps, independently of the production bit scan.

- 139,264 native reference lanes cover both operations and all 16 counts, with zero/all-one/sign boundaries, every single-set/single-clear position and deterministic patterns. These supply 557,056 verified lane observations through direct/prepared typed/loaded memory execution. Shifted unaligned buffers, upper source bits, marker writes, complete padding and nonmutating validation pass. Scalar and integer APIs supply another 32,768 checks.
- 2,144 address checks include 96 invalid lane refusals across validation and both memory APIs. There are 320 metadata/source-type refusals, 128 short budgets, 1,024 AIR/LLVM coexistence cases and 128 short input/output buffer refusals. Thirty-two negative name/type/arity/definition profiles reject in preparation and direct execution before marker writes.
- 142 controls cover state/freeze/lane isolation, strict observed undef, preflight addresses, vector PHI reuse, exact loop budgets, duplicate declarations, strictfp and shared limits. Loops XOR the source before each operation through 1,024 visits; scalar and integer APIs match independent expectations at 7 × visits + 3 steps and refuse one fewer. Twelve boundary fixtures check 4,096 versus 4,097 result slots and 1,000,000 versus 1,000,016 lane-work units across memory/void/scalar APIs; scalar fixtures also use the integer API. Runtime limits are unchanged.
- Each vector operation's units pass 705,024 independent values, 327,712 sweep lanes and 104,448 poison/undef/freeze checks across LLVM's i1–i64 support. Scalar bit operation units pass 733,180 comparisons. All 61,972 cache identities and the extrema, saturation, multiply-high, scalar AIR integer, vector clamp/float extrema, FMA/unary names, rounding and canonicalization regressions pass. The unchanged vector integer extrema checker passes 557,056 native lanes and 133,120 scalar/integer comparisons with its controls.

A fresh software Metal host passes normal and deterministic sizes runs: 480 images, 702,732 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen updated `image_sizes` images execute one-lane AIR operations in the bit-value path and compare two-lane AIR results for x and its complement against LLVM. Double AIR reversal must restore both source lanes. Those comparisons gate pixel data before the existing independent RGBA8/readback/padding oracle. Clipped groups, repeated dispatches and two drained runtimes per process pass. All prior comparison rows remain present in both hashing modes. Canonicalization, float extrema, clamp, multiply-high, integer min/max and saturating image kernels are byte-for-byte unchanged.

Initial checker controls omitted the GEP data layout and reused binary-operation work counts for a unary fixture. Both fixture errors were corrected; failed `reference/` and `reference-verified/` bundles remain. `reference-final/` passes with the committed checker. The existing ctpop/bitreverse unit rejection lists also contained the already-supported `llvm.clmul.v2i32`; these now check unsupported i65. No production evaluator correction was required.

Generated C confirms fixed 61,972-entry vector and unchanged 2,179-entry scalar caches, without allocations on successful extended name/key paths. Error paths retain boxed-error allocation. Thirty-two i64 entries add 256 bytes; no evaluator, owner or graph node kind is added. Retained heap was not measured, leak detection was disabled and native JIT instructions are not sanitizer-instrumented.

This extends CPU software Metal. Native GPU execution/rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-vector-bits-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-vector-bits-20261117-r1.tar.gz`.

- Archive SHA-256: `db050121c743c0e2f567c9fe7ab6779f250b540e6bc0c84dfbd09dd53dde74b5`.
- Typed inventory SHA-256: `c98e2cb9990e27e436f3fa19dfcf3d5857e0911ed0bcb38f44ce98b2523a7b5c`.
- Source archive SHA-256: `913759cf9aa5aa6653811e646c7bfc217304ac05db8e2a51d0f0ec73ce43bb76`.

Complete inventory and archive comparison passes for logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit. Generated C, IR/bitcode, native disassembly, images, commands, binaries and sanitizer logs remain. Toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
