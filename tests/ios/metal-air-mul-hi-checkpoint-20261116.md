# Software Metal AIR multiply-high checkpoint — 2026-11-16

Source revision: `6e15327035a908bcbb3b3003575dd94bded91e78`.

Prepared compute kernels execute scalar `air.mul_hi.s.i32` and `air.mul_hi.u.i32`, returning the upper 32 bits of the signed/unsigned 64-bit product. The exact names and binary signatures follow the [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go) and its [compiler comparison cases](https://github.com/vertex-language/air/blob/main/intrinsic_test.go). Our fixtures are synthetic AIR; those upstream Apple compiler comparisons were not run here.

The calls reuse existing multiply-high IDs, normalization and evaluators. Keys 2166..2167 append two identities, bringing the scalar declaration cache to 2,168 entries without moving earlier keys. LLVM/AIR forms coexist. Exact i32 signatures, direct-call metadata, pure attributes and duplicate guards retain their checks. Pure results may feed bounded buffer addresses. Other AIR widths/vectors remain excluded, as do calls in integer-only scalar execution.

`tests/ios/air-native-mul-hi.v` passes under ASan/UBSan with LLVM 23.1.5 MCJIT on arm64 Darwin. Native references always extend i32 operands to i64 with sext/zext, multiply, shift by 32 and truncate. Disassembly of the saved native module confirms these operations and no active AIR or LLVM multiply-high calls. Unreferenced declarations remain in that module.

- 131,072 native value/address cases exercise both direct and prepared memory APIs, plus 65,536 scalar checks. Four modes cover each operation alone and alongside its LLVM equivalent. All pairs of sixteen boundary values precede deterministic/equal/complement patterns. Both argument normalization paths, shifted views and complete output padding are checked.
- 48 native loop comparisons check PHI/result-slot reuse and exact executed-step budgets. Another 12 short budgets, 26 state/discard checks and 26 profile/metadata/duplicate refusals pass. State controls cover either operand, source/result freezes and existing scalar undef refusals. Invalid memory profiles preserve marker bytes before writes.
- The previous AIR saturation checker passes another 131,072 native value/address cases, 65,536 scalar checks and 96 loops. Name, multiply-high and canonicalization unit binaries pass. The multiply-high unit checks 240,296 independent bit-column products across i1–i64, including exhaustive i1–i8 pairs, plus 17,408 vector lanes and 8,192 state checks.

A freshly compiled software Metal host passes normal and deterministic sizes runs: 448 shader images, 667,228 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen multiply-high image cases compare both AIR i32 results, after truncation, with retained LLVM i8 results for coordinates 0–63. A disagreement selects poison. Existing vector operations, the independent pixel/padding oracle and the 32-level address-expression limit remain. Each process checks two drained runtimes.

The initial native checker was correctly rejected by its exact-count assertion after a generator replacement reduced the sample bound to 4,192. The qualified rebuild uses all 16,384 samples per mode and keeps the original required counters. The initial binary, IR and failure logs remain preserved.

Generated C confirms the fixed 2,168-entry scalar cache, unchanged 61,604-entry vector cache and allocation-free successful name decoding. Existing owners, result slots, address nodes, snapshots and cleanup are reused; two i64 cache entries add 16 bytes. Retained heap was not measured and leak detection was disabled. Native JIT instructions are not sanitizer-instrumented. This extends CPU software Metal; Apple compiler emission, native GPU execution, rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-mul-hi-20261116-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-mul-hi-20261116-r1.tar.gz`.

- Archive SHA-256: `46353caef0d16353bb958f71689495f245ab97f04906fa0c897b29cbf822b210`.
- Typed inventory SHA-256: `9ff673a08bb5af5c2e11f68ed335ad65535d9ad6b6561bd10ae35c0e60e3858f`.
- Source archive SHA-256: `aaff88b05195b85ba3ed4639b70934c2b174663cdab386f3cc6ccb1ffbc6d1af`.

Complete inventory and archive comparison passes for all logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit; generated C, IR/bitcode and native disassembly, images, commands, binaries, intermediate attempts and sanitizer logs remain. Captured toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
