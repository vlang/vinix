# Software binary16 scalar execution

The [mixed scalar interpreter](BINARY32.md) accepts LLVM `half` values as
16-bit raw IEEE binary16 patterns. `IRScalarRun.kind` is `binary16` for a half
return, with `bits == 16`. Existing integer and binary32 enum values retain
their values. Incoming arguments are masked to the declared width.

The half profile supports:

- Flag-free `fadd`, `fsub`, `fmul`, `fdiv`, `frem` and all sixteen `fcmp` predicates.
- `fptrunc float ... to half`, rounding to nearest, ties to even.
- `fpext half ... to float`, exact for every finite half value.
- Bitcasts between half and i16, arguments, constants, return, select and PHIs.
- `fneg half`, which changes only the sign bit, including for signaling NaNs.
- [Signed/unsigned numeric conversions between half and i1..i64](BINARY16-INTEGER.md).
- [Selected scalar LLVM absolute-value, sign-copy and rounding intrinsics](SCALAR-INTRINSICS.md).

`binary16_cast.v` uses integer significands, exponent shifts and guard/round/
sticky bits. Narrowing preserves signed zero and gradual underflow; rounding
at the top of the finite range can produce signed infinity. Widening preserves
all finite values, signed zeros and infinities exactly. Precision-conversion
NaNs choose the preferred positive quiet NaN (`0x7e00` or `0x7fc00000`), which
LLVM allows. Copying, bitcasts, PHIs and select preserve all NaN bits, while
negation changes only their sign.

`binary16.v` performs arithmetic directly on half significands and exponents,
with a shared nearest/ties-to-even packer. Addition aligns guard/round/sticky
bits, multiplication has an exact product of at most 22 bits, and division
uses at most 25 numerator bits plus a sticky remainder. Remainder uses at most
39 shift/subtract exponent steps and returns an exact representable result
with the dividend's sign. Arithmetic never performs a rounded float operation
as an intermediate. Comparisons reuse integer-only binary32 classification
after exact widening; both NaN classes are unordered. Constant `fcmp false`
and `true` predicates do not read operands, including poison or undef.

Signed zero, infinities, gradual underflow and overflow retain their IEEE
results. Invalid arithmetic, including zero divided by zero, an infinite
dividend in `frem`, or a zero remainder divisor, returns the preferred quiet
NaN `0x7e00`. Other arithmetic and comparisons propagate operand poison.

Poison propagates, selected undef errors and fast-math flags reject. No host
FP instruction, environment, numeric cast, allocation or LLVM dependency
participates in production conversion. Normalization requires at most 23
shifts for float input and ten shifts for half input. The existing execution
arrays, their ownership and instruction/loop budgets are unchanged. Matching
immutable indexes and valid LLVM IR remain preconditions.

`bfloat16`, `double`, vectors, memory and other intrinsics reject, including in
unvisited blocks. The integer-only entry point
still rejects all floating-point types.

`binary16_cast_test.v` checks 14 exact widening patterns, 32 exact narrowing
patterns and round trips for all 65,536 half encodings. Conversion NaNs use
their documented preferred patterns. Mixed units check result kinds, widths,
steps, input masking, constants, poison, undef, exact signaling-NaN negation,
budgets, arithmetic/comparisons and unsupported flag/profile guards.
`binary16_test.v` checks 41 exact arithmetic patterns, all sixteen predicates
and 131,072 subnormal remainders against independent integer modulo.

`tests/ios/air-binary16-casts.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
twelve functions and native raw-bit ABI wrappers. Vinix interprets the original
functions, never the wrappers or a CALL instruction. It compares 1,167,424
results: each half/i16-input case covers all 65,536 encodings; each float-input
case covers 65,536 mixed-bit patterns, 32 fixed edges, and the midpoint plus
its immediate float neighbors for every positive/negative half rounding
boundary, including underflow, the subnormal/normal transition and overflow.

The test-only native LLVM midpoint generator widens adjacent half values,
adds them and divides by two, all exact in float; the overflow boundary uses
the hypothetical next finite value 65536. It does not call Vinix conversion
code. Reference functions execute natively only in the default FP environment.
All non-conversion results, including NaN bits, compare exactly. Conversion
NaNs check class and the exact preferred Vinix representation; native NaN
payload/sign equality is not qualified. The checker also verifies metadata,
eleven rejecting guards, three poison results, lazy select, five corrupted
results and two distinguishing host-rounding controls. Original IR/bitcode,
assembler/JIT/fenv identities and every comparison are saved externally.
LLVM/JIT native code is not sanitizer-instrumented. The tool can execute only
its generated fixture.

`tests/ios/air-binary16-execute.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
31 half functions plus native raw-bit ABI wrappers. It compares 2,587,648
results across arithmetic, every predicate, bitcasts, select, branch/PHIs,
parallel PHI swaps and accumulation loops that round each addition to half.
Each function receives a 32-by-32 edge corpus and every half encoding in
operand A paired with mixed-bit B; the eight arithmetic/flow functions also
receive 65,536 independent mixed-bit pairs. This is not exhaustive pair coverage.
The five primitive arithmetic functions require exactly two instructions.

The 62,180 arithmetic NaNs check native NaN class and Vinix's exact preferred
representation. Every other result compares bit for bit, including NaN bits
in non-arithmetic operations. Seven unsupported/undef guards, five poison
results, lazy select/constant predicates, five corrupted-result controls and
four host-rounding controls pass. Half addition uses a distinguishing tie for
each changed host mode; remainder retains an exact extreme-quotient result.
Native reference calls run only in the default environment. LLVM/JIT native
code is not sanitizer-instrumented. The tool runs only its generated fixture
and preserves every comparison, original IR/bitcode and target/fenv identity
outside Git. Retired unsupported-operation guards now check still-unsupported
dead precision operations and conversion/comparison flags.

These are scalar shader prerequisites. They do not create a Metal device,
execute an AIR shader, submit GPU work or qualify an iOS application launch.

References: [LLVM precision conversions](https://llvm.org/docs/LangRef.html#conversion-operations),
[NaN behavior](https://llvm.org/docs/LangRef.html#behavior-of-floating-point-nan-values),
[default environment](https://llvm.org/docs/LangRef.html#floating-point-environment).
