# AIR scalar half unary checkpoint — 2026-11-17

Feature revision: `f8abccb613c6a606875fdf190d44fcfd86ff5250`.

Software Metal accepts scalar `air.fabs.f16`, `air.floor.f16`, `air.ceil.f16`
and `air.trunc.f16` with matching half operands/results. The existing binary16
value evaluators are reused. Absolute value clears only the sign bit, including
NaN payload/signaling bits. Rounding preserves signed zeros and infinities and
uses positive canonical NaN 0x7e00. Keys 2193–2196 append four identities without
moving earlier AIR/LLVM scalar/vector keys. The scalar cache has 2,197 entries;
vector entries remain 62,228.

`tests/ios/air-native-half-builtins.v` passes under ASan/UBSan with LLVM
23.1.5 on arm64 Darwin:

- All 65,536 binary16 encodings pass for each operation, alone and followed
  by the matching LLVM call. There are 1,048,576 native typed/loaded memory
  cases through direct and prepared execution, including shifted views and
  complete output padding, plus 524,288 scalar results. Native rounding NaNs
  are normalized to the established software canonical NaN policy; fabs
  compares exact payload/signaling bits.
- Twenty-eight poison/undef/freeze/discard checks, 52 profile/metadata/duplicate
  refusals, 24 short budgets and twenty signature/overload/address guards pass.
  Ninety-six native loop comparisons run through 257 visits with exact budgets
  and one-fewer-step refusals. Another 1,024 checks compare native results in
  four host rounding environments without changing the caller's rounding mode.
- Another 1,024 native comparisons mix all four AIR half and float32 operations,
  checking coexistence with earlier scalar declaration-cache entries.

Saved native disassembly has thirteen reference functions containing twenty
half and four float32 LLVM intrinsic calls, with no AIR calls or software
evaluator calls. Twenty-one unit groups pass, including 262,144 independent
rational/bit binary16 unary checks, every encoding with high-bit masking,
exact names/keys, conversions, floats, integer families and vector state.
The maintained float32 checker again passes 131,072 native memory cases,
65,536 scalar checks and its state/refusal/budget controls. Its stale rejected
`air.floor.v2f32` case now checks unsupported `air.floor.v2f16`; vector float32
rounding was already admitted. Previous evidence and historical auditors remain.

A fresh software Metal host passes normal and deterministic sizes runs:
512 images, 738,236 checked invocations, 212 rejected pipelines and four
prewrite bounds failures. Sixteen new half images check both signs of the
smallest subnormal, 1.25, 1.5 and a signaling NaN against explicit raw bits.
Results gate and contribute to pixel data. Complete RGBA8/readback/padding
expectations, all previous comparison rows and eight earlier AIR image kernel
bodies remain unchanged. Clipped groups, repeated dispatches and two drained
runtimes per process pass. The new shader has ninety static instructions,
within the existing one-million-step dispatch budget for 4,096 invocations.

Generated host C confirms cache sizes and no allocations on successful extended
float-name paths; error boxing remains. Four cache entries add 32 bytes.
No evaluator, owner, expression node or production resource limit was added.
Floating-dependent addresses and integer-only scalar calls retain their
exclusions. Other half AIR families and vectors remain excluded. Retained heap
was not measured; leak detection was disabled and native JIT instructions are
not sanitizer-instrumented. Fixtures are synthetic; Apple compiler emission
and native AIR/GPU comparisons were not run. Native GPU execution and new
Fortnite launch/frame evidence remain unverified. No kernel/guest build or
broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-half-unary-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-half-unary-20261117-r1.tar.gz`.

- Archive SHA-256: `ede84ffb7d7a40ff468a93aa93d48d72e454d05382de52a0bd1f6e2f05f1e779`.
- Typed inventory SHA-256: `126605fc282577125bbf4e040c7b539244c0424afa1d3566929fb6fb36b9741d`.
- Source archive SHA-256: `38819f40a7b3e225c049fa8de0f9c838ba36a6eaa62d8c5b3cf93782067fa4bb`.

Complete inventory and archive comparison passes for logical bytes, paths,
types, permissions and links, including root mode. Originals remain retained.
Source pins match the feature revision. Source, generated host C, IR/bitcode,
native disassembly, images, commands, binaries and sanitizer logs remain.
Toolchain libraries are referenced externally; the bundle is not hermetic.
No restoration replay or evidence deletion is claimed.
