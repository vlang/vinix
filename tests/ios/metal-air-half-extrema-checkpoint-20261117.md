# AIR scalar half extrema checkpoint — 2026-11-17

Feature revision: `bde4734b40cf5437539380f3d7aaab1dea667ff5`.

Software Metal accepts binary `air.fmin.f16` and `air.fmax.f16` with matching
half operands/results. They prefer a number to a NaN, preserve the first
operand on numeric ties (including opposite signed zeros), and normalize two
NaNs to positive canonical 0x7e00. Subnormal numbers retain their bits.
The shared AIR wrapper now accepts binary16 and masks unused upper bits,
reusing the existing number evaluator outside zero ties. Keys 2201..2202
append two identities without moving earlier AIR/LLVM scalar or vector keys.
The scalar cache has 2,203 entries; vector entries remain 62,228.

`tests/ios/air-native-half-extrema.v` passes under ASan/UBSan with LLVM 23.1.5
on arm64 Darwin:

- 1,579,776 native typed/loaded memory cases run through direct and prepared
  execution, including shifted views and complete output padding, plus 789,888
  scalar results. Six modes cover single min/max calls, AIR-to-LLVM chains and
  opposite AIR extrema chains. Every binary16 encoding appears in each operand
  position with equal, complementary and deterministic peers, plus 3,456 boundary
  pairs across the six modes. This does not exhaust every possible operand pair.
  There are 6,768 canonical NaN results; native NaNs are normalized to the
  established software policy.
- Twenty-eight poison/undef/freeze/discard checks, eight ordered poison/undef
  stores, eight memory freeze/lazy repairs, 120 metadata/type/profile refusals,
  eighteen short budgets and eighteen signature/overload/address guards pass.
  Both operand types remain checked after cached calls. Forty-eight native
  loops run through 257 visits with exact budgets and one-fewer-step refusals.
- 768 checks in four host rounding environments match captured native results
  and preserve the caller's rounding mode. Five controls reject corrupt scalar
  values, kind, width, poison and step counts.
- Another 1,024 native comparisons mix half/float32 AIR extrema and earlier half
  FMA calls, checking declaration-cache coexistence.

Saved native disassembly has nine reference functions, fourteen half LLVM
number-extrema calls, one half FMA call and two float32 number-extrema calls.
Fourteen explicit first-zero selections adapt the AIR references while LLVM
chains retain LLVM zero ordering. No native reference calls AIR or the software
evaluator. Twenty-five unit groups pass, including 6,291,456 independent ordered-key
comparisons covering every binary16 encoding, twenty-four boundary peers and both
operand orders, with unused high bits set. The earlier 262,144 float32 extrema
comparisons pass. The unchanged float32 extrema checker passes 98,304 native
memory cases, 49,152 scalar results and its full controls. The unchanged earlier
half-FMA checker passes 1,227,648 native memory cases, 613,824 scalar results and
its full controls.

A fresh software Metal host passes normal and deterministic sizes runs:
560 images, 791,492 checked invocations, 212 rejected pipelines and four
prewrite bounds failures. Sixteen new images check opposite signed zeros in
both orders, a NaN in either position, opposite finite signs, smallest signed
subnormals, opposite infinities and two NaNs (including a signaling encoding).
Four AIR calls cover both operations and operand orders; two LLVM calls check
their separate zero ordering. Explicit raw-bit comparisons gate pixel data,
and all four AIR results contribute to the color. Complete RGBA8/readback/padding
expectations, all previous comparison rows and eleven earlier image kernel
bodies remain unchanged. Clipped groups, repeated dispatches and two drained
runtimes per process pass. The new shader has 120 static instructions, within
the existing one-million-step dispatch budget for 4,096 invocations.

Generated host C confirms cache sizes and no allocations on successful extended
float-name and AIR extrema wrapper paths; error boxing remains. Two cache entries
add sixteen bytes. No owner, expression node or production resource limit was
added. Floating-dependent addresses and integer-only scalar calls retain their
exclusions. Half AIR clamp, vector extrema and fast overloads remain excluded.
Retained heap was not measured; leak detection was disabled and native JIT
instructions are not sanitizer-instrumented. Fixtures are synthetic; Apple
compiler emission and native AIR/GPU comparisons were not run. The software
treats signaling NaNs as quiet for numeric preference under its established
policy. Native GPU execution and new Fortnite launch/frame evidence remain
unverified. No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-half-extrema-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-half-extrema-20261117-r1.tar.gz`.

- Archive SHA-256: `67d4f50c7eebe1909f25a9e7774d8ab52271078c6e164e19c99bd26a6c19f29f`.
- Typed inventory SHA-256: `4426dfe2d1f7c770c0a32afc65d80f9849d08b156f0dc6cfe9908861470711ac`.
- Source archive SHA-256: `3c76432a78d9f63c62e046226afff624defa2e1ac3a262ad3ecee2c0e70e771c`.

Complete inventory and archive comparison passes for logical bytes, paths,
types, permissions and links, including root mode. Originals remain retained.
Source pins match the feature revision. Source, generated host C, IR/bitcode,
native disassembly, images, commands, binaries and sanitizer logs remain.
Toolchain libraries are referenced externally; the bundle is not hermetic.
No restoration replay or evidence deletion is claimed.
