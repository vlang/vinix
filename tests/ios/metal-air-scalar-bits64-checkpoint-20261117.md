# AIR scalar i64 bit operations checkpoint — 2026-11-17

Feature revision: `9112eb5231d553d8c0c0619d2bcd7384fc7926cb`.

Software Metal accepts scalar `air.popcount.i64` and `air.reverse_bits.i64`
with matching i64 input/results, reusing the existing bit evaluators and
pure checked address expressions. Keys 2179–2180 append after AIR float
identities. Earlier scalar and vector keys remain stable. Scalar cache
entries total 2,181; vector entries remain 62,228.

`tests/ios/air-native-scalar-bits64.v` passes under ASan/UBSan with LLVM
23.1.5 on arm64 Darwin:

- 131,072 native value/address comparisons cover both operations, a mixed
  chain and AIR/LLVM coexistence through direct/prepared execution. Loaded
  i64 value paths additionally match the native result and complete output
  padding; loaded scalar addresses retain their existing refusal.
- 65,536 scalar results also match independent standard-library bit counts
  and reversals. Inputs include all single-set/single-clear positions,
  zero, all ones, sign boundaries and deterministic full-width patterns.
- Thirteen poison/undef/freeze/discard checks, 33 profile/metadata/duplicate
  refusals and 12 short budgets pass. Twenty-four native loop comparisons
  run through 257 visits with exact budgets and one-fewer-step refusals.
  Another 256 checks combine i32/i64 AIR calls and an AIR float call in one
  function, verifying that their cache identities coexist.

Saved native disassembly contains nine reference functions and eighteen
LLVM i64 population-count/bit-reversal calls. Nineteen unit groups pass,
including exact names, appended scalar keys, old float identities, saturation,
zero counts, conversions, integer operations, vector cache identities and
multiply-high. The unchanged maintained i32 bit checker again passes its
131,072 native comparisons, 65,536 scalar checks and existing controls.

A fresh software Metal host passes normal and deterministic sizes runs:
480 images, 702,732 checked invocations, 212 rejected pipelines and four
prewrite bounds failures. Sixteen updated images compare scalar i64 calls
with LLVM and explicit formulas using a set top bit. A double scalar reversal
reconstructs the output coordinate; comparisons gate pixel data. Complete
RGBA8/readback/padding expectations, all prior comparison rows and six other
AIR image kernels remain unchanged. Clipped groups, repeated dispatches and
two drained runtimes per process pass.

The initial checker tried to prepare a scalar-load-dependent address, which
the existing expression builder excludes. Its failed bundle remains in
`reference/`; `reference-final/` passes with explicit refusal checks for that
boundary and loaded value checks on supported paths. No projection limit or
evaluator change was required. Other scalar AIR integer i64 families remain
excluded. Integer-only scalar execution retains its existing call exclusion.

Generated host C confirms cache sizes and no successful extended name/width
path allocations; error boxing remains. Two cache entries add 16 bytes. No
evaluator, owner or graph node kind was added. Retained heap was not measured;
leak detection was disabled and native JIT instructions are not sanitizer-
instrumented. Fixtures are synthetic; Apple compiler emission and native AIR/GPU
comparisons were not run. This extends CPU software Metal. Native GPU execution
and new Fortnite launch/frame evidence remain unverified. No kernel/guest build
or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-scalar-bits64-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-scalar-bits64-20261117-r1.tar.gz`.

- Archive SHA-256: `b7678e325e9842db7ce0cbfa3cceb859cb38a49e4272d1455ca6aee478bb0095`.
- Typed inventory SHA-256: `d5198c5f9263663d74ba71adf0e952bb75f2bd37a5e5fb334b4c85152a8f1a8f`.
- Source archive SHA-256: `e8ccfc1b2c1b3d5c6761879b1abdc98369b0c75c2b1764f114ca965c2aeca4d1`.

Complete inventory and archive comparison passes for logical bytes, paths,
types, permissions and links, including root mode. Originals remain retained.
Source pins match the feature revision. Source, generated host C, IR/bitcode,
native disassembly, images, commands, binaries and sanitizer logs remain.
Toolchain libraries are referenced externally; the bundle is not hermetic.
No restoration replay or evidence deletion is claimed.
