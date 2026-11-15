# Scalar saturating integer addition and subtraction

The mixed scalar interpreter accepts `llvm.sadd.sat.iN`, `llvm.uadd.sat.iN`,
`llvm.ssub.sat.iN` and `llvm.usub.sat.iN` for every N from 1 through 64.
Each takes two iN arguments and returns iN. Signed results clamp to the signed
minimum/maximum; unsigned addition clamps to the unsigned maximum and unsigned
subtraction clamps to zero. Saturation produces a defined value. Poison in
either input propagates; selected undef errors. The integer-only API retains
its no-call profile for scalar intrinsic calls. Primitive CALL/return takes two
executed instructions.

Production masks both inputs and uses unsigned arithmetic throughout. Unsigned
operations check the available margin before addition/subtraction. Signed
operations compute a masked modular result and detect overflow from the input
and result sign bits, then choose the appropriate signed limit. This handles
i1 and INT64_MIN without host signed arithmetic or overflow. No host builtin,
LLVM, FP or new allocation participates in numerical evaluation. Unary integer
evaluators reject these binary operations.

[Saturating left shifts](SCALAR-SATURATING-SHIFT.md) use separate poison-aware
evaluation because a shift amount at least as large as the width produces poison.

The [direct-call profile](SCALAR-INTRINSICS.md) requires canonical reserved
names, exact integer widths, homogeneous fixed signatures, external declaration
identity, ordinary calling convention, default pointer address space and the
plain explicit-type header. Fast-math/tail flags and call-site attributes
reject. Harmless function-level declaration attributes retain their whitelist;
parameter/return attributes, including `immarg`, reject for these operations.
In the scalar profile, wider integers, malformed decimal suffixes and AIR
aliases reject.
All blocks are preflighted. Valid LLVM IR and matching immutable indexes
remain preconditions.

The fixed stack cache has 1384 entries: forty floating-overload slots and
twenty-one independent 64-width integer ranges. The four saturating families use
separate ranges. Attribute validation runs once per admitted declaration under
the shared 1,000,000-work limit. Fixed two-ID attribute storage and the three
existing owned execution arrays/cleanup remain. Retained allocation is not measured.

`scalar_saturating_test.v` passes **1,303,888** independent margin/carry-reference
comparisons, including **36,864 boundary pairs**. Every i1..i8 input pair is
exhausted; wider widths receive 4,096 mixed-bit pairs and a twelve-by-twelve edge
matrix. The signed reference safely reconstructs signed values, checks margins
before computing any potentially overflowing result, and clamps first. The
unsigned-add reference uses two 32-bit limbs with an explicit carry. Addition
commutativity, zero identities and strict name/width/arity/evaluator guards pass.

`tests/ios/air-saturating.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates and
LLVM-verifies 256 primitive functions. It compares **1,303,888 bit-exact native
LLVM results**, including **36,864 boundary pairs**, with incoming high-bit
noise on both arguments. Inputs cover signed minima/maxima and neighbors,
unsigned maxima/zero, alternating and byte patterns. Every i1..i8 pair is
exhausted; wider widths receive 4,096 mixed-bit pairs plus the edge matrix.

Controls check 512 input-poison results, 512 undef rejections, 512 budget/
integer-API rejections, twenty-eight metadata corruptions, eight argument-type
mismatches, twelve name/width mismatches and twenty result corruptions. Another
512 mixed-family cache chains use all four declarations with zero as the
second operand and return the original inputs' XOR in six instructions.
Only generated fixtures execute. LLVM/JIT/native code is not sanitizer-
instrumented. Complete IR/bitcode, every comparison, binaries, identities and
logs belong in external bundles. `tests/ios/air-saturating-regressions.v` runs
the local pinned-toolchain shared-profile checks; its header documents the
environment and output children must be fresh.

This is scalar execution groundwork. No AIR shader, Metal device, GPU command
or application launch is qualified.

## Vector saturating addition and subtraction

Ordinary direct `llvm.sadd.sat.vNiW`, `llvm.uadd.sat.vNiW`,
`llvm.ssub.sat.vNiW` and `llvm.usub.sat.vNiW` calls support fixed 1..16-lane
integer vectors at widths i1..i64. Both arguments and the result must have the
identical vector type. Signed results clamp to the signed minimum/maximum;
unsigned addition clamps to the unsigned maximum and unsigned subtraction to
zero. Defined operands always produce defined clamped values, including i1 and
i64. The existing scalar evaluator uses unsigned arithmetic and sign-bit overflow
detection; no host signed overflow or new normal-path allocation is added.

Poison propagates per lane from either source. Any undef source lane fails even
when the result is discarded. Source/result freezes select zero for indeterminate
lanes; results are independent snapshots. Both scalar APIs, void and memory
execution admit these vector calls. Floating producers retain their mixed-only
policy. Canonical names, exact types/signatures, direct declaration identity,
ordinary flags/calling convention and both arguments are checked. Harmless
function attributes remain allowed; return/parameter attributes, including
immarg, reject. Cold unsupported blocks reject before writes. Vector arguments/
returns/PHIs/loads/stores, scalable/oversized vectors, i65/wider lanes and AIR
aliases remain outside this profile. The binary integer profile is shared with
vector extrema without changing its source checks or work accounting.

The four families use separate 1,024-entry width/count ranges in the order above:
11968..12991, 12992..14015, 14016..15039 and 15040..16063. The shared declaration
cache now has 18,112 stack entries, including 2,048 saturating-shift identities. Each call costs one instruction, three lane
counts of profiling work and one construction slot. Existing 4,096-result and
1,000,000-work limits remain unchanged. Attributes are checked per cached
identity; both sources are checked on every call.

`vector_saturating_test.v` checks 4,124,032 independent value comparisons, using
checked signed margins and two unsigned 32-bit limbs with explicit carry.
Every i1..i8 pair, 4,096 wider patterns per operation, all widths/counts, another
36,864 boundary pairs, addition commutativity, zero identities, masking and
snapshots are covered. Another 835,584 lane-state checks cover both inputs.
The shared cache test checks all 18,112 identities. Older units now use
unsupported vector carryless-multiply name guards while preserving positive tests.

`tests/ios/air-vector-saturating.v LLVM_AS FRESH_EXTERNAL_DIR` generates all four
operations in the decoded matrix and bulk narrow exhaustion/wide patterns. It
also checks all four declarations together using two edge pairs at every width,
both poison/undef sources, repaired attribute baselines, forbidden immarg groups,
cold i65 blocks and exact shared work/storage limits through four APIs. Native
comparisons consume defined extracted values with canonical padding; the VM
also receives high-bit noise. Generated IR, bitcode and comparison records are
gzip-compressed after each module, immediately decoded and compared with their
original SHA-256; both hashes remain recorded. Historical checkers are unchanged.

The software Metal fixture adds 1,504 dispatches across 288 kernels per runtime:
1,408 complete and 96 fail as expected. It covers all four families, equal inputs,
source/result freezes, poison/undef/discard, nonzero old snapshots, repeated
saturating chains, deferred input writes, sparse bindings and output guards.
Eight tail/i65 pipelines reject. This qualifies CPU software execution; native
JIT is uninstrumented, retained heap is unmeasured and GPU rendering/application
launch remain unqualified.

Reference: [LLVM saturation semantics](https://llvm.org/docs/LangRef.html#saturation-arithmetic-intrinsics).
