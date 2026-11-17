# AIR scalar half clamp checkpoint — 2026-11-17

Feature revision: `d1ac76397135d172d93a2d425595bd393156d191`.

Software Metal accepts ternary `air.clamp.f16` with matching half operands and
result. It composes AIR fmin(fmax(x, low), high), preserving numeric NaN preference
and first-operand signed-zero ties. Ordered low > high produces poison; NaN
bounds do not trigger this comparison. All-NaN results use positive canonical
0x7e00. The shared clamp helper selects the existing binary16 comparison and
extrema evaluators. Key 2203 appends one identity without moving earlier keys;
the scalar cache has 2,204 entries and vector entries remain 62,228.

`tests/ios/air-native-half-clamp.v` passes under ASan/UBSan with LLVM 23.1.5
on arm64 Darwin:

- 1,227,648 typed/loaded memory cases run through direct and prepared execution,
  with shifted views and complete output padding. There are 613,824 scalar
  cases: 352,974 defined native values, 260,850 domain poison results and 300
  canonical NaNs. Three modes cover a single clamp, repeated clamp and AIR
  extrema-to-clamp composition. Every binary16 encoding appears in each of the
  three operand positions with deterministic peers, plus 24,000 boundary triples
  across the modes. This does not exhaust the complete operand triple space.
- Twenty-one state/discard checks, six ordered poison/undef stores, six memory
  repairs, 75 metadata/type/profile refusals, nine short budgets and twelve
  signature/overload/address guards pass. All operand types remain checked after
  cached calls. Twenty-four native loops run through 257 visits with exact
  budgets and one-fewer-step refusals. Forty-eight checks in four host rounding
  environments preserve the caller's mode and match captured nearest-mode values.
- Six controls reject corrupt scalar value, kind, width, poison and step counts,
  including lost domain poison. Seven domain controls cover observing, freezing,
  lazily bypassing, discarding and storing invalid-bound results, retaining earlier
  stores on an observed poison failure.

Saved native disassembly has four reference functions and twelve half LLVM
number-extrema calls with twelve explicit AIR first-zero selections. Three
ordered comparisons classify invalid bounds before the defined composition;
the references do not execute undefined native clamp operations or call AIR
or the software evaluator. Twenty-five unit groups pass, including 204,608
independent ordered-key domain/composition checks (86,950 poison), all half
encodings in every operand position, 8,000 boundary triples, all signed-zero
combinations and unused-upper-bit masking. The earlier float32 clamp checker
passes 98,304 memory and 49,152 scalar cases with its full controls. The unchanged
half-extrema checker passes 1,579,776 memory and 789,888 scalar comparisons,
its controls and 1,024 mixed half/float32 extrema/FMA cache comparisons.

A fresh software Metal host passes normal and deterministic sizes runs:
576 images, 809,244 checked invocations, 212 rejected pipelines and four
prewrite bounds failures. Sixteen new images cover opposite signed zeros, NaN
input and bounds, subnormals, infinities and all-NaN triples (including a signaling
encoding). Raw expected bits and AIR extrema composition gate the pixel result;
the clamp bits contribute to the color. Invalid bounds are frozen and bypassed
by lazy select. A float32 clamp with equal bounds verifies mixed-width cache
coexistence after exact half-to-float-to-half conversion. Complete RGBA8 readback,
padding, prior comparison rows and twelve earlier image kernel bodies pass.
Clipped groups, repeated dispatches and two drained runtimes per process pass.
The new shader has 91 static instructions, within the existing one-million-step budget
for 4,096 invocations.

The first image attempt failed because its mixed-width fixture incorrectly
expected NaN clamp with numeric infinity bounds to preserve NaN. Equal bounds
correct that identity check. The failed run and its generated source remain
under `software/`; the passing fresh build and both executions are under
`software-repaired/`.

Generated host C confirms cache sizes and no allocations on successful extended
float-name and clamp wrapper paths; error boxing remains. One cache entry adds
eight bytes. No owner, expression node or production resource limit was added.
Half AIR vectors, fast overloads, integer-only scalar calls and floating-dependent
addresses retain their exclusions. Retained heap was not measured; leak detection
was disabled and native JIT instructions are not sanitizer-instrumented. Fixtures
are synthetic; Apple compiler emission and native AIR/GPU comparisons were not
run. Signaling NaNs follow the established software numeric-preference policy.
Native GPU execution and new Fortnite launch/frame evidence remain unverified.
No kernel/guest build or broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-half-clamp-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-half-clamp-20261117-r1.tar.gz`.

- Archive SHA-256: `a6004bd4693f7530584db50b04acbdb6440e93ec62df253a3b0789178ca35da0`.
- Typed inventory SHA-256: `66bf9360f1a54b304762d2f993ff1d06f1086082c6c9fbc226d816b5c0a69334`.
- Source archive SHA-256: `ea2173c55eb849e092eefb3a896d882a7611f438da31b005e3e91443da0b1768`.

Complete inventory and archive comparison passes for logical bytes, paths,
types, permissions and links, including root mode. Originals remain retained.
Source pins match the feature revision. Source, generated host C, IR/bitcode,
native disassembly, images, commands, binaries and sanitizer logs remain.
Toolchain libraries are referenced externally; the bundle is not hermetic.
No restoration replay or evidence deletion is claimed.
