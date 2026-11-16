# Software Metal AIR vector FMA checkpoint — 2026-11-17

Source revision: `52c05f86241ca793b884e917c17c50337b752b9b`.

Prepared compute pipelines now execute `air.fma.vNf32` for fixed 1..16-lane float32 vectors, with three exactly matching arguments and result. The [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go) supplies the ternary math form, vector suffix and pure attributes; its [compiler comparison cases](https://github.com/vertex-language/air/blob/main/intrinsic_test.go) cover scalar FMA. This checkpoint uses synthetic vector AIR. Apple compiler emission for these shapes and upstream compiler comparisons were not run.

The [Metal specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf), dated 2026-06-04, page 206, requires FMA to combine an exact product with its addend before rounding. The existing vector/scalar FMA evaluator implements one nearest rounding with ties to even, including cancellation, overflow rescue, underflow and signed zeros. Arithmetic NaNs use the established positive canonical encoding. Preserving subnormals and treating signaling NaNs as quiet remain explicit software choices beyond Metal's minimum guarantees (page 368). The primary PDF and extracted pages are retained.

The decoder appends sixteen AIR declaration identities at keys 61716..61731. Vector entries become 61,732; scalar entries remain 2,179. Earlier LLVM/AIR keys remain stable and mixed calls coexist. Exact signatures, all three argument types, ordinary call metadata, pure attributes and duplicate checks remain required, including cached calls. Existing lane poison, strict unfrozen undef, source/result freezes, discarded poison, work/step bounds, result slots and vector-PHI ownership are reused. Half, scalable, fast spellings and floating address projections remain excluded.

`tests/ios/air-native-vector-fma.v` passes under ASan/UBSan with LLVM 23.1.5 MCJIT on arm64 Darwin:

- 196,608 typed/loaded vector cases each exercise direct and prepared memory APIs: 1,671,168 native lane comparisons and 98,304 scalar extractions across sixteen shapes in single AIR, mixed AIR/LLVM and repeated AIR modes. Every lane combines eight boundary words in 512 triples before deterministic and cancellation samples. Shifted unaligned buffers, upper bits of all three arguments, markers and padding are checked. Only native expected NaN words are canonicalized; software bits must match exactly.
- 816 native fused/unfused lane distinctions cover cancellation, overflow rescue and underflow. Single AIR calls match the fused reference; separately rounded multiply/add reference bodies produce different results for all six distinguishing triples in every lane count. These triples also occur in the typed/loaded numeric sample set.
- 1,296 three-source state/discard/isolation cases, 576 ordered store/repair cases, 960 metadata/type refusals, 240 short budgets, 36 native vector-PHI loops with executed-budget refusals, 144 host-rounding checks, 240 corrupted-result controls, sixteen overload/type/arity/address guards and a duplicate AIR identity refusal pass. Runtime poison/undef failures preserve preceding stores; invalid profiles preserve output before writes.
- Units verify all 61,732 cache identities without collisions, sixteen appended ternary keys and unchanged unary/LLVM identities. Existing vector FMA tests pass 7,888 exact fused-pattern lanes, 2,097,152 identity lanes and 9,792 three-source state checks. Rounding, canonicalization and multiply-high units pass. The unchanged AIR vector unary reference passes 974,848 native lane comparisons and 57,344 scalar extractions with its state, budget and refusal controls.

Saved native disassembly contains sixteen LLVM FMA declarations, ninety LLVM call sites, separate multiply/add control bodies and no active AIR calls. An initial fixture failed LLVM assembly because generated discard function names began with a digit. The corrected fixture and all runtime checks pass; the failed assembly and checker logs remain in the bundle.

A freshly compiled software Metal host passes normal and deterministic sizes runs: 448 shader images, 667,228 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen canonicalization image cases combine a coordinate-dependent affine lane with an alternating-sign fused-cancellation lane before the independent RGBA8 pixel/padding oracle. Two drained runtimes per process pass.

Generated C confirms the fixed 61,732-entry vector cache, unchanged 2,179-entry scalar cache and allocation-free successful decoder/key paths. Unsupported-input errors retain the existing boxed-error convention. Sixteen i64 entries add 128 bytes. No evaluator, result-slot lifetime or cleanup implementation changed. Retained heap was not measured, leak detection was disabled, and native JIT instructions are not sanitizer-instrumented.

This extends CPU software Metal. Native GPU execution/rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-vector-fma-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-vector-fma-20261117-r1.tar.gz`.

- Archive SHA-256: `ad67cc53d626b665b5306484d231a2b80170cf3c098d7635111312c75c1bfa51`.
- Typed inventory SHA-256: `0c1fe94d41ce28097142c999c678af9f03b64a8a997d78bda5764546a93a1c0f`.
- Source archive SHA-256: `a010de36c9df94fa0b7112028a990759fa4f38ee8413949067d8bb5c6017b268`.

Complete inventory and archive comparison passes for logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit. Generated C, IR/bitcode, native disassembly, images, commands, binaries, primary PDF and sanitizer logs remain. Toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
