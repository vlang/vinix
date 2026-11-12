# Scalar fused multiply-add

The mixed scalar interpreter accepts direct ordinary `llvm.fma.f16` and
`llvm.fma.f32` declarations with three homogeneous arguments and a matching
result. It computes `a * b + c` exactly before one nearest/ties-to-even rounding.
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
declaration cache is now twenty-six fixed stack entries. Generated AArch64 C
confirms the two limb arrays and declaration cache use stack storage. This is
not a retained-allocation measurement.

NaN inputs, zero times infinity, or an infinite product plus an opposite-sign
infinity choose the existing preferred positive quiet NaN. Other infinities
retain the algebraic sign. Exact cancellation of nonzero terms gives positive zero;
two zero terms give negative zero only when both terms have negative sign.
Rounded underflow retains the exact sum's sign and gradual underflow. Both
overflow and underflow occur after the addition. Dynamic/constrained FP
environments, flags, errno, other precisions/vectors, AIR aliases and
`llvm.fmuladd` remain unsupported.

`scalar_fma_test.v` checks 58 exact patterns, including cancellation, signed
zeros, infinities/NaNs, overflow rescue, underflow ties and tiny perturbations
on both sides of a product midpoint. Six explicit controls distinguish fused
results from separate multiply/add operations. Name/width/arity guards pass.

`tests/ios/air-fma.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates eight
primitive/swapped/chain/four-iteration-loop functions across both precisions.
Each receives all 20-by-20-by-20 boundary triples. Half sweeps place every
encoding in each of the three operand positions with mixed-bit peers. Float
cases receive 131,072 mixed-bit triples. Primitive/swapped functions take two
instructions, chains three and four-iteration PHI loops twenty-six.

The checker compares **1,505,792 native LLVM results**: **1,394,878 exact** and
**110,914 NaN-class cases**, checking Vinix's exact preferred representation
when the native result is NaN. It includes 131,072 cancellation triples using
the negative of a separately rounded native product as the addend. **130,784**
distinguish FMA from native separate multiply/add. Six poison, six undef, six
metadata (including third-operand types), five result-corruption and four
distinguishing host-rounding controls pass, with budget/integer isolation.
Native reference calls run only in the default environment. The tool executes
its own generated fixture; LLVM/JIT/native code is not sanitizer-instrumented.

This qualifies a scalar prerequisite, not AIR shader execution or Metal GPU
submission. See [LLVM FMA](https://llvm.org/docs/LangRef.html#llvm-fma-intrinsic).
