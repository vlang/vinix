# Software Metal AIR float32 builtins checkpoint — 2026-11-16

Source revision: `6e1008b51c5addc2df155ddf9ce1df4146d0caf0`.

Prepared compute pipelines now execute unary `air.fabs.f32`, `air.floor.f32`, `air.ceil.f32` and `air.trunc.f32`. These exact names and float32 signatures follow the [AIR declaration builder](https://github.com/vertex-language/air/blob/main/intrinsic.go) and its [compiler comparison cases](https://github.com/vertex-language/air/blob/main/intrinsic_test.go). Our fixtures are synthetic AIR; those upstream Apple compiler comparisons were not run here.

The calls reuse existing float evaluators and state rules. `fabs` clears the sign bit while preserving every other bit, including signaling NaN payloads. Rounding operations preserve signed zeros/infinities and use the established positive canonical NaN `0x7fc00000`. Keys 2168..2171 append four independent declaration identities; the scalar cache has 2,172 entries and earlier keys remain stable. LLVM/AIR declarations coexist. Exact signatures, direct-call metadata, pure attributes, duplicate checks, prewrite validation and existing resource bounds remain required. Other AIR float overloads/vectors and floating address projections remain excluded.

`tests/ios/air-native-float-builtins.v` passes under ASan/UBSan with LLVM 23.1.5 MCJIT on arm64 Darwin. Saved native disassembly contains LLVM float operations and no active AIR calls; unused AIR declarations remain.

- 131,072 native memory cases each exercise direct and prepared APIs, plus 65,536 scalar checks. Eight modes cover four operations alone and followed by their LLVM equivalents. Boundary encodings of both signs precede deterministic raw words. Typed values carry nonzero upper bits; loaded values and output views use shifted, unaligned bindings. Complete output bytes, marker and padding are compared.
- All `fabs` bits compare exactly. For rounding, 228 scalar cases require the existing canonical NaN; only the corresponding native expected result word is normalized before memory comparison. Other finite, zero and infinite results compare exactly.
- 96 native loop comparisons check PHI/result-slot reuse and exact executed budgets. Another 24 short budgets, 28 state/discard checks, 52 metadata/profile/duplicate refusals and 20 signature/overload/address guards pass. Invalid memory profiles preserve output bytes before writes. Scalar undef retains its refusal; source/result freezes and poison propagation keep existing behavior.
- 1,024 native comparisons across all four host rounding modes pass, and scalar execution preserves the selected rounding mode. Exception flags were not qualified. The checker starts and finishes with the default floating environment.
- A freshly built AIR multiply-high regression passes 131,072 native memory cases, 65,536 scalar checks and 48 loops. Float-name, integer-name, scalar-intrinsic, multiply-high and canonicalization units pass, including 2,097,152 canonicalization checks.

A freshly compiled software Metal host passes normal and deterministic sizes runs: 448 shader images, 667,228 checked invocations, 212 rejected pipelines and four prewrite bounds failures. Sixteen canonicalization image cases also check all four new calls on positive/negative coordinate-derived fractions. Any disagreement selects poison before the independent expected pixel/padding comparison. Existing vector checks, address-expression bounds and two drained runtimes per process remain.

Generated C confirms the fixed 2,172-entry scalar cache, unchanged 61,604-entry vector cache and allocation-free successful float-name decoding. Four i64 cache entries add 32 bytes; evaluators, owners, result slots and cleanup are reused. Retained heap was not measured and leak detection was disabled. Native JIT instructions are not sanitizer-instrumented. The initial checker build failed on a helper named `nan` conflicting with `math.h`; the corrected helper and original failure log are retained. The final checker adds explicit malformed-signature and address controls without reducing the original comparison counters.

This extends CPU software Metal. Apple compiler emission, native GPU execution, rendering and new Fortnite launch/frame evidence remain unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-float-basic-20261116-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-float-basic-20261116-r1.tar.gz`.

- Archive SHA-256: `3a0f97852190d5e33a3a1a60562b34386454872fc6fc3c11198d17658d554a0a`.
- Typed inventory SHA-256: `00cd935004fb4fd41f23901d6e6f318ff69e5155f3a2c94ed0a251fc0142b406`.
- Source archive SHA-256: `d028431deb08a7dd362925bf72fa7f9f9a42847f2e6aa596760c8929850112a5`.

Complete inventory and archive comparison passes for logical bytes, paths, types, permissions and links, including root mode. Originals remain retained. Source pins match the feature commit; generated C, IR/bitcode, native disassembly, images, commands, binaries and sanitizer logs remain. Toolchain libraries are referenced externally, so the bundle is not hermetic. No restoration replay or evidence deletion is claimed.
