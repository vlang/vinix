# Scalar leading and trailing zero counts

The mixed scalar interpreter accepts `llvm.ctlz.iN` and `llvm.cttz.iN` for
every N from 1 through 64. Each takes an iN value and a constant i1 flag and
returns iN. `ctlz` counts leading zeros; `cttz` counts trailing zeros. Zero
input with a false flag returns N; with a true flag it produces poison.
Other inputs return exact counts. Incoming high bits are masked before testing
for zero. Poison input propagates and selected undef errors. The integer-only
API retains its existing no-call profile.

Production uses a bounded loop of at most N unsigned bit tests, with shifts
only in 0..N-1. It uses no host builtin, LLVM, FP or new allocation. Evaluation
returns a value/poison pair; untagged numeric evaluators explicitly reject these
operations so no poison payload is silently consumed. A CALL costs one executed
instruction and primitive CALL/return takes two.

The [existing direct-call profile](SCALAR-INTRINSICS.md) checks canonical names,
exact integer width/signature/arity, declaration identity, external linkage,
calling convention, default address space, explicit-type header and flag/attribute
policy. The second operand must resolve to a nonsplat integer/zero constant of
type i1, with raw value 0 or 1. Arguments, SSA results, declarations, opaque/
poison/undef constants and malformed types/values reject. Every call is checked,
including in dead blocks and after another call cached its declaration attributes.
Only `is.fpclass`, `ctlz`, `cttz` and integer `abs` admit parameter two's exact
enum `immarg`
attribute; other parameter/return/string/type attributes still reject. Valid
LLVM IR and matching immutable indexes remain preconditions.

The 1192-entry fixed stack cache reserves forty floating-overload slots and
eighteen separate 64-width integer ranges. `ctlz` and `cttz` use separate ranges;
their two flag values share a declaration identity, not a cached immediate.
The shared 1,000,000 attribute-work budget and fixed two-ID group storage remain.
The existing three owned execution arrays and cleanup are unchanged. Retained
allocation is not measured.

`scalar_zero_count_test.v` passes **1,310,712** standard-library comparisons
over both operations, every width and both flags (128 poison results), with
all i1..i16 inputs exhausted and 4,096 wide patterns. Explicit zero boundaries,
name/width/arity guards and rejection by untagged evaluators also pass.

`tests/ios/air-zero-count.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates and
LLVM-verifies 256 primitive functions, one per operation/width/flag combination.
Every narrow input is exhausted; wide inputs receive 4,096 mixed-bit patterns.
All overloads also receive zero/all-one/sign/alternating/byte patterns and every
single-set/single-clear bit, with high-bit noise. **1,329,400** exact value/tag
comparisons pass: 1,329,226 defined values and 174 poison results.

The reference wrapper computes the expected poison tag independently from the
input's zero test and constant flag. Before a native true-flag call on zero,
it substitutes one; defined zero cases still use actual zero. Native execution
never evaluates a poison-producing intrinsic. Poison result bits are ignored;
the tag, type, width and steps are checked. This avoids assuming that LLVM's
choice to refine poison to a value establishes an exact poison oracle.

Controls check 128 poisoned inputs, 128 undef rejections, 256 budget/integer-API
rejections, 256 mixed-flag results, 128 nonconstant flags after cached attributes,
fourteen metadata corruptions, twenty-four malformed flags, twelve result
corruptions (including lost poison tags), and two invalid flags in dead blocks.
LLVM/JIT/native code is not sanitizer-instrumented. The tool executes only its
own fixture; source/IR/bitcode, every comparison, binaries, identities and logs
are preserved in complete external bundles.

This is scalar execution groundwork. No AIR shader, Metal device, GPU command
or application launch is qualified.

References: [LLVM ctlz](https://llvm.org/docs/LangRef.html#llvm-ctlz-intrinsic),
[LLVM cttz](https://llvm.org/docs/LangRef.html#llvm-cttz-intrinsic),
[poison refinement](https://llvm.org/docs/LangRef.html#poison-values).
