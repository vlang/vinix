# Scalar signed and unsigned saturating left shifts

The mixed scalar interpreter accepts `llvm.sshl.sat.iN` and `llvm.ushl.sat.iN`
for every N from 1 through 64. Both take an iN value and an iN shift amount,
returning iN. The amount is a width-truncated unsigned integer. An amount
greater than or equal to N produces poison, including when the input value is
zero. Other shifts multiply by a power of two and clamp to the signed bounds
or unsigned maximum. Shift zero preserves all input bits, including i1 and
INT64_MIN. Poison in either input propagates; selected undef errors. The
integer-only API retains its no-call profile. CALL/return takes two instructions.

Production rejects overshifts before every host shift. Unsigned evaluation
compares the input against a shifted unsigned limit before shifting. Signed
evaluation uses unsigned magnitude and a sign-dependent limit, returning the
appropriate bound if necessary. Unsigned negation reconstructs negative bits,
including INT64_MIN. No host signed arithmetic, host builtin, LLVM, FP or new
allocation participates in valid numerical evaluation. Untagged and unary
integer evaluators reject these operations.

The [direct-call profile](SCALAR-INTRINSICS.md) checks canonical names, exact
widths, homogeneous fixed signatures, external declaration identity, ordinary
calling convention, default pointer address space and explicit-type header.
Fast-math/tail flags and call-site attributes reject. Harmless function-level
declaration attributes retain their whitelist. Parameter/return attributes,
including `immarg`, reject for these operations. Dynamic shift amounts are
supported. Vectors, wider integers, malformed suffixes and AIR aliases reject.
All blocks are preflighted. Valid LLVM IR and matching immutable indexes remain
preconditions.

The fixed stack cache has 1320 entries: forty floating-overload slots and
twenty independent 64-width integer ranges. The two shift families use
separate ranges. The shared 1,000,000-work attribute limit, fixed two-ID
attribute storage and three existing owned execution arrays/cleanup remain.
Retained allocation is not measured.

`scalar_saturating_shift_test.v` passes **651,944** independent checked-doubling
comparisons, including **206,750 poison results** and **18,432 value/amount edge
pairs**. Every i1..i8 input pair is exhausted. Wider widths receive 4,096 mixed
values with amounts cycling through 0..N+1, plus a twelve-by-twelve boundary
matrix. It covers signed minima/maxima, neighbors, unsigned maxima/zero, byte
patterns and amounts `0`, `1`, `N-1`, `N`, `N+1`, the maximum iN value, `2`,
`N/2`, `31`, `32`, `63` and `64`, truncated to iN.
The reference repeatedly doubles a value after checking safe arithmetic margins,
independently of production's shifted-limit algorithm. Zero identity, zero
overshift and strict name/width/arity/tagged-evaluator guards pass.

`tests/ios/air-saturating-shift.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
and LLVM-verifies 128 primitive functions. It compares **651,944 exact native
LLVM value/tag results**: **445,194 defined values and 206,750 poison tags**,
including the same **18,432 boundary pairs**. Wider value patterns differ from
the unit reference; high-bit noise on both arguments checks truncation. Native
value wrappers substitute a zero shift for an overshift before any native call.
Separate unsigned-comparison wrappers return the poison tags, preserving all
64 data bits. Poison payload bits are ignored.

Controls check 256 input-poison results, 256 undef rejections, 256 budget/
integer-API rejections, fourteen metadata corruptions, four type mismatches,
six name/width mismatches and fourteen result/tag corruptions. Another 512
mixed-family cache chains reconstruct the inputs' XOR using zero shifts in four
instructions. Another 128 chains propagate an overshift of zero through the
opposite shift family in three instructions. Only generated fixtures execute.
LLVM/JIT/native code is not sanitizer-instrumented. Complete IR/bitcode, every
comparison, binaries, identities and logs belong in external bundles.
`tests/ios/air-saturating-shift-regressions.v` runs the local pinned-toolchain
shared-profile checks; its header documents the environment and output children
must be fresh.

This is scalar execution groundwork. No AIR shader, Metal device, GPU command
or application launch is qualified.

Reference: [LLVM saturation semantics](https://llvm.org/docs/LangRef.html#saturation-arithmetic-intrinsics).
