# Numeric binary16/integer conversions

The [mixed scalar interpreter](BINARY16.md) supports flag-free `uitofp`,
`sitofp`, `fptoui` and `fptosi` between half and every integer width i1..i64.
Arguments/results use raw bits and the existing explicit poison state.

| Instruction | Behavior |
| --- | --- |
| `uitofp` | Mask to the source width, interpret unsigned, round directly to half, nearest/ties to even. |
| `sitofp` | Mask to the source width, interpret two's complement, round directly to half, nearest/ties to even. |
| `fptoui` | Truncate toward zero, then require the result to fit the unsigned destination. |
| `fptosi` | Truncate toward zero, then require the result to fit the signed destination. |

Integer-to-half overflow produces signed infinity, not poison. Unsigned 65519
rounds to 65504, while 65520 rounds to infinity. Signed i1 has values -1 and 0.
Half-to-integer NaNs, infinities and out-of-range results produce poison.
Range checks follow truncation: unsigned negative fractions near zero become
zero, and signed i8 -128.5 becomes -128. Signed zero and subnormals become zero.

`binary16_from_integer` computes an unsigned magnitude, normalizes it with at
most 63 shifts, and retains eleven significand bits plus guard/round/sticky
bits for the half packer. It does not round through float. Half-to-integer uses
exact integer-only widening to binary32 and the existing truncation/range
checker. That widening preserves every finite value and the invalid-input
classification. There is no host numeric cast, FP environment, new allocation
or execution array. Poison operands propagate, selected undef errors, and
nonzero conversion flags (including `nneg` and fast-math) reject. The integer-only
API and execution budget/ownership contract remain unchanged. Valid LLVM IR
and matching immutable indexes remain preconditions.

`binary16_integer_test.v` checks 18 exact integer-to-half patterns, 27 exact
half-to-integer patterns, invalid widths and 8,188 exhaustive signed/unsigned
i1..i11 exact round trips. Mixed units check decoded signed/unsigned casts,
masking, kinds/widths/steps, fractional boundaries, overflow infinity,
poison/undef and flag/profile/budget guards.

`tests/ios/air-binary16-integer.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
four modules covering sixteen integer widths each. Each of the 128 original
half-to-integer functions executes for all 65,536 half encodings. Each of the
128 integer-to-half functions executes for 8,256 inputs: width/sign limits,
rounding ties, overflow neighbors, mixed small magnitudes/signs and wide bit
patterns. High incoming bits check masking. This is exhaustive half-input
coverage at every width and signedness, not exhaustive wide integer coverage.

The native reference uses LLVM's ordinary integer-to-half casts, which remain
defined even when the result overflows to infinity. Half-to-integer values
use exact native widening to float followed by defined saturating i64
intrinsics and destination masking. An independent poison reference truncates
in float first, then checks NaNs and exact power-of-two bounds up to 2^64.
No potentially invalid ordinary native half-to-integer function is called.
Vinix executes the original cast functions, never the reference wrappers,
intrinsics or CALL instructions.

All 9,445,376 comparisons pass: 7,735,300 defined results and 1,710,076 poison
tags. The checker compares exact bits, kinds, widths, poison and two executed
instructions. Each batch rejects six corrupted results, including lost poison
(24 total). Two distinguishing integer-to-half controls retain RNE under upward/
downward host rounding. Native reference calls use only the default environment.
LLVM/JIT/native code is not sanitizer-instrumented. Original IR/bitcode,
assembler/JIT/fenv identities and every comparison are saved outside Git.
The tool executes only its generated fixture.

Saturating intrinsics remain test-only references. These casts do not execute
an AIR shader, create a Metal device, submit GPU work or qualify an iOS launch.

References: [LLVM conversion semantics](https://llvm.org/docs/LangRef.html#conversion-operations),
[default environment](https://llvm.org/docs/LangRef.html#floating-point-environment),
[saturating references](https://llvm.org/docs/LangRef.html#saturating-floating-point-to-integer-conversions).
