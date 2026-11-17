# AIR scalar half roots and rounding checkpoint — 2026-11-17

Feature revision: `f1b4acc08185ef48e38d056887ad3a9be7eff14b`.

Software Metal accepts scalar `air.sqrt.f16`, `air.round.f16` and `air.rint.f16`
with matching half operands/results. Existing binary16 evaluators provide nearest
square roots with ties to even, round with half ties away from zero and rint
with half ties to even, independently of the host rounding mode. Signed zeros
are preserved; arithmetic NaNs and negative nonzero square-root inputs produce
positive canonical NaN 0x7e00. Keys 2197–2199 append three identities without
moving earlier AIR/LLVM scalar/vector keys. The scalar cache has 2,200 entries;
vector entries remain 62,228.

The shared square-root helper now masks unused upper bits on its zero and
positive-infinity returns. This fixes direct evaluator calls carrying high bits
while preserving signed zero and existing normalized executor results. Tests
cover every binary16 encoding with high bits and float32 zero/infinity endpoints.

`tests/ios/air-native-half-math.v` passes under ASan/UBSan with LLVM
23.1.5 on arm64 Darwin:

- All 65,536 binary16 encodings pass for each operation, alone and followed
  by the matching LLVM call. There are 786,432 native typed/loaded memory
  cases through direct and prepared execution, including shifted views and
  complete output padding, plus 393,216 scalar results. Native arithmetic
  NaNs are normalized to the established software canonical NaN policy.
- Twenty-one poison/undef/freeze/discard checks, 39 profile/metadata/duplicate
  refusals, eighteen short budgets and sixteen signature/overload/address guards
  pass. Seventy-two native loop comparisons run through 257 visits with exact
  budgets and one-fewer-step refusals. Another 768 checks compare software results
  in four host rounding environments against captured nearest-mode native
  references, checking that software execution preserves the caller's mode.
- Another 1,024 native comparisons mix all three AIR half and float32 operations,
  checking coexistence with earlier scalar declaration-cache entries.

Saved native disassembly has ten reference functions containing fifteen half
and three float32 LLVM intrinsic calls, with no AIR or software evaluator calls.
Twenty-two unit groups pass, including 196,608 independent rational/squared-
midpoint checks for the new operations, every binary16 encoding with high-bit
masking, all earlier unary half checks, vector roots, exact keys and state.
The float32 math checker passes 98,304 native memory cases, 49,152 scalar checks,
196,608 square-root midpoint neighbors and its state/refusal/budget controls.
Its stale rejected `air.sqrt.v2f32` case now checks unsupported `air.sqrt.v2f16`;
vector float32 roots were already admitted. The unchanged earlier half-unary
checker again passes 1,048,576 native memory cases, 524,288 scalar results and
its full controls. Previous evidence and historical auditors remain.

A fresh software Metal host passes normal and deterministic sizes runs:
528 images, 755,988 checked invocations, 212 rejected pipelines and four
prewrite bounds failures. Sixteen new images check square roots of signed
4, 9, zero and signaling NaN, plus signed half ties from 0.5 through 3.5.
Explicit raw-bit comparisons gate pixel data; results contribute to the color.
Complete RGBA8/readback/padding expectations, all previous comparison rows and
nine earlier AIR image kernel bodies remain unchanged. Clipped groups, repeated
dispatches and two drained runtimes per process pass. The new shader has 76
static instructions, within the existing one-million-step dispatch budget for
4,096 invocations.

Generated host C confirms cache sizes and no allocations on successful extended
float-name and square-root helper paths; error boxing remains. Three cache
entries add 24 bytes. No owner, expression node or production resource limit
was added. Floating-dependent addresses and integer-only scalar calls retain
their exclusions. Other half AIR families and vectors remain excluded. Retained
heap was not measured; leak detection was disabled and native JIT instructions
are not sanitizer-instrumented. Fixtures are synthetic; Apple compiler emission
and native AIR/GPU comparisons were not run. Native GPU execution and new
Fortnite launch/frame evidence remain unverified. No kernel/guest build or
broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-half-math-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-half-math-20261117-r1.tar.gz`.

- Archive SHA-256: `513f5bcd61336eb443209cbbd571ee2c49560c5408ddbed83bc9966ae9e2fcef`.
- Typed inventory SHA-256: `5cb73d7d6d238924d09c0483332943895d8707a951706a3785867f3d12558477`.
- Source archive SHA-256: `070dc97067777e6bf9592404a1c69eaff4b7161f95a3fa6436482aaa7a5744fd`.

Complete inventory and archive comparison passes for logical bytes, paths,
types, permissions and links, including root mode. Originals remain retained.
Source pins match the feature revision. Source, generated host C, IR/bitcode,
native disassembly, images, commands, binaries and sanitizer logs remain.
Toolchain libraries are referenced externally; the bundle is not hermetic.
No restoration replay or evidence deletion is claimed.
