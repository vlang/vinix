# Software Metal AIR vector clamp checkpoint — 2026-11-17

Source revision: `d1618d6e06689e6d1aa67e9e17aab3ba11e488e0`.

Prepared compute pipelines now execute ternary `air.clamp.vNf32` for matching fixed 1..16-lane float32 vectors. The [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go) supplies the ternary signature, vector suffix and pure attributes. The fixtures here are synthetic; Apple compiler emission and upstream compiler comparisons were not run.

The [Metal specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf), dated 2026-06-04, page 201, defines clamp as AIR max followed by min and leaves reversed bounds undefined. The new lane helper reuses the scalar evaluator: numeric preference over NaNs, first-argument signed-zero ties and positive canonical all-NaN results. Reversed ordered bounds produce poison in that lane as an explicit software policy. NaN bounds do not satisfy the ordered comparison. Signaling-NaN quieting and preserved subnormals remain software choices beyond Metal's minimum guarantees. The primary PDF and extracted clamp/minimum pages are retained.

Keys 61764..61779 append sixteen AIR identities, bringing vector entries to 61,780. Scalar entries remain 2,179 and prior keys stay stable. Exact ternary signatures, all operand types, ordinary pure calls and duplicate checks remain required. Existing strict unfrozen undef, local poison, source/result freeze, discarded poison, lazy selection, resource bounds and ownership apply. Numeric NaN preference never suppresses poison or hides undef. Half, scalable, fast spellings and floating address projections remain excluded.

`tests/ios/air-native-vector-clamp.v` passes under ASan/UBSan with LLVM 23.1.5 MCJIT on arm64 Darwin. Native references use defined modern LLVM number operations with explicit first-zero selection, and separately classify reversed ordered bounds per lane. No undefined native clamp is executed. Saved disassembly confirms 32 LLVM declarations, 160 LLVM calls, vector bounds classifiers and zero selectors, with no active AIR calls.

- 393,216 plain typed/loaded vector cases each exercise direct and prepared memory APIs, checking values or rejecting poison stores after the earlier marker. Another 393,216 frozen vector cases compare all 3,342,336 lanes through both APIs. Before typed/loaded duplication, the native classifier covers 1,137,762 defined lanes and 533,406 domain-poison lanes; frozen poison expects zero rather than a native undefined result. There are also 196,608 scalar extractions. Three modes cover clamp, repeated clamp and AIR min/max followed by clamp. Twenty-four boundary words, deterministic triples, equal/opposite-sign bounds, upper argument bits, shifted unaligned buffers, markers and padding are checked. Only native expected NaN words are canonicalized.
- 1,296 three-source state/discard/isolation cases, 576 ordered store/repair cases, 1,120 metadata/type refusals, 240 short budgets, 192 partial-domain/repair checks, 288 host-rounding checks, 288 corrupted-result controls, seventeen overload/type/arity/address guards and a duplicate AIR refusal pass.
- Units pass 2,228,224 independent ordered-key lane/domain checks, including all 24³ boundary triples at every width, plus 4,896 three-source poison/undef checks with NaN peers. All 61,780 cache identities are covered without collisions. Scalar clamp, vector extrema, FMA/unary names, rounding, canonicalization and multiply-high units pass. The unchanged vector min/max reference passes 3,342,336 native lane comparisons and 196,608 scalar extractions, including its native loops and AIR/LLVM signed-zero distinctions.

A fresh software Metal host passes normal and deterministic sizes runs: 480 images, 702,732 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen new images check numeric clamping, both first-zero signs, NaN inputs/bounds, lane isolation and freeze/select repairs of reversed-bound poison before independent RGBA8 pixel/padding readback. Two drained runtimes per process pass. Every prior comparison row remains present in both hashing modes; each adds eight images and 8,876 invocations. The previous canonicalization kernel and dispatch budgets are unchanged.

Generated C confirms fixed 61,780-entry vector and unchanged 2,179-entry scalar caches, with no allocations on successful decoder/key/lane paths. Unsupported-input errors retain boxed-error allocation. Sixteen i64 entries add 128 bytes; existing result slots, PHI owners and cleanup are reused. Retained heap was not measured, leak detection was disabled and native JIT instructions are not sanitizer-instrumented.

This extends CPU software Metal. Native GPU execution/rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated. Initial unit qualification corrected an expected state count and an obsolete vector-name rejection; no evaluator correction or budget increase was needed. Initial and final native receipts remain in the bundle; only `reference-final/` includes the added frozen-vector comparison sweep.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-vector-clamp-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-vector-clamp-20261117-r1.tar.gz`.

- Archive SHA-256: `008ed9edcc4659dfd24cc31f33bf96ae23c952075972956e414d152c24cac211`.
- Typed inventory SHA-256: `9322753270940e0c699a26866470a9d872fddb0bd2de0c45fe59889a6b5efe0a`.
- Source archive SHA-256: `184be7a15eb62e547548d243495a9aa96c05962db35c37d403d57667765285a1`.

Complete inventory and archive comparison passes for logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit. Generated C, IR/bitcode, native disassembly, images, commands, binaries, primary PDF and sanitizer logs remain. Toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
