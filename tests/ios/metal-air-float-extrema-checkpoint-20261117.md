# Software Metal AIR float32 min/max checkpoint — 2026-11-17

Source revision: `090d3baedb3257cfa564cf32cee8e91f7e88e2a2`.

Prepared compute pipelines now execute binary `air.fmin.f32` and `air.fmax.f32`. Their names/signatures follow the [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go) and its [compiler comparison cases](https://github.com/vertex-language/air/blob/main/intrinsic_test.go). Fixtures are synthetic AIR; those upstream Apple compiler comparisons were not run here.

The [Metal specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf), dated 2026-06-04, pages 206–207, specifies numeric preference over a NaN and first-argument selection on numeric ties. The latter preserves the first signed zero even when the second zero has the opposite sign. Separate appended AIR enum IDs preserve that behavior without changing the existing LLVM extrema policy. A float32 wrapper normalizes inputs, handles zero ties and delegates other values to the existing number evaluator. Both NaNs produce the existing positive canonical NaN. The software treats signaling NaNs as quiet for numeric preference and preserves numeric subnormals; these are explicit choices beyond Metal's minimum guarantees (page 368). The primary PDF and extracted pages are retained in the bundle.

Keys 2176..2177 append two AIR declaration identities, bringing the scalar cache to 2,178 entries without moving earlier keys. Exact signatures, ordinary direct calls, pure attributes, duplicate checks and both operand types remain checked, including cached calls. Other widths/vectors, fast spellings and floating address projections remain excluded. State/freeze, budgets, prewrite profile checks and runtime write ordering retain their rules.

`tests/ios/air-native-float-extrema.v` passes under ASan/UBSan with LLVM 23.1.5 MCJIT on arm64 Darwin. References use modern LLVM number extrema plus an explicit first-operand selection when both arguments are zero, applied only to AIR calls. LLVM calls in mixed chains retain LLVM zero ordering. Saved native disassembly confirms modern calls/selects and no active AIR or legacy LLVM extrema calls. This qualifies the explicit Metal policy; it is not an unmodified native legacy-minnum comparison.

- 98,304 native typed/loaded memory cases each exercise direct and prepared APIs, plus 49,152 scalar checks. Six modes cover each AIR call alone, AIR/LLVM chains and mixed AIR min/max chains. All pairs of twenty-four boundary words precede deterministic/equal/complement samples: 3,456 boundary cases across the modes. Shifted unaligned bindings, upper argument bits and complete output/marker/padding bytes are checked. For 282 scalar NaN cases, only the native expected result word is normalized; the software must return exactly `0x7fc00000`.
- 48 native loops check PHI/result-slot reuse and executed budgets. Another 18 short budgets, 120 metadata/type/profile refusals, 18 signature/overload/address guards and five corrupted-result controls pass. Invalid profiles preserve output before writes.
- 28 state/discard checks exercise both operands with a NaN peer. Eight runtime poison/undef cases preserve the preceding marker and reject the result store; eight freeze/lazy repairs check defined bytes and padding through both memory APIs. Numeric NaN preference does not discard poison or bypass scalar undef refusal.
- 768 scalar checks across four host rounding modes match references captured in nearest mode and preserve the selected mode. Exception flags were not qualified; the process starts and finishes with the default environment.
- Units pass 262,144 independent comparisons using ordered integer keys, both input orders, first-zero cases, input normalization and unchanged LLVM zero ordering. Existing scalar-intrinsic, integer/float-name, multiply-high and canonicalization units pass. The unchanged AIR FMA regression passes 98,304 memory cases, 49,152 scalar checks and its fused/unfused controls.

A freshly compiled software Metal host passes normal and deterministic sizes runs: 448 shader images, 667,228 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen canonicalization image cases additionally check coordinate extrema, NaN preference and raw bits for both first-zero signs. Disagreement selects poison before the independent pixel/padding oracle. Earlier unary/FMA/vector coverage, address bounds and two drained runtimes per process remain.

Generated C confirms the fixed 2,178-entry scalar cache, unchanged 61,604-entry vector cache and allocation-free successful decoding/wrapper paths. Two i64 cache entries add sixteen bytes; owners, result slots, snapshots and cleanup are reused. Retained heap was not measured and leak detection was disabled. Native JIT instructions are not sanitizer-instrumented.

This extends CPU software Metal. Apple compiler emission, native GPU execution/rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-float-extrema-20261116-r1` (the directory retains its initial run label).

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-float-extrema-20261116-r1.tar.gz`.

- Archive SHA-256: `0cba0f482abdb430f3b691398add75d3c5830d73b6f04e447859e07fb0fdcb1b`.
- Typed inventory SHA-256: `a9887969bc075fe5f34d1b6ee31d98fd45b30d7fbea038f59bf75ecf077e3495`.
- Source archive SHA-256: `3ad5069047abe019dd4bcd6df7cb6f59b1b82b7ca4842fc6dc354e31d31e5513`.

Complete inventory and archive comparison passes for logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit; generated C, IR/bitcode, native disassembly, images, commands, binaries, the primary PDF and sanitizer logs remain. Toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
