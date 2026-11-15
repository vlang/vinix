# Scalar power-of-two scaling

The mixed scalar interpreter accepts `llvm.ldexp.f16.i32(half, i32)` and
`llvm.ldexp.f32.i32(float, i32)`, returning the input floating type. The second
argument is a signed i32 exponent: multiply the first argument by `2^exponent`.
Unlike the other admitted math calls, this signature mixes float and integer
arguments. Admission verifies the exact names, floating precision, i32 width,
declared/operand type identity and the existing strict [call profile](SCALAR-INTRINSICS.md).
Other integer exponent widths, precisions and AIR aliases reject. Fixed-vector
calls use the separate profile below.

Evaluation normalizes the integer significand, adjusts the unbiased exponent,
then uses the existing packer for one nearest/ties-to-even rounding. Gradual
underflow supports exact subnormals and halfway ties; rounded zero retains the
input sign. Overflow returns signed infinity. Both zero signs and infinities
remain unchanged for every exponent; NaNs choose the existing preferred
positive quiet representation under LLVM's usual math NaN rules.

Exponents outside -512..512 have a known overflow/rounded-zero result for every
nonzero finite half/float. Checking that bound before exponent addition handles
INT_MIN/MAX without overflow or exponent-dependent loops. Within the bound,
normalization takes at most 23 shifts and packing uses bounded shift/jam logic.
There is no host FP, libm, LLVM dependency or allocation in evaluation.

Poison in either operand propagates, even for special floating values; selected
undef errors. Each intrinsic CALL costs one instruction. The declaration cache
is thirty-four fixed stack entries; existing three owned execution arrays and
cleanup remain unchanged. The integer-only API rejects these floating calls.
Fast-math, constrained/dynamic FP environments, exception flags, errno and
general calls remain outside this profile. Valid LLVM IR and matching immutable
indexes are preconditions; admission is not a full verifier.

`scalar_ldexp_test.v` checks 48 exact values across both precisions: signs,
subnormal normalization, underflow ties, zero/infinity/NaN, INT_MIN/MAX and i32
masking, plus name/arity guards.

The maintained `tests/ios/air-scalar-intrinsics.v` checker now generates 40
functions. The two new scaling wrappers truncate their i64 input to i32, call
the intrinsic and return, with exact three-step accounting. In addition to the
usual exhaustive half and mixed-bit/midpoint float coverage, it checks every
half encoding and 65,536 float patterns against sixteen signed exponent values
covering boundaries and INT_MIN/MAX: 2,097,152 scaling boundary pairs.

The complete suite compares 14,619,264 results: 13,161,614 exact and 1,457,650
NaN-class cases, checking Vinix's exact preferred representation for native
math NaNs. Eight new poison/undef controls, two exponent-type corruptions and
four distinguishing host-rounding controls pass. The latter scale one or three
minimum subnormals down one bit, distinguishing nearest mode from upward or
downward rounding. Existing guard/corruption controls remain; all native
references run only in the default environment. The prior half copysign integer
oracle remains documented separately. LLVM/JIT/native code is not sanitizer-
instrumented. This does not execute an AIR shader or submit Metal GPU work.

## Fixed vectors

The mixed, void and memory interpreters accept unflagged
`llvm.ldexp.vNf16.vNi32` and `llvm.ldexp.vNf32.vNi32`, for N=1..16.
The first operand and result have the same floating type; the second operand
must be an i32 vector with the same count. Actual declaration and source types
are checked independently of the overload name. Each lane uses the scalar
evaluator above. Either source's poison propagates locally; any undef source
lane rejects even when the result is discarded. Source freezes repair lanes,
and results retain independent snapshots. Calls cost one step, three lane
counts of validation work and one shared construction slot. Thirty-two new
declaration identities extend the vector cache to 608 entries.

`tests/ios/air-vector-ldexp.v` checks all counts and both formats, exact values,
states, changing-exponent loops, malformed signatures and shared limits.
Its native reference uses scalar calls for N=1 because the captured LLVM
AArch64 backend crashes legalizing that vector form; N=2..16 use vector calls.
Vector arguments/returns, PHIs, loads/stores, scalable vectors, other exponent
widths, fast-math and strict FP remain unsupported.

References: [LLVM ldexp](https://llvm.org/docs/LangRef.html#llvm-ldexp-intrinsic),
[LLVM math NaN rules](https://llvm.org/docs/LangRef.html#behavior-of-floating-point-operations).
