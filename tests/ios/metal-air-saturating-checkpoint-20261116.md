# Software Metal AIR saturating add/subtract checkpoint — 2026-11-16

Source revision: `a83efd06e994eab039163c72a148d4e002d0817d`.

Prepared compute kernels execute scalar `air.add_sat.s.i32`, `air.sub_sat.s.i32`, `air.add_sat.u.i32` and `air.sub_sat.u.i32`. Their signed/unsigned names and binary signatures follow the [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go); its [compiler comparison cases](https://github.com/vertex-language/air/blob/main/intrinsic_test.go) include unsigned addition and signed subtraction. Our fixtures use synthetic AIR and native LLVM references; those upstream Apple compiler comparisons were not run here.

The four calls reuse existing saturation IDs, normalization and evaluators. Overflow/underflow clamps to the signed limits or unsigned zero/maximum; input poison still propagates. Keys 2162..2165 append four identities, bringing the scalar declaration cache to 2,166 entries without moving earlier keys. LLVM/AIR forms coexist. Exact i32 signatures, direct-call metadata, pure attributes and duplicate guards retain their checks. Other AIR widths/vectors remain excluded, as do calls in integer-only scalar execution.

`tests/ios/air-native-saturating-builtins.v` passes under ASan/UBSan against LLVM 23.1.5 MCJIT on arm64 Darwin:

- 131,072 native value/address cases exercise both direct and prepared memory APIs, plus 65,536 scalar checks. Eight modes cover each operation alone and alongside its LLVM equivalent. All pairs of sixteen boundary values precede deterministic/equal/complement patterns, covering overflow, underflow, both argument normalization paths, shifted views and complete output padding.
- 96 native loop comparisons check PHI/result-slot reuse and exact executed-step budgets. Another 24 short budgets, 52 state/discard checks and 52 profile/metadata/duplicate refusals pass. State controls cover either operand, source/result freezes and existing scalar undef refusals. Invalid memory profiles preserve marker bytes before writes.
- The previous AIR zero-count checker passes another 131,072 native value/address cases, 65,536 scalar checks and 48 loops, including its flag and attribute controls. Name, saturation, canonicalization and multiply-high unit binaries pass. The saturation unit checks 1,303,888 independent margin/carry comparisons across i1–i64, including exhaustive i1–i8 pairs and 36,864 edge pairs.

A freshly compiled software Metal host passes normal and deterministic sizes runs: 448 shader images, 667,228 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen image cases use all four AIR saturation calls in coordinate calculations across four shapes and both selectors. The pixel/padding oracle and the 32-level address-expression limit are unchanged. Each process checks two drained runtimes.

Generated C confirms the fixed 2,166-entry scalar cache, unchanged 61,604-entry vector cache and allocation-free successful name decoding. Existing owners, result slots, address nodes, snapshots and cleanup are reused; four i64 cache entries add 32 bytes. Retained heap was not measured and leak detection was disabled. Native JIT instructions are not sanitizer-instrumented. This extends CPU software Metal; Apple compiler emission, native GPU execution, rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-saturating-20261116-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-saturating-20261116-r1.tar.gz`.

- Archive SHA-256: `cdacdecc7106b79120521fb4d763b84bc8e1a30f2071039b6a3c1a7366730890`.
- Typed inventory SHA-256: `21a9a3c7dbc556287053899a9bd48cfe67e15b8c22ed11e0710b35539c19ecb5`.
- Source archive SHA-256: `b258400afccfd92cc9e5258f848e7677068126d9fe988032b87d62dd53e5b2af`.

Complete inventory and archive comparison passes for all logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit; generated C, IR/bitcode, images, commands, binaries and sanitizer logs remain. Captured toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
