# Software Metal AIR i64 vector bit operations checkpoint — 2026-11-17

Source revision: `ca55d645b7401a0244985d8c552e797006688b4c`.

Prepared compute pipelines execute `air.popcount.vNi64` and `air.reverse_bits.vNi64` for matching fixed 1..16-lane i64 vectors. Existing evaluators count all 64 bits or reverse their order. Keys 62004..62035 append 32 identities, bringing vector entries to 62,036. Scalar entries remain 2,179; all previous i32, AIR and LLVM identities stay stable. Other AIR integer vector families retain their i32 restriction. Exact declarations, matching source/result types, ordinary pure calls, duplicate checks, poison/undef/freeze, checked address projections and shared limits remain required.

The [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go) supplies the names, generic integer/vector suffix construction, unary signatures and pure attributes; its source is retained with a URL and checksum. Fixtures are synthetic. Apple compiler emission and upstream compiler comparisons were not run.

`tests/ios/air-native-vector-bits64.v` passes under ASan/UBSan with LLVM 23.1.5 MCJIT on arm64 Darwin. Saved disassembly confirms 32 reference bodies calling only LLVM vector ctpop/bitreverse. Every native expected lane also matches V standard-library count/reverse operations, independently of the production bit scan. No native AIR calls execute.

- 139,264 native reference lanes supply 557,056 direct/prepared typed/loaded observations across both operations and all 16 counts. Inputs include zero/all-one/sign and 32/64-bit boundaries, every single-set/single-clear bit position and deterministic full-width words. Shifted unaligned buffers, marker writes, complete padding and nonmutating validation pass. Scalar/integer APIs supply another 32,768 exact checks.
- 2,144 address checks include 96 invalid lane refusals across validation and both memory APIs. There are 320 metadata/source-type refusals, 128 short budgets, 1,024 AIR/LLVM coexistence cases and 128 short input/output buffer refusals. Thirty-two negative name/type/arity/definition profiles reject in preparation and direct execution before markers.
- 142 controls cover state/freeze/lane isolation, strict observed undef, address preflight, duplicate declarations, strictfp, loops and shared limits. Two-lane i64 PHIs XOR the top bit before each operation through 1,024 visits; scalar/integer expectations and exact 7 × visits + 3 budgets match, while one fewer step refuses. Twelve fixtures retain 4,096/4,097 result-slot and 1,000,000/1,000,016 lane-work boundaries across memory/void/scalar APIs; scalar fixtures also use the integer API. No limit increased.
- Units cover all 62,036 cache identities, distinct i32/i64 keys and refusal of other AIR i64 families. Scalar bit-operation units pass 733,180 comparisons. Each vector bit-operation unit passes 705,024 values, 327,712 sweep lanes and 104,448 poison/undef/freeze checks across i1–i64. Integer extrema, saturation, multiply-high, scalar AIR integer, vector clamp/float extrema, FMA/unary names, rounding and canonicalization regressions pass. The unchanged AIR vector zero-count checker passes 174,080 native reference lanes and 696,320 lane observations, including its flag controls.

A fresh software Metal host passes normal and deterministic sizes runs: 480 images, 702,732 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen updated `image_sizes` images compare both i64 AIR operations with LLVM and algebraic expectations composed from i32 halves. Each seed has matching 32-bit halves with their top bits set; the second lane is its complement. Expected i64 populations sum the two half counts; expected reversals reconstruct both halves in the correct positions. Full comparisons gate pixel data before the independent RGBA8/readback/padding oracle. Existing i32 operations coexist in the same shader. All prior comparison rows remain present in both hashing modes, and the six other AIR image kernels are unchanged. Clipped groups, repeated dispatches and two drained runtimes per process pass.

Native, unit and image checks passed without evaluator corrections. Generated C confirms 62,036 vector and 2,179 scalar entries, with no allocations on successful extended name/key paths; error paths retain boxed errors. Thirty-two i64 cache entries add 256 bytes. No evaluator, owner or graph node kind is added. Retained heap was not measured, leak detection was disabled and native JIT instructions are not sanitizer-instrumented.

This extends CPU software Metal. Native GPU execution/rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-vector-bits64-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-vector-bits64-20261117-r1.tar.gz`.

- Archive SHA-256: `a28ce19040a1761a7684ec216b3853abd82841292b1656ccf420856d1e89da55`.
- Typed inventory SHA-256: `5a504d00ff6e69f6e3c63ab4d16417e0abe2dbeaf75e5c19577b6d385327ede0`.
- Source archive SHA-256: `e92787c78a730ae25994546baa7c95b9c256077956672c094645b229a3e783e6`.

Complete inventory and archive comparison passes for logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit. Generated C, IR/bitcode, native disassembly, images, commands, binaries and sanitizer logs remain. Toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
