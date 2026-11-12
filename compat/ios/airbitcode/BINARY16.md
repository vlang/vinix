# Software binary16 precision conversions

The [mixed scalar interpreter](BINARY32.md) accepts LLVM `half` values as
16-bit raw IEEE binary16 patterns. `IRScalarRun.kind` is `binary16` for a half
return, with `bits == 16`. Existing integer and binary32 enum values retain
their values. Incoming arguments are masked to the declared width.

The half profile supports:

- `fptrunc float ... to half`, rounding to nearest, ties to even.
- `fpext half ... to float`, exact for every finite half value.
- Bitcasts between half and i16, arguments, constants, return, select and PHIs.
- `fneg half`, which changes only the sign bit, including for signaling NaNs.

`binary16_cast.v` uses integer significands, exponent shifts and guard/round/
sticky bits. Narrowing preserves signed zero and gradual underflow; rounding
at the top of the finite range can produce signed infinity. Widening preserves
all finite values, signed zeros and infinities exactly. Precision-conversion
NaNs choose the preferred positive quiet NaN (`0x7e00` or `0x7fc00000`), which
LLVM allows. Copying, bitcasts, PHIs and select preserve all NaN bits, while
negation changes only their sign.

Poison propagates, selected undef errors and fast-math flags reject. No host
FP instruction, environment, numeric cast, allocation or LLVM dependency
participates in production conversion. Normalization requires at most 23
shifts for float input and ten shifts for half input. The existing execution
arrays, their ownership and instruction/loop budgets are unchanged. Matching
immutable indexes and valid LLVM IR remain preconditions.

Half arithmetic, half comparisons (even constant true/false predicates),
half/integer numeric conversions, bfloat16, double, vectors, memory and
intrinsics reject, including in unvisited blocks. Half arithmetic is not
performed by promoting to float. The integer-only entry point still rejects
all floating-point types.

`binary16_cast_test.v` checks 14 exact widening patterns, 32 exact narrowing
patterns and round trips for all 65,536 half encodings. Conversion NaNs use
their documented preferred patterns. Mixed units check result kinds, widths,
steps, input masking, constants, poison, undef, exact signaling-NaN negation,
budgets and unsupported arithmetic/comparison/flag/profile guards.

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

These are scalar shader prerequisites. They do not create a Metal device,
execute an AIR shader, submit GPU work or qualify an iOS application launch.

References: [LLVM precision conversions](https://llvm.org/docs/LangRef.html#conversion-operations),
[NaN behavior](https://llvm.org/docs/LangRef.html#behavior-of-floating-point-nan-values),
[default environment](https://llvm.org/docs/LangRef.html#floating-point-environment).
