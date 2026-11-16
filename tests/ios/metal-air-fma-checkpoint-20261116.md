# Software Metal AIR fused multiply-add checkpoint — 2026-11-16

Source revision: `3fb1c18f04703f05290a179560a43f5084f95b3b`.

Prepared compute pipelines now execute ternary `air.fma.f32` using the existing exact float32 fused multiply-add evaluator. The name and three-argument signature follow the [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go) and its [compiler comparison cases](https://github.com/vertex-language/air/blob/main/intrinsic_test.go); that builder uses the same name for precise and fast MSL FMA. Our fixtures are synthetic AIR; those upstream Apple compiler comparisons were not run here.

The evaluator adds the exact product to the addend before one nearest rounding with ties to even, independent of the host rounding mode. Existing signed-zero, subnormal, infinity, canonical-NaN and state/freeze rules are reused. Slot 2175 appends one AIR identity, for 2,176 scalar cache entries without moving earlier LLVM/AIR keys. Exact signatures, ordinary direct calls, pure attributes, duplicate checks and all three operand types remain checked, including cached calls. Half/vector overloads, unknown AIR spellings and floating address projections remain excluded.

`tests/ios/air-native-fma.v` passes under ASan/UBSan with LLVM 23.1.5 MCJIT on arm64 Darwin. Saved native disassembly contains LLVM FMA calls and a separate fmul/fadd reference, with no active AIR calls. Native references run in the default nearest floating environment.

- 98,304 native typed/loaded memory cases each exercise direct and prepared APIs, plus 49,152 scalar checks. Three modes cover one AIR call, an AIR/LLVM chain and two calls sharing the AIR declaration. Every triple from twenty boundary words precedes deterministic raw/cancellation samples, giving 24,000 boundary cases across the modes. Shifted unaligned bindings, upper argument bits and complete output/marker/padding bytes are checked. For 12,794 scalar NaN cases, only the native expected word is normalized; the software must return exactly `0x7fc00000`.
- 24 native loops check PHI/result-slot reuse and exact executed budgets. Another nine short budgets, 21 state/discard checks, 65 metadata/type/profile refusals, twelve signature/overload/address guards and five corrupted-result controls pass. Metadata/type failures preserve all output bytes before writes.
- Six runtime poison/undef cases check each argument through both memory APIs: the preceding marker store remains and the rejected result store/padding stay untouched. Six freeze/lazy-selection repairs check defined result bytes and preserved padding. Runtime value failures retain earlier writes; they do not undo them.
- Six finite cases distinguish fused execution from native separate multiply/add, covering cancellation signs/order, overflow recovery and subnormal rounding. Forty-eight scalar checks across four host rounding modes match references captured in nearest mode and preserve the selected mode. Exception flags were not qualified; the process starts and finishes with the default environment.
- The unchanged previous AIR math checker passes 98,304 memory cases, 49,152 scalar checks and 196,608 square-root boundary comparisons. Float/integer-name, scalar-FMA, multiply-high and canonicalization units pass, including 58 exact FMA cases, six independent unfused distinctions and 2,097,152 canonicalization checks.

A freshly compiled software Metal host passes normal and deterministic sizes runs: 448 shader images, 667,228 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen canonicalization image cases additionally check a coordinate-dependent affine FMA and alternating positive/negative cancellation whose exact nonzero bits distinguish fused execution. Any disagreement selects poison before the independent pixel/padding oracle. Earlier unary/vector coverage, address bounds and two drained runtimes per process remain.

Generated C confirms the fixed 2,176-entry scalar cache, unchanged 61,604-entry vector cache and allocation-free successful name decoding. One i64 cache entry adds eight bytes; owners, exact fixed-stack-limb evaluator, result slots and cleanup are reused. Retained heap was not measured and leak detection was disabled. Native JIT instructions are not sanitizer-instrumented.

The initial checker incorrectly expected the marker preceding a poison store to be undone. The corrected test checks the existing write ordering explicitly; unchanged-output controls for malformed calls/types remain. Failed checkers, sources, IR and logs are preserved. No production execution semantics were changed to handle this test failure.

This extends CPU software Metal. Apple compiler emission, native GPU execution/rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-fma-20261116-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-fma-20261116-r1.tar.gz`.

- Archive SHA-256: `90eb1b2064feb0a4acf2400351fb545ebed164e16602065410515ecc592d0f3f`.
- Typed inventory SHA-256: `e930b49b41cd8f5b7bbd7e382a40194384a024c2086a27b2561e61ca738e10fb`.
- Source archive SHA-256: `901766454bc5073808d4a788e182be75a86438b9cf598b1957b75568b55fe845`.

Complete inventory and archive comparison passes for logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit; generated C, IR/bitcode, native disassembly, images, commands, binaries and sanitizer logs remain. Toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
