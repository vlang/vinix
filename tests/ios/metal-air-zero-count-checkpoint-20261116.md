# Software Metal AIR zero-count checkpoint — 2026-11-16

Source revision: `400d33155139744898dab44cf23b29612f544488`.

Prepared compute kernels execute scalar `air.clz.i32` and `air.ctz.i32` with an i32 value and constant-false i1 flag. Zero returns 32. This is the form used by the [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go); its [compiler comparison cases](https://github.com/vertex-language/air/blob/main/intrinsic_test.go) include both i32 operations. Our fixtures are synthetic AIR; those upstream Apple compiler comparisons were not run here.

The calls reuse the existing leading/trailing-zero evaluators. Keys 2160..2161 append two identities, bringing the scalar declaration cache to 2,162 entries without moving earlier keys. AIR/LLVM forms coexist. True, runtime, undef, poison and instruction-valued AIR flags reject, including after a declaration cache hit. LLVM’s separate true/poison form is unchanged. Exact signatures, direct-call metadata, pure attributes and optional exact second-parameter immarg retain their checks. Other AIR flag forms and widths/vectors remain excluded, as do calls in integer-only scalar execution.

`tests/ios/air-native-zero-count.v` passes under ASan/UBSan against LLVM 23.1.5 MCJIT on arm64 Darwin:

- 131,072 native value/address cases exercise both direct and prepared memory APIs, plus 65,536 scalar checks. Four modes cover each operation alone and alongside its LLVM equivalent. Zero, all ones, single bits, complements and deterministic patterns check all zero-count boundaries, high argument-bit normalization, shifted views and complete output padding.
- 48 native loop comparisons check PHI/result-slot reuse and exact executed-step budgets. Another 12 short budgets, 18 state/discard/LLVM-zero checks, two canonical immarg declarations and 42 profile/metadata/flag/duplicate refusals pass. Invalid memory profiles preserve marker bytes before writes. Scalar undef retains its existing refusal; direct source freezes choose zero and then count to 32.
- The previous AIR min/max checker passes another 131,072 native value/address cases, 65,536 scalar checks and 96 loops. Name, zero-count, scalar-intrinsic/attribute, canonicalization and multiply-high units pass. The zero-count unit checks 1,310,712 standard-library comparisons across i1–i64 and both LLVM flags, including 128 poison cases.

A freshly compiled software Metal host passes normal and deterministic sizes runs: 448 shader images, 667,228 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen image cases use both AIR calls in coordinate calculations across four shapes and both selectors. The pixel/padding oracle and the 32-level address-expression limit are unchanged. Each process checks two drained runtimes.

The first checker attempt incorrectly placed immarg on a nonintrinsic declaration. Its corrected fixture uses a typed-module view of LLVM ctlz for canonical AIR attribute checks. A later test assertion expected an immediate diagnostic for an instruction-valued flag; the final checker asserts the exact existing constant-pool refusal. Both failed attempts, inputs, binaries and logs remain preserved.

Generated C confirms the fixed 2,162-entry scalar cache, unchanged 61,604-entry vector cache and allocation-free successful name decoding. Existing owners, result slots, address nodes, snapshots and cleanup are reused; two i64 cache entries add 16 bytes. Retained heap was not measured and leak detection was disabled. Native JIT instructions are not sanitizer-instrumented. This extends CPU software Metal; Apple compiler emission, native GPU execution, rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-zero-count-20261116-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-zero-count-20261116-r1.tar.gz`.

- Archive SHA-256: `4d24dbbbc6e1ca5c309c3a45565ce34054451ea085d8515d85d5fa9821ca834b`.
- Typed inventory SHA-256: `6be0967c32448489ce2916bf2b359254f172c4b11e92e9cb248e19735fc028a9`.
- Source archive SHA-256: `c3ea5cac4d15d77b3e7e34bfed070f2ecd9c6b1fd2fb05f4a747f8b2692694c3`.

Complete inventory and archive comparison passes for all logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit; generated C, IR/bitcode, images, commands, binaries, intermediate attempts and sanitizer logs remain. Captured toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
