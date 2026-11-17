# AIR scalar i64 zero-count checkpoint — 2026-11-17

Feature revision: `da2b0c736d97abdd9c0758d2102242694c27d1bf`.

Software Metal accepts scalar `air.clz.i64` and `air.ctz.i64` with matching
i64 input/results and a constant-false i1 flag. Zero returns 64. The existing
zero-count evaluators, state rules and pure checked address expressions are
reused. Keys 2185–2186 append two identities; earlier AIR/LLVM/scalar/vector
keys remain stable. The scalar cache has 2,187 entries; vector entries remain
62,228. True, runtime, instruction-valued, undef and poison scalar AIR flags
retain their refusal, including after a declaration cache hit. LLVM's separate
true/poison form and AIR vector flag policy retain their rules.

`tests/ios/air-native-scalar-zero-count64.v` passes under ASan/UBSan with
LLVM 23.1.5 on arm64 Darwin:

- 131,072 native value/address comparisons check both operations and AIR/LLVM
  coexistence through direct and prepared memory execution, including full
  output padding and shifted views. The 65,536 scalar results also match
  standard-library zero counts. Inputs cover zero, all ones, every single-set
  and single-clear bit, and deterministic full-width patterns.
- Eighteen poison/undef/freeze/discard/LLVM-zero checks, 42 profile/metadata/
  flag/duplicate refusals, twelve short budgets and two canonical immarg
  declarations pass. Forty-eight native loop comparisons run through 257
  visits with exact budgets and one-fewer-step refusals.
- Another 512 checks pack i32/i64 leading/trailing counts into separate fields
  and combine AIR population count, signed min and float absolute value,
  checking coexistence with previous scalar cache families.

Saved native disassembly contains ten reference functions with fourteen LLVM
i64 zero-count calls. Twenty-one unit groups pass, including 1,310,712
standard-library zero-count comparisons across all i1–i64 widths and both
LLVM flags (128 poison cases), exact AIR names/keys/widths, floats,
conversions, saturation, extrema, vector state and multiply-high. The unchanged
maintained i32 zero-count checker again passes 131,072 native comparisons,
65,536 scalar checks and its existing refusal/budget controls.

A fresh software Metal host passes normal and deterministic sizes runs:
496 images, 720,484 checked invocations, 212 rejected pipelines and four
prewrite bounds failures. Sixteen new dedicated images compare i64 AIR calls
with LLVM and explicit counts on all 64 single-bit positions and mixed
zero/nonzero inputs. Trailing-zero counts reconstruct the actual store
coordinate; comparison results gate pixel data. Complete RGBA8/readback/padding
expectations and all previous comparison rows pass. Seven previous AIR image
kernel bodies remain unchanged. Clipped groups, repeated dispatches and two
drained runtimes per process pass.

The initial expanded geometry shader exceeded the existing dispatch instruction
budget at 64×64. The final fixture adds a small dedicated kernel and preserves
the one-million-step limit. A second attempt retained the old valid/rejected
pipeline partition endpoint; updating it for the added kernel restores the
intended partition. Failed sources/generated C, binaries and logs remain under
`software/` and `software-final/`; `software-qualified/` contains passing runs.

Generated host C confirms cache sizes and no allocations on successful extended
name/width paths; error boxing remains. Two cache entries add sixteen bytes.
No evaluator, owner, expression node or production resource limit was added.
Scalar-load-dependent addresses and integer-only scalar calls retain their
exclusions. Other scalar AIR i64 integer families remain excluded. Retained
heap was not measured; leak detection was disabled and native JIT instructions
are not sanitizer-instrumented. Fixtures are synthetic; Apple compiler emission
and native AIR/GPU comparisons were not run. Native GPU execution and new
Fortnite launch/frame evidence remain unverified. No kernel/guest build or
broader SIMD/indirect suite was repeated.

Evidence: `/Users/alex/Library/Caches/vinix-ios/air-scalar-zero-count64-20261117-r1`.

Complete archive: `/Users/alex/Library/Caches/vinix-ios/air-scalar-zero-count64-20261117-r1.tar.gz`.

- Archive SHA-256: `386be08a7f4c4f289276705e709aa76e3ec36d7c7e98c35b7e05e68cc64421af`.
- Typed inventory SHA-256: `6aad072190f9f0a5b4cd2c5c55d815b58fa9300f3e7604d2defb01b28d45efe6`.
- Source archive SHA-256: `3511eebe7cd5209d6668f1321c783bf66a1dedca4dff02f6a024e49659d4e128`.

Complete inventory and archive comparison passes for logical bytes, paths,
types, permissions and links, including root mode. Originals remain retained.
Source pins match the feature revision. Source, generated host C, IR/bitcode,
native disassembly, images, commands, binaries and sanitizer logs remain.
Toolchain libraries are referenced externally; the bundle is not hermetic.
No restoration replay or evidence deletion is claimed.
