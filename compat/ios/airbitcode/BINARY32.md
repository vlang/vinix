# Software binary32 scalar execution

Build matching immutable decoded indexes as in [INTEGER.md](INTEGER.md), then:

```v
result := p.run_scalar_function(ir, stream, pools, bodies, function_index,
    argument_bits, step_limit)!
```

This mixed profile accepts i1..i64 and LLVM `float` (IEEE binary32). Arguments
are raw u64 bit patterns, masked to their declared widths. `IRScalarRun` reports
the return `kind` (`integer` or `binary32`), `bits`, raw `value`, `poison` and
`steps`. Do not consume `value` when poison is true. The existing integer entry
point keeps its integer-only profile and result type.

The function must be valid LLVM IR with ordinary calling convention, no
attribute set and no varargs. The profile adds flag-free `fadd`, `fsub`, `fmul`,
`fdiv`, `frem`, all sixteen `fcmp` predicates, `fneg`, bitcasts between i32 and float,
and [numeric i1..i64 conversions](BINARY32-CASTS.md).
Integer operations and control flow remain available. Select and simultaneous
PHIs can carry either kind. All instructions, including unvisited blocks, must
belong to the supported profile. Floating-point fast-math flags reject.

`binary32.v` implements arithmetic using unsigned integer significands,
exponents and guard/round/sticky bits. It rounds to nearest, ties to even and
preserves subnormals with gradual underflow. Products fit in 48 bits; division
uses at most 51 numerator bits and a sticky remainder. Normalization loops are
bounded by the binary32 format. No host floating-point instruction, rounding
mode, exception flag, allocation or LLVM dependency participates in production
arithmetic. This implements the default LLVM floating-point environment.

`frem` follows LLVM's `fmod` semantics: truncate the mathematical quotient
toward zero and keep the dividend's sign, including for an exact zero. It reduces
normalized integer significands with at most 276 shift/subtract iterations,
then normalizes the exact, representable remainder. This handles quotients
that would overflow binary32 without ever computing a floating-point quotient.
Subnormal results remain exact. A finite dividend with an infinite divisor
returns the dividend; an infinite dividend or zero divisor produces the
preferred quiet NaN. Neither case produces poison.

Signed zero, infinities, underflow and overflow retain their IEEE results.
Floating division by zero produces infinity or NaN as appropriate; it does not
use host integer division on a zero divisor. Arithmetic NaNs choose the
preferred positive quiet NaN `0x7fc00000`, which LLVM permits. Copying, select,
PHIs and bitcasts preserve every NaN bit; `fneg` changes only the sign bit,
including for signaling NaNs. Comparisons classify quiet/signaling NaNs as
unordered. The constant `fcmp false`/`true` predicates return their constants
without reading operands. Other comparisons and arithmetic propagate poison;
selected undef and unsupported constant expressions still error. No undef or
freeze bit pattern is invented.

The mixed entry point shares the integer execution budget, switch comparison
charges and three owned temporary arrays. It borrows its inputs and frees those
arrays on success/error. Input validity, dominance and full CFG/PHI correctness
remain caller preconditions; this is not a general LLVM verifier.

Outside this profile: half/bfloat16/double, vectors,
precision conversions, fast/constrained operations,
function attributes, calls/intrinsics, pointers, memory and Metal commands.
These are explicit unsupported cases, not approximated operations.

`binary32_test.v` checks 34 exact rounding/special-value patterns, 30 exact
remainder patterns, 131,072 subnormal remainder comparisons against integer
modulo, and all sixteen predicates. `integer_exec_test.v` adds mixed
argument/constant/return checks, integer API isolation, exact signaling-NaN
negation, poison/undef, constant
predicates, flag rejection and budgets. Remainder integration also checks
both operand positions for poison, undef and constants, high argument bits,
result kinds/widths/steps, invalid-input NaN and signed zero.

`tests/ios/air-binary32-execute.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
30 portable functions plus native wrappers. Vinix interprets the original
float-argument functions; only LLVM's wrappers call them natively through their
real float ABI. Vinix does not execute the wrappers or a CALL instruction. The
tool compares 649,216 results, including a 32-by-32 edge corpus and deterministic
mixed-bit samples, branches, select, constants, bitcasts and float PHI swaps.
The 132,096 remainder comparisons include every pair of encoded exponents
with mixed significands and signs. For 5,641 arithmetic NaN results it checks
the NaN class and Vinix's exact preferred representation; native NaN
sign/payload equality is not qualified.
Every other result is compared bit for bit, including non-arithmetic NaNs.
Seven unsupported/undef guards, five poison results, lazy select and five
corrupted-result controls are checked separately. After native calls, software
execution is checked under upward/downward host rounding, using a distinguishing
tie input for each mode. Two extreme-quotient remainder checks also retain
their exact subnormal results in those modes. No reference call runs
under those altered modes. Original IR, bitcode, assembler status, JIT/fenv
identity and every comparison are saved externally. LLVM/native machine code
is not sanitizer-instrumented. The tool can execute only its generated fixture.

This is scalar shader groundwork. It does not execute an AIR shader, create a
Metal device, submit GPU work or qualify an iOS application launch.

References: [default LLVM environment](https://llvm.org/docs/LangRef.html#floating-point-environment),
[NaN behavior](https://llvm.org/docs/LangRef.html#behavior-of-floating-point-nan-values),
[floating-point semantics](https://llvm.org/docs/LangRef.html#floating-point-semantics)
and [comparisons](https://llvm.org/docs/LangRef.html#fcmp-instruction),
[floating remainder](https://llvm.org/docs/LangRef.html#frem-instruction).
