# Scalar fused multiply-add

The mixed scalar interpreter accepts direct ordinary `llvm.fma.f16` and
`llvm.fma.f32` declarations with three homogeneous arguments and a matching
result. It computes `a * b + c` exactly before one nearest/ties-to-even rounding.
It also accepts `llvm.fmuladd.f16/f32`, whose contract permits fused or separate
rounding. The interpreter consistently chooses the fused result using this same
implementation; it does not promise to reproduce another backend's choice.
The existing [intrinsic admission rules](SCALAR-INTRINSICS.md) apply, including
strict declaration identity, signatures, attributes and rejection of fast-math
flags. Each CALL costs one instruction. Selected undef errors; poison in any
of the three operands propagates. The integer-only API rejects FMA.

`scalar_fma.v` decodes finite values as unsigned coefficients times powers of
two. Binary32 coefficients have at most 24 bits, with powers -149 through 104.
An exact product lies on a `2^-298` grid, occupying at most bits 0..553; the
addend occupies bits 149..425. Two nine-limb `u64` fixed stack arrays hold their
magnitudes. Half values fit on the same grid. Addition or magnitude subtraction
runs through at most nine limbs. Locating the highest bit takes at most nine
limb checks and 63 shifts. Only then is the exact result reduced to the packer's
three extra bits and sticky information, with one final target-precision round.
There is no intermediate product overflow, underflow or rounding.

All evaluation uses integer operations. There is no host FP instruction,
libm, LLVM dependency, allocation or native function invocation in production.
The existing three owned execution arrays and cleanup remain unchanged; the
declaration cache is now thirty-four fixed stack entries. Generated AArch64 C
confirms the two limb arrays and declaration cache use stack storage. This is
not a retained-allocation measurement.

NaN inputs, zero times infinity, or an infinite product plus an opposite-sign
infinity choose the existing preferred positive quiet NaN. Other infinities
retain the algebraic sign. Exact cancellation of nonzero terms gives positive zero;
two zero terms give negative zero only when both terms have negative sign.
Rounded underflow retains the exact sum's sign and gradual underflow. Both
overflow and underflow occur after the addition. Dynamic/constrained FP
environments, flags, errno, other precisions/vectors and AIR aliases remain unsupported.

`scalar_fma_test.v` checks 58 exact patterns, including cancellation, signed
zeros, infinities/NaNs, overflow rescue, underflow ties and tiny perturbations
on both sides of a product midpoint. Six explicit controls distinguish fused
results from separate multiply/add operations. Name/width/arity guards pass.

`tests/ios/air-fma.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates eight
primitive/swapped/chain/four-iteration-loop functions across both precisions,
plus two `fmuladd` primitives (ten functions in total).
Each receives all 20-by-20-by-20 boundary triples. Half sweeps place every
encoding in each of the three operand positions with mixed-bit peers. Float
cases receive 131,072 mixed-bit triples. Primitive/swapped functions take two
instructions, chains three and four-iteration PHI loops twenty-six.

The checker compares **1,980,544 fused-oracle results**: **1,842,062 exact** and
**138,482 NaN-class cases**, checking Vinix's exact preferred representation
when the native result is NaN. It includes 131,072 cancellation triples using
the negative of a separately rounded native product as the addend for each
operation (262,144 total). **261,568** distinguish fusion from separate multiply/add.
Twelve poison, twelve undef, six
metadata (including third-operand types), five result-corruption and eight
distinguishing host-rounding controls pass, with budget/integer isolation.
Native reference calls run only in the default environment. The tool executes
its own generated fixture; LLVM/JIT/native code is not sanitizer-instrumented.

For `fmuladd`, the value oracle deliberately calls native LLVM `fma` to qualify
the interpreter's chosen refinement. Separately, `native-optional.tsv` records
474,752 actual native `fmuladd` outcomes and verifies each matches the native
fused or separate result (NaNs compare by class). These backend choices do not
relax the production comparison against the fused oracle.

This qualifies a scalar prerequisite, not AIR shader execution or Metal GPU
submission. See [LLVM FMA](https://llvm.org/docs/LangRef.html#llvm-fma-intrinsic).
The [fmuladd contract](https://llvm.org/docs/LangRef.html#llvm-fmuladd-intrinsic)
explicitly permits rounding either once or between multiplication and addition.
