# AIR scalar i64 multiply-high checkpoint — 2026-11-17

Feature revision: `805dff33689fafe29c839c1900c3fd60800d3b8a`.

Software Metal accepts scalar `air.mul_hi.s.i64` and `air.mul_hi.u.i64`
with matching i64 operands/results. The existing signed/unsigned evaluators
return the upper 64 bits of the full product. Keys 2191–2192 append two
identities without moving earlier scalar/vector AIR/LLVM keys. The scalar
cache has 2,193 entries; vector entries remain 62,228. All fourteen admitted
scalar AIR i32 integer operations now have matching i64 forms.

`tests/ios/air-native-scalar-mul-hi64.v` passes under ASan/UBSan with LLVM
23.1.5 on arm64 Darwin:

- 131,072 native value/address comparisons check both operations and AIR/LLVM
  coexistence through direct and prepared memory execution, including full
  output padding and shifted views. The 65,536 scalar results also match an
  independent bit-column magnitude/product-negation oracle. Inputs include
  all pairs of sixteen boundaries, equal/complement pairs, sign and 32-bit
  boundaries and deterministic full-width patterns.
- Twenty-six poison/undef/freeze/discard checks, 26 profile/metadata/duplicate
  refusals and twelve short budgets pass. Forty-eight native loop comparisons
  run through 257 visits with exact budgets and one-fewer-step refusals.
- Another 512 checks combine i32/i64 AIR multiply-high with AIR population
  count, leading-zero count, unsigned saturation and float absolute value,
  checking coexistence with earlier scalar cache families.

Saved native disassembly contains ten reference functions and fourteen full
i128 products, followed by logical shifts by 64 and truncation to i64.
Operands use signed or unsigned extension; no reference body calls an intrinsic
or the software evaluator. Twenty-one unit groups pass, including 240,296
independent bit-column product checks across i1–i64, exhaustive i1–i8 pairs,
exact AIR names/keys/widths, floats, conversions, saturation, zero counts,
extrema and vector state. The unchanged maintained i32 multiply-high checker
again passes 131,072 native comparisons, 65,536 scalar checks and its existing
state/refusal/budget controls.

A fresh software Metal host passes normal and deterministic sizes runs:
496 images, 720,484 checked invocations, 212 rejected pipelines and four
prewrite bounds failures. Sixteen updated multiply-high images compare both
scalar i64 operations with LLVM and explicit formulas on positive and top-bit-
set inputs. The unsigned scalar high word reconstructs the actual store
coordinate; comparisons gate pixel data. Complete RGBA8/readback/padding
expectations, all previous comparison rows and seven other AIR image kernel
bodies remain unchanged. Clipped groups, repeated dispatches and two drained
runtimes per process pass. The updated shader has 160 static instructions,
within the existing one-million-step dispatch budget for 4,096 invocations.

Generated host C confirms cache sizes and no allocations on successful extended
name/width paths; error boxing remains. Two cache entries add sixteen bytes.
No evaluator, owner, expression node or production resource limit was added.
Scalar-load-dependent addresses and integer-only scalar calls retain their
exclusions. Other widths and spellings retain their exclusions. Retained heap
was not measured; leak detection was disabled and native JIT instructions are
not sanitizer-instrumented. Fixtures are synthetic; Apple compiler emission
and native AIR/GPU comparisons were not run. Native GPU execution and new
Fortnite launch/frame evidence remain unverified. No kernel/guest build or
broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-scalar-mul-hi64-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-scalar-mul-hi64-20261117-r1.tar.gz`.

- Archive SHA-256: `59d94cce75537212adc6f1b29255dd33a180779abb14b134cbec7c4dd22afe1c`.
- Typed inventory SHA-256: `7451fa76073b441818d095b1f8a50b93e9e8f86a809c7aa77dac72b257ddffad`.
- Source archive SHA-256: `a2d6c2fe2bc9a811891a3b3624cc34b0f37e32b45112639aa59bbb8a44954481`.

Complete inventory and archive comparison passes for logical bytes, paths,
types, permissions and links, including root mode. Originals remain retained.
Source pins match the feature revision. Source, generated host C, IR/bitcode,
native disassembly, images, commands, binaries and sanitizer logs remain.
Toolchain libraries are referenced externally; the bundle is not hermetic.
No restoration replay or evidence deletion is claimed.
