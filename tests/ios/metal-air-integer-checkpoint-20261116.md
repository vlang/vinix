# Software Metal AIR integer builtins checkpoint — 2026-11-16

Source revision: `f565f71ca110dbc62922fc9be2393782740a9ccc`.

Compute kernels now execute scalar `air.popcount.i32` and `air.reverse_bits.i32`, including bounded buffer addresses. The exact names/signatures follow the [AIR builder comparison cases](https://github.com/vertex-language/air/blob/main/intrinsic_test.go); its [declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go) also supplies the pure function attributes used by our synthetic fixtures. Those upstream compiler comparisons were not run here; this checkpoint compares against native LLVM equivalents.

The existing population-count and bit-reversal evaluators supply values and poison behavior. Separate keys 2154..2155 let AIR and LLVM declarations coexist without moving existing identities; the scalar cache grows to 2,156 entries. Duplicate AIR declarations still reject. The shared scanner now admits function-level `mustprogress` (LLVM bitcode enum 70), alongside the existing pure properties. Return/parameter placements, unsupported effects, types, arities and call metadata retain their guards. Other AIR widths/vectors remain excluded, as do calls in the integer-only scalar API.

`tests/ios/air-native-integer-builtins.v` passes under ASan/UBSan against LLVM 23.1.5 MCJIT on arm64 Darwin:

- 131,072 native value/address cases exercise both direct and prepared memory execution, plus 65,536 scalar checks. Four modes cover each operation, chaining, and AIR/LLVM coexistence. Inputs include single bits, complements and deterministic patterns; high argument bits, shifted byte views and complete output padding are checked.
- 24 native loop comparisons check PHI/result-slot reuse and exact executed-step budgets. Another 12 short budgets, 25 profile/metadata/duplicate refusals and 13 poison/undef/freeze/discard checks pass. Prewrite failures preserve marker bytes. Scalar undef observations retain their existing refusal, including a result freeze after an undef input.
- Focused name, integer-intrinsic, scalar-attribute, memory-attribute, canonicalization and multiply-high unit binaries pass.

A freshly compiled software Metal host passes sizes mode in both normal and deterministic hashing: 448 shader images and 667,228 checked invocations in total. Sixteen image cases use the new AIR calls across four shapes and both dispatch selectors, checking RGBA8 output and reconstructed buffer addresses. The same executable passes SIMD dispatch (1,012 dispatches, 886,400 checked invocations) and indirect dispatch (40 dispatches, 55,192 invocations, 12 deferred failures and 24 encoding refusals). Each process checks two drained runtimes.

Preserved failed attempts include an invalid reference declaration with `immarg` on a nonintrinsic, the valid fixture exposing missing `mustprogress` acceptance, and an expected-pixel calculation that read a counter after consuming it. The qualified runs include the production attribute fix and the corrected independent pixel calculation.

Generated C confirms the fixed scalar cache and allocation-free successful name decoding. Existing owners, evaluators, snapshots and cleanup are reused. Retained heap was not measured; leak detection was disabled. Native JIT instructions are not sanitizer-instrumented. This validates synthetic AIR on CPU software Metal; Apple compiler emission, native GPU execution, rendering and new Fortnite launch/frame evidence remain unverified. No kernel or guest build was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-integer-20261116-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-integer-20261116-r1.tar.gz`.

- Archive SHA-256: `45e0af682e7475ed46e8ea30c0531330d0c66b703ec3cb37b0db2471fe05cd14`.
- Typed inventory SHA-256: `f7b66a1cad343c57d09613a60c41850e39802f3ad2647f5c4f7ad6fd9afb92ad`.
- Source archive SHA-256: `e8d56786304842e6bdcce4ba19050af1b838ce02c42bf06aa991c63b61205650`.

Complete inventory and archive comparison passes for every logical file byte, path, type, mode and link, including root mode. Originals remain retained. Source pins match the feature commit; generated C, IR/bitcode, images, comparison receipts, commands, failed attempts, binaries and sanitizer logs remain. Captured toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
