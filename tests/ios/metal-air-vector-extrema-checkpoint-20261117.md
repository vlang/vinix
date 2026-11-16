# Software Metal AIR vector min/max checkpoint — 2026-11-17

Source revision: `16f391591bdc8bedbd0f1de258071f504fc5e171`.

Prepared compute pipelines now execute binary `air.fmin.vNf32` and `air.fmax.vNf32` for matching fixed 1..16-lane float32 vectors. The [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go) supplies math signatures, vector suffixes and pure attributes; its [compiler comparison cases](https://github.com/vertex-language/air/blob/main/intrinsic_test.go) cover scalar extrema. These vector fixtures are synthetic; Apple compiler emission and upstream compiler comparisons were not run.

The [Metal specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf), dated 2026-06-04, pages 206–207, specifies numeric preference over NaN and first-argument choice on numeric ties. The new lane helper reuses the scalar AIR evaluator, including first signed zero and positive canonical all-NaN results. Treating signaling NaNs as quiet and preserving subnormals remain software choices beyond Metal's minimum guarantees (page 368). The primary PDF and extracted pages are retained.

Keys 61732..61763 append 32 AIR identities, bringing vector entries to 61,764. Scalar entries remain 2,179 and prior keys stay stable. Exact binary signatures, both operand types, ordinary pure calls and duplicate checks remain required, including cached calls. Existing local lane poison, strict unfrozen undef, source/result freezes, discarded poison, resource bounds and ownership apply. NaN preference does not discard poison or hide undef. Half, scalable, fast spellings and floating address projections remain excluded.

`tests/ios/air-native-vector-extrema.v` passes under ASan/UBSan with LLVM 23.1.5 MCJIT on arm64 Darwin. Native references use modern LLVM number extrema plus explicit first-zero selection for AIR calls. Mixed chains retain LLVM zero ordering. Saved disassembly confirms 32 LLVM declarations, 212 LLVM calls, vector zero selectors and no active AIR calls. This qualifies the explicit software policy, not native Apple GPU behavior.

- 393,216 typed/loaded vector cases each exercise direct and prepared memory APIs: 3,342,336 native lane comparisons and 196,608 scalar extractions. Six modes cover each AIR operation, AIR min/max compositions and AIR/LLVM compositions. Every lane combines twenty-four boundary words in 576 pairs before deterministic/equal/opposite-sign samples. Upper argument bits, unaligned shifted buffers, markers and padding are checked. Only native expected NaN words are canonicalized.
- 1,728 two-source state/discard/isolation cases with NaN peers, 768 ordered store/repair cases, 1,760 metadata/type refusals, 480 short budgets, 72 native vector-PHI loops with executed-budget refusals, 288 host-rounding checks, 272 AIR/LLVM zero-order distinctions, 480 corrupted-result controls, thirty overload/type/arity/address guards and a duplicate AIR refusal pass.
- Units pass 2,228,224 independent ordered-key lane comparisons, 6,528 poison/undef checks with NaN peers and all 61,764 cache identities without collisions. Scalar AIR extrema, LLVM vector min/max, rounding, canonicalization, multiply-high and existing AIR name units pass. The unchanged vector FMA reference passes 1,671,168 native lane comparisons and 98,304 scalar extractions, including its fused/unfused controls.

A fresh software Metal host passes normal and deterministic sizes runs: 464 images, 684,980 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen new images check coordinate extrema, both first-zero signs and NaN preference against independent expectations before RGBA8 pixel/padding readback. Two drained runtimes per process pass.

The initial combined fixture exceeded the dispatch instruction budget; its failed run remains under `software/`. The successful `software-separated/` build adds a dedicated extrema kernel. The budget is unchanged, the previous canonicalization kernel is byte-for-byte unchanged, and every prior comparison row remains present in both hashing modes. Each mode adds eight images and 8,876 invocations.

Generated C confirms fixed 61,764-entry vector and unchanged 2,179-entry scalar caches, with no allocations on successful decoder/key/lane paths. Unsupported-input errors retain boxed-error allocation. Thirty-two i64 entries add 256 bytes; existing result slots, PHI owners and cleanup are reused. Retained heap was not measured, leak detection was disabled and native JIT instructions are not sanitizer-instrumented.

This extends CPU software Metal. Native GPU execution/rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-vector-extrema-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-vector-extrema-20261117-r1.tar.gz`.

- Archive SHA-256: `dd060a65b9c5110be5a09303e3a5339874782c54ab5263b10f19bb30e2bace2d`.
- Typed inventory SHA-256: `0d440516f11fdc3e9fb28279f17854141efadd837e35150856803f73b7ed8f86`.
- Source archive SHA-256: `8a6d7bf0d57f94ead7629f91a898573745c495aec2610b8ec06bd8a62d59a7bb`.

Complete inventory and archive comparison passes for logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit. Generated C, IR/bitcode, native disassembly, images, commands, binaries, primary PDF and sanitizer logs remain. Toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
