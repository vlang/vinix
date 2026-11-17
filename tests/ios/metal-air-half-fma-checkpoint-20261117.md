# AIR scalar half fused multiply-add checkpoint — 2026-11-17

Feature revision: `f499ea26a961561ee6aa00ccf3518954475697d8`.

Software Metal accepts ternary `air.fma.f16` with three matching half operands
and a half result. The existing exact evaluator combines product and addend
before one nearest rounding with ties to even. Signed zeros, subnormals,
infinities, positive canonical NaNs and poison/undef/freezes retain existing
rules. Key 2200 appends one identity without moving earlier AIR/LLVM scalar or
vector keys. The scalar cache has 2,201 entries; vector entries remain 62,228.

The shared FMA helper now masks unused upper bits when a zero product returns
the finite nonzero addend. This fixes direct evaluator calls carrying high bits
while preserving existing normalized executor results. Checks cover half and
float32 addend masking and all binary16 encodings in three exact FMA identities.

`tests/ios/air-native-half-fma.v` passes under ASan/UBSan with LLVM 23.1.5
on arm64 Darwin:

- 1,227,648 native typed/loaded memory cases run through direct and prepared
  execution, including shifted views and complete output padding, plus 613,824
  scalar results. Single AIR calls, AIR-to-LLVM chains and repeated AIR calls
  cover every binary16 encoding in each operand position with deterministic
  peers, plus every triple of twenty boundaries. This includes 24,000 boundary
  triples across the three modes. Native arithmetic NaNs are normalized to the
  established software positive canonical NaN policy.
- Twenty-one poison/undef/freeze/discard checks, six ordered poison/undef stores,
  six memory freeze/lazy repairs, 65 metadata/type/profile refusals, nine short
  budgets and twelve signature/overload/address guards pass. All three operand
  types are checked even after cached calls. Twenty-four native loops run through
  257 visits with exact budgets and one-fewer-step refusals.
- Forty-eight checks in four host rounding environments match captured native
  nearest-mode results and preserve the caller's rounding mode. Six native
  controls distinguish fused from separately rounded multiply/add. Five controls
  reject corrupt scalar values, kind, width, poison and step counts.
- Another 1,024 native comparisons mix half/float32 AIR FMA with earlier half
  absolute-value and rint calls, checking declaration-cache coexistence.

Saved native disassembly has six reference functions, seven half and one float32
LLVM FMA calls, and half fabs/rint calls. A separate reference contains one half
multiply and add. No native reference calls AIR or the software evaluator.
Twenty-five unit groups pass, including 196,608 exact all-encoding FMA identity
and masking checks, fused cancellation/overflow/underflow controls, 2,097,152
vector identity lanes and 9,792 three-source vector state checks. The unchanged
float32 FMA checker again passes 98,304 native memory cases, 49,152 scalar
results and its full controls. The unchanged earlier half-math checker passes
786,432 native memory cases, 393,216 scalar results and its full controls.

A fresh software Metal host passes normal and deterministic sizes runs:
544 images, 773,740 checked invocations, 212 rejected pipelines and four
prewrite bounds failures. Sixteen new images check fused cancellation in both
signs, overflow rescue, a subnormal tie, signed zero, infinity times zero and
signaling NaN. Results match LLVM and explicit raw bits; five cases must differ
from separate multiply/add. Comparisons gate pixel data and results contribute
to the color. Complete RGBA8/readback/padding expectations, all previous
comparison rows and ten earlier AIR image kernel bodies remain unchanged.
Clipped groups, repeated dispatches and two drained runtimes per process pass.
The new shader has 82 static instructions, within the existing one-million-step
dispatch budget for 4,096 invocations.

Generated host C confirms cache sizes and no allocations on successful extended
float-name and FMA helper paths; error boxing remains. One cache entry adds
eight bytes. No owner, expression node or production resource limit was added.
Floating-dependent addresses and integer-only scalar calls retain their
exclusions. Other half AIR families and vectors remain excluded. Retained heap
was not measured; leak detection was disabled and native JIT instructions are
not sanitizer-instrumented. Fixtures are synthetic; Apple compiler emission
and native AIR/GPU comparisons were not run. Native GPU execution and new
Fortnite launch/frame evidence remain unverified. No kernel/guest build or
broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-half-fma-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-half-fma-20261117-r1.tar.gz`.

- Archive SHA-256: `42f106beb366f7cfb0f9bdee87b84e359a08849c2c9d56475a4eb04ef9b17bc6`.
- Typed inventory SHA-256: `37a0e24411ff27acaca1a171e3507ed7a80264dbb07e405bda1ee861d6514f87`.
- Source archive SHA-256: `0f115abe08a13aea1ca756f089bc2f89f7b5bbb31e7b4eefb2208cb1b52bcb47`.

Complete inventory and archive comparison passes for logical bytes, paths,
types, permissions and links, including root mode. Originals remain retained.
Source pins match the feature revision. Source, generated host C, IR/bitcode,
native disassembly, images, commands, binaries and sanitizer logs remain.
Toolchain libraries are referenced externally; the bundle is not hermetic.
No restoration replay or evidence deletion is claimed.
