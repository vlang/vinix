# Numeric binary32/integer conversions

The [mixed scalar interpreter](BINARY32.md) supports flag-free numeric
conversions between binary32 and every integer width i1..i64. Arguments/results
use the same raw-bit API and explicit poison state as other scalar instructions.

| Instruction | Behavior |
| --- | --- |
| `uitofp` | Mask to the source width, interpret unsigned, round to nearest/ties to even. |
| `sitofp` | Mask to the source width, interpret two's complement, round to nearest/ties to even. |
| `fptoui` | Truncate toward zero, then require the result to fit the unsigned destination. |
| `fptosi` | Truncate toward zero, then require the result to fit the signed destination. |

Float-to-integer NaNs, infinities and out-of-range results produce poison.
Range checks apply after truncation: unsigned `-0.999` becomes zero, and signed
i8 `-128.5` becomes -128. Signed i1 has the range -1..0. Signed zero and tiny
subnormals become integer zero. All i1..i64 integers fit a finite binary32 value,
though wide values can lose precision. For example, unsigned 16,777,217 rounds
to 16,777,216, and u64 maximum rounds to the exactly representable float 2^64.

`binary32_cast.v` uses unsigned magnitudes, exponent shifts and the existing
guard/round/sticky packer. No host numeric cast or floating-point environment
participates. Integer normalization takes at most 63 shifts; float normalization
is bounded by the binary32 format. There are no new execution arrays. Poison
operands propagate, selected undef errors, and nonzero conversion flags reject,
including `nneg`/fast-math flags. Precision conversions and saturating intrinsic
execution remain outside the interpreter. The integer-only API is unchanged.

`binary32_cast_test.v` checks 22 exact integer-to-float patterns, 34
float-to-integer patterns, invalid widths and 262,140 exhaustive exact signed/
unsigned i1..i16 round trips. Mixed-instruction tests check result kinds/widths,
range and operand poison, undef and flag rejection.

`tests/ios/air-binary32-casts.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
four bounded modules covering all 64 widths and four cast opcodes. Each of the
256 original functions executes in Vinix for 4,160 inputs: fixed edge/boundary
patterns and deterministic mixed-bit samples. High input bits check masking.
The tool compares 1,064,960 results, including 843,042 defined values and 221,918
poison tags. Results retain exact integer or float bits, kinds, widths and steps.

The independent native reference uses LLVM's ordinary integer-to-float casts,
which are defined for every input. For float-to-integer values it uses defined
`llvm.fptosi.sat.i64.f32`/`llvm.fptoui.sat.i64.f32` calls followed by truncation
to the destination width. It computes poison separately using `llvm.trunc.f32`,
exact power-of-two boundaries and NaN comparisons. This avoids converting
integer bounds to imprecise floats and preserves fractional values just outside
the destination range whose truncated result still fits. Vinix never calls
these intrinsics; they belong to the test reference only. The potentially
invalid ordinary native float-to-integer functions are never called.

Each batch rejects six corrupted results, including a lost poison tag (24 total).
Two integer-to-float controls retain RNE results under upward/downward host
rounding, with a distinguishing input for each mode. Native reference calls
occur only in the default environment. LLVM verifies the generated fixture;
IR, bitcode, assembly status, JIT/fenv identity and every comparison are retained
externally. LLVM/native machine code is not sanitizer-instrumented. The tool
can execute only its own generated fixture, never arbitrary AIR or an app.

These casts are shader groundwork; they do not create a Metal device or submit
GPU work. See [LLVM conversion semantics](https://llvm.org/docs/LangRef.html#conversion-operations)
and [saturating references](https://llvm.org/docs/LangRef.html#saturating-floating-point-to-integer-conversions).
