# AIR scalar i64 saturation checkpoint — 2026-11-17

Feature revision: `5945ed0ae34bb0e29f68053977eae35128ca9f6a`.

Software Metal accepts scalar `air.add_sat.s.i64`, `air.sub_sat.s.i64`,
`air.add_sat.u.i64` and `air.sub_sat.u.i64` with matching i64 operands/results.
The existing evaluators clamp signed overflow to the signed endpoint, unsigned
addition overflow to UINT64_MAX and unsigned subtraction underflow to zero.
Keys 2187–2190 append four identities without moving earlier scalar/vector
AIR/LLVM keys. The scalar cache has 2,191 entries; vector entries remain 62,228.

`tests/ios/air-native-scalar-saturating64.v` passes under ASan/UBSan with
LLVM 23.1.5 on arm64 Darwin:

- 131,072 native value/address comparisons check all four operations and
  AIR/LLVM coexistence through direct and prepared memory execution, including
  full output padding and shifted views. The 65,536 scalar results also match
  an independent signed-margin/unsigned-limb-carry oracle. Inputs cover all
  pairs of sixteen boundaries, equal/complement pairs and full-width patterns.
- Fifty-two poison/undef/freeze/discard checks, 52 profile/metadata/duplicate
  refusals and 24 short budgets pass. Ninety-six native loop comparisons run
  through 257 visits with exact budgets and one-fewer-step refusals.
- Another 1,024 checks combine each i32/i64 saturation family with AIR
  population count, leading-zero count and float absolute value, checking
  coexistence with earlier scalar cache families.

Saved native disassembly contains twenty reference functions with twenty-eight
LLVM i64 saturation calls. Twenty-one unit groups pass, including 1,303,888
independent margin/carry saturation comparisons across all i1–i64 widths,
exhaustive i1–i8 pairs, exact AIR names/keys/widths, floats, conversions,
zero counts, extrema, vector state and multiply-high. The unchanged maintained
i32 saturation checker again passes 131,072 native comparisons, 65,536 scalar
checks and its existing state/refusal/budget controls.

A fresh software Metal host passes normal and deterministic sizes runs:
496 images, 720,484 checked invocations, 212 rejected pipelines and four
prewrite bounds failures. Sixteen updated saturation images compare the four
scalar i64 calls with LLVM and explicit endpoints, alternating both signed
clamp directions and exercising unsigned overflow/underflow. Scalar unsigned
subtraction reconstructs the actual store coordinate; comparisons gate pixel
data. Complete RGBA8/readback/padding expectations, all previous comparison
rows and seven other AIR image kernel bodies remain unchanged. Clipped groups,
repeated dispatches and two drained runtimes per process pass. The dispatch
instruction budget and address-expression bounds remain unchanged.

Generated host C confirms cache sizes and no allocations on successful extended
name/width paths; error boxing remains. Four cache entries add 32 bytes.
No evaluator, owner, expression node or production resource limit was added.
Scalar-load-dependent addresses and integer-only scalar calls retain their
exclusions. Other scalar AIR i64 integer families remain excluded. Retained
heap was not measured; leak detection was disabled and native JIT instructions
are not sanitizer-instrumented. Fixtures are synthetic; Apple compiler emission
and native AIR/GPU comparisons were not run. Native GPU execution and new
Fortnite launch/frame evidence remain unverified. No kernel/guest build or
broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-scalar-saturating64-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-scalar-saturating64-20261117-r1.tar.gz`.

- Archive SHA-256: `9b4be2f9ebc56be5c5e5abc6b2161c53574c9096ea455d007e7274fac8645d61`.
- Typed inventory SHA-256: `1c34493a438dea715891c1eac57cc175522516e727737a43552dbeddd47d9ea3`.
- Source archive SHA-256: `6e9ae186763260edae1e5a0e310f3616c21c7413c397b638de560eccd71fc32d`.

Complete inventory and archive comparison passes for logical bytes, paths,
types, permissions and links, including root mode. Originals remain retained.
Source pins match the feature revision. Source, generated host C, IR/bitcode,
native disassembly, images, commands, binaries and sanitizer logs remain.
Toolchain libraries are referenced externally; the bundle is not hermetic.
No restoration replay or evidence deletion is claimed.
