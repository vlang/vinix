# AIR scalar i64 min/max checkpoint — 2026-11-17

Feature revision: `44ad5c19abb9a97e93734deb206c6dfa09986449`.

Software Metal accepts scalar `air.min.s.i64`, `air.max.s.i64`,
`air.min.u.i64` and `air.max.u.i64` with matching i64 operands/results.
The existing signed/unsigned extrema evaluators and pure checked address
expressions supply their results. Keys 2181–2184 append four identities;
earlier AIR/LLVM/scalar/vector keys remain stable. The scalar cache has
2,185 entries; vector entries remain 62,228.

`tests/ios/air-native-scalar-extrema64.v` passes under ASan/UBSan with
LLVM 23.1.5 on arm64 Darwin:

- 131,072 native value/address comparisons check all four operations and
  AIR/LLVM coexistence through direct and prepared memory execution, including
  full output padding. The 65,536 scalar results also match an independent
  sign/unsigned-order oracle. Inputs include every pair of sixteen endpoints,
  sign and 32-bit boundaries, equal/complement pairs and full-width patterns.
- Fifty-two poison/undef/freeze/discard checks, 52 profile/metadata/duplicate
  refusals and 24 short budgets pass. Ninety-six native loop comparisons run
  through 257 visits with exact budgets and one-fewer-step refusals.
- Another 256 checks combine all four i32/i64 AIR extrema, an AIR float call
  and i64 population count in one function, checking cache coexistence.

Saved native disassembly contains twenty reference functions with twenty-eight
LLVM i64 extrema calls. Twenty-one unit groups pass, including 1,267,024
independent scalar extrema comparisons and vector extrema value/state checks,
exact names/keys, floats, conversions, saturation, zero counts and multiply-high.
The unchanged maintained i32 extrema checker again passes 131,072 native
comparisons, 65,536 scalar checks and its existing refusal/budget controls.

A fresh software Metal host passes normal and deterministic sizes runs:
480 images, 702,732 checked invocations, 212 rejected pipelines and four
prewrite bounds failures. Sixteen updated min/max images compare the four
scalar i64 calls with LLVM and explicit comparison/select results, alternating
the input sign bit. Unsigned extrema reconstruct the checked output coordinate;
comparisons gate pixel data. Complete RGBA8/readback/padding expectations,
all prior comparison rows and six other AIR image kernels remain unchanged.
Clipped groups, repeated dispatches and two drained runtimes per process pass.

Generated host C confirms cache sizes and no allocations on successful extended
name/width paths; error boxing remains. Four cache entries add 32 bytes.
No evaluator, owner, expression node or resource limit was added. Scalar-load-
dependent addresses and integer-only scalar calls retain their exclusions.
Other scalar AIR i64 integer families remain excluded. Retained heap was not
measured; leak detection was disabled and native JIT instructions are not
sanitizer-instrumented. Fixtures are synthetic; Apple compiler emission and
native AIR/GPU comparisons were not run. Native GPU execution and new Fortnite
launch/frame evidence remain unverified. No kernel/guest build or broader
SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-scalar-extrema64-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-scalar-extrema64-20261117-r1.tar.gz`.

- Archive SHA-256: `fe9a5c520a4e9c4bfe226e43ed81c9f0bf0d3c9e79ccf85bf37fb2236ea5a61a`.
- Typed inventory SHA-256: `0736ed0b56df22e0c79acd4677ee20393840b05d54816844056971d145c99852`.
- Source archive SHA-256: `e8d6d8f82401de076a4444cdf92165390916307a9bde0818050788620459ea67`.

Complete inventory and archive comparison passes for logical bytes, paths,
types, permissions and links, including root mode. Originals remain retained.
Source pins match the feature revision. Source, generated host C, IR/bitcode,
native disassembly, images, commands, binaries and sanitizer logs remain.
Toolchain libraries are referenced externally; the bundle is not hermetic.
No restoration replay or evidence deletion is claimed.
