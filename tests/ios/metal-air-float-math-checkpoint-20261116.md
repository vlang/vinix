# Software Metal AIR square root and nearest rounding checkpoint — 2026-11-16

Source revision: `ab06fe7390a35419ba71cdf31023fe4bdb2445a4`.

Prepared compute pipelines now execute unary `air.sqrt.f32`, `air.round.f32` and `air.rint.f32`. Exact names, arity and float32 signatures follow the [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go) and its [compiler comparison cases](https://github.com/vertex-language/air/blob/main/intrinsic_test.go). Our fixtures are synthetic AIR; those upstream Apple compiler comparisons were not run here.

These calls reuse existing root and rounding evaluators. Square root rounds once to nearest with ties to even, preserves negative zero and returns the established positive canonical NaN for negative nonzero inputs and NaNs. Round takes half ties away from zero; rint takes half ties to even. Results are independent of the host rounding mode. Keys 2172..2174 append three separate identities, for 2,175 scalar cache entries without moving earlier LLVM/AIR keys. Exact signatures, ordinary direct calls, pure attributes, duplicate checks, state/freeze behavior, prewrite validation and existing resource bounds remain required. Fast forms, other AIR float widths/vectors and floating address projections remain excluded.

`tests/ios/air-native-float-math.v` passes under ASan/UBSan with LLVM 23.1.5 MCJIT on arm64 Darwin. Saved native disassembly contains LLVM sqrt/round/rint calls and no active AIR calls; unused AIR declarations remain. Native references run in the default nearest floating environment.

- 98,304 native typed/loaded memory cases each exercise direct and prepared APIs, plus 49,152 scalar checks. Six modes cover the three operations alone and followed by their LLVM equivalents. Boundary encodings of both signs precede deterministic raw words; shifted unaligned bindings, nonzero upper argument bits and complete output/marker/padding comparisons are covered. For 8,376 scalar NaN cases, only the native expected result word is normalized; the software must return exactly `0x7fc00000`.
- 196,608 additional native square-root comparisons use neighbors of squared odd midpoint significands across the normal exponent range. Inputs are constructed with integer products/shifts independently of the production root/pack code.
- 72 native loop comparisons check PHI/result-slot reuse and exact executed budgets. Another 18 short budgets, 21 state/discard checks, 39 metadata/profile/duplicate refusals and 16 signature/overload/address guards pass. Invalid memory profiles preserve output bytes before writes.
- 768 scalar checks across four host rounding modes match references captured in nearest mode and preserve the selected mode. Exception flags were not qualified. The checker starts and finishes with the default environment.
- The previous AIR float checker passes 131,072 memory cases, 65,536 scalar checks and all existing controls. Its excluded-family fixture now uses rsqrt because sqrt is admitted; counters and comparisons retain their requirements. Float/integer name, scalar-intrinsic, multiply-high and canonicalization units pass, including 327,680 integer-root inequalities and 2,097,152 canonicalization checks.

A freshly compiled software Metal host passes normal and deterministic sizes runs: 448 shader images, 667,228 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen canonicalization image cases also check roots of coordinate squares and positive/negative half ties for round/rint. Any disagreement selects poison before the independent pixel/padding oracle. Earlier float/vector coverage, address bounds and two drained runtimes per process remain.

Generated C confirms the fixed 2,175-entry scalar cache, unchanged 61,604-entry vector cache and allocation-free successful name decoding. Three i64 cache entries add 24 bytes; owners, evaluators, result slots and cleanup are reused. Retained heap was not measured and leak detection was disabled. Native JIT instructions are not sanitizer-instrumented.

The initial checker build failed on shadowed local names. The first compiled checker was rejected by its exact-count assertion after a generator replacement reduced the sample bound to 6,192. The final rebuild restores all 8,192 samples per mode and retains every required counter. Failed logs, the earlier compiled checker and its source remain preserved.

This extends CPU software Metal. Apple compiler emission, native GPU execution/rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-float-math-20261116-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-float-math-20261116-r1.tar.gz`.

- Archive SHA-256: `e7ec7a21b271c6c3fcb9e05df8f2dc9f78b227ac5226b698af7378434ef51594`.
- Typed inventory SHA-256: `70999b42fed8f1e2638365aac62627da0950df9773dc0c0b327515f4e05cf8f8`.
- Source archive SHA-256: `69d70284a38bb27142608b69c0b73814ea3067d55aebfd4a060880416113595c`.

Complete inventory and archive comparison passes for logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit; generated C, IR/bitcode, native disassembly, images, commands, binaries and sanitizer logs remain. Toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
