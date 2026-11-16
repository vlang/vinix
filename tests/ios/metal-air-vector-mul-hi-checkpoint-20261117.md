# Software Metal AIR vector multiply-high checkpoint — 2026-11-17

Source revision: `fda20005ddd179e7bcb2983a0691ad9b244f9000`.

Prepared compute pipelines now execute signed `air.mul_hi.s.vNi32` and unsigned `air.mul_hi.u.vNi32` for matching fixed 1..16-lane i32 vectors. The [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go) supplies signed integer names, vector suffixes, binary signatures and pure attributes. Its source is retained with a URL and checksum. These fixtures are synthetic; Apple compiler emission and upstream compiler comparisons were not run.

The existing multiply-high evaluator masks each input to 32 bits and returns the upper 32 bits of the signed or unsigned 64-bit product. The change adds declaration decoding and cache identities, reusing existing arithmetic, result slots, poison/undef/freeze handling and integer address projections. Keys 61780..61811 append 32 identities, bringing the vector cache to 61,812 entries. The scalar cache remains 2,179 and all previous keys stay stable. Exact ordinary direct declarations, matching source/result types, pure attributes, duplicate checks and shared resource limits remain required. Other AIR integer vector families and widths remain excluded.

`tests/ios/air-native-vector-mul-hi.v` passes under ASan/UBSan with LLVM 23.1.5 MCJIT on arm64 Darwin. Native references explicitly widen i32 to i64 with sext/zext, multiply, logically shift and truncate. Saved disassembly confirms 32 reference bodies with 32 widened vector products and no calls. This checks native widened arithmetic, rather than native execution of AIR or LLVM multiply-high declarations.

- 278,528 native reference lanes are checked through typed and loaded inputs, each with direct and prepared memory execution. Independent bit-column products also match every native expected lane. Shifted unaligned buffers, upper argument bits, earlier markers, complete output padding and nonmutating validation are checked. A further 1,024 native scalar comparisons and 65,536 scalar/integer vector extractions total 66,560 scalar/integer checks.
- 2,144 scalar/vector address checks include 96 out-of-range vector projection refusals across validation and both memory APIs. There are also 352 call metadata/operand type refusals, 128 short budgets, 2,048 AIR/LLVM vector coexistence cases and 192 short input/output buffer refusals. Thirty negative name/type/arity/definition profiles reject during preparation and direct execution before marker writes.
- 163 controls cover lane poison, strict observed undef, source/result freeze, lane isolation, address preflight, duplicate declarations, strictfp rejection, vector-PHI reuse and executed budgets. Loops run up to 1,024 visits against independent bit-column expectations. Twelve boundary fixtures exercise 4,096 versus 4,097 result slots and 1,000,000 versus 1,000,016 lane-work units across memory/void/scalar APIs; scalar fixtures also check the integer API. No limit was increased.
- Units pass all 61,812 cache identities, exact signed/vector spelling guards and namespace separation. Existing multiplication units pass 240,296 independent bit-column products, including every i1..i8 operand pair, plus 17,408 vector lanes and 8,192 poison/undef/freeze checks. Scalar AIR integer, vector clamp/extrema, FMA/unary names, rounding and canonicalization regressions pass. The unchanged vector clamp reference passes 3,342,336 frozen native lane comparisons and 196,608 scalar extractions with its controls.

A fresh software Metal host passes normal and deterministic sizes runs: 480 images, 702,732 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen updated multiply-high images compare both AIR i32 vectors with LLVM vectors and independent i64 products before the existing RGBA8 pixel/padding oracle. The output coordinate uses an AIR unsigned vector result through checked integer projection. Both signed interpretations, both lanes, clipped groups, repeated dispatches and two drained runtimes per process pass. Every prior comparison row remains present in both hashing modes. The canonicalization, extrema and clamp kernels are byte-for-byte unchanged.

Generated C confirms fixed 61,812-entry vector and unchanged 2,179-entry scalar caches, without allocations on successful new name/key paths. Unsupported-input errors retain boxed-error allocation. Thirty-two i64 entries add 256 bytes; no new evaluator, owner or graph node kind is added. Retained heap was not measured, leak detection was disabled and native JIT instructions are not sanitizer-instrumented.

This extends CPU software Metal. Native GPU execution/rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated. An initial checker build rejected a shadowed local variable; its failure receipt remains. `reference-final/` includes the expanded coexistence, type, bounds and negative-profile checks; the earlier successful `reference-verified/` remains retained.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-vector-mul-hi-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-vector-mul-hi-20261117-r1.tar.gz`.

- Archive SHA-256: `fbd82ff42eb10c42849cb0cf3fb1f2b2bf586fbfac7620367894245cf98aec0b`.
- Typed inventory SHA-256: `5de37a1a7501d043f244228649161f6785adb14b22b1331508de823e49b32913`.
- Source archive SHA-256: `5bfb667fb30a6ce53c9dd96b555e1b88f6de11af7f405459e2aeafdee8cd5b3f`.

Complete inventory and archive comparison passes for logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit. Generated C, IR/bitcode, native disassembly, images, commands, binaries and sanitizer logs remain. Toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
