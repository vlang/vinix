# Software Metal AIR float32 clamp checkpoint — 2026-11-17

Source revision: `c03b42db3893e3d752fc87c673b7375825970ae7`.

Prepared compute pipelines now execute ternary `air.clamp.f32`. The exact name and signature follow the [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go) and its [compiler comparison cases](https://github.com/vertex-language/air/blob/main/intrinsic_test.go). Fixtures are synthetic AIR; upstream Apple compiler comparisons were not run here.

The [Metal specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf), dated 2026-06-04, page 201, defines clamp as `fmin(fmax(x, low), high)` and leaves reversed bounds undefined. This implementation chooses poison for ordered `low > high`. NaN bounds do not satisfy that comparison. Existing AIR extrema preserve numeric NaN preference and the first argument on numeric ties, including opposite signed zeros (pages 206–207). All-NaN composition produces the existing positive canonical NaN. Treating signaling NaNs as quiet and preserving numeric subnormals remain explicit software choices beyond Metal's minimum guarantees (page 368). The primary PDF and extracted pages are retained.

The new helper uses integer-bit comparison and the existing AIR extrema evaluators. It observes all three input states before evaluation. Domain poison may be discarded, frozen to zero or bypassed by an unchosen lazy-select arm; an observed poison store rejects while retaining earlier stores. Scalar undef still refuses until frozen. Key 2178 appends one declaration identity, bringing the scalar cache to 2,179 entries without moving earlier keys. Exact float32 types, ordinary calls, pure attributes and duplicate checks remain required. Other widths/vectors, fast spellings and floating address projections remain excluded.

`tests/ios/air-native-clamp.v` passes under ASan/UBSan with LLVM 23.1.5 MCJIT on arm64 Darwin. Its native reference first classifies reversed bounds with ordered comparison, then uses defined modern LLVM number extrema plus explicit AIR first-zero selection. It never executes an undefined native clamp. Saved disassembly confirms the classifier, modern extrema/selects and absence of active AIR calls.

- 49,152 scalar cases: 27,444 native values and 21,708 domain-poison results, including 192 canonical NaNs and 24,000 boundary triples. Three modes cover clamp alone, repeated clamp and mixed AIR min/max/clamp. All twenty boundary words are combined before deterministic samples. Upper argument bits are ignored as required.
- 98,304 typed/loaded memory cases each exercise direct and prepared APIs. Unaligned shifted bindings, marker and padding bytes are checked. Invalid-bounds stores reject after the marker; prewrite validation leaves output untouched.
- 21 state/discard cases, six ordered poison/undef stores, six memory repairs, seven invalid-bounds discard/freeze/select/store cases, 75 metadata/type/profile refusals, nine short budgets, 24 native loops with executed-budget refusals, 48 host-rounding checks, six corrupted-result controls and twelve signature/overload/address guards pass.
- Units pass 131,072 independent ordered-key domain/composition comparisons, including 48,148 poison results, all zero signs and input normalization. Existing extrema, scalar-intrinsic, float/integer-name, canonicalization and multiply-high units pass. The unchanged AIR extrema regression passes 98,304 memory cases and 49,152 scalar checks with its state, rounding and refusal controls.

A freshly compiled software Metal host passes normal and deterministic sizes runs: 448 shader images, 667,228 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen canonicalization image cases check clipping against an independent comparison/select result, NaN input, both first-zero signs and invalid-bounds freeze/lazy recovery before the independent RGBA8 pixel/padding oracle. Two drained runtimes per process pass.

Generated C confirms the fixed 2,179-entry scalar cache, unchanged 61,604-entry vector cache and allocation-free successful decoding/clamp paths. One i64 cache entry adds eight bytes. Existing owners, result slots and cleanup are reused. Retained heap was not measured; leak detection was disabled. Native JIT instructions are not sanitizer-instrumented. An initial checker build failed on duplicate local names; the corrected build and all runtime checks pass, and the failed build log is retained.

This extends CPU software Metal. Apple compiler emission, native GPU execution/rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-clamp-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-clamp-20261117-r1.tar.gz`.

- Archive SHA-256: `0e452e495dd25fd1987e7a4dfb4cb3447bed5102054917fc8ad6b9cc52d28c82`.
- Typed inventory SHA-256: `a0420a04d8190d4470b0ad057597842a2fb2203d09f73b292719ace0f1b6cc75`.
- Source archive SHA-256: `2c7fa8971f7d5a12fd7333cc749fc5e51aa65b0a17a25ebb0b429d45ecf7a3ec`.

Complete inventory and archive comparison passes for logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit; generated C, IR/bitcode, native disassembly, images, commands, binaries, primary PDF and sanitizer logs remain. Toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
