# Scalar floating-point classification

The mixed scalar interpreter accepts ordinary direct calls to
`llvm.is.fpclass.f16` and `.f32`. Each takes a half/float value and a constant
i32 mask and returns i1. The integer-only API continues to reject all calls.

| Mask bit | Class |
| --- | --- |
| 0 | Signaling NaN |
| 1 | Quiet NaN |
| 2 | Negative infinity |
| 3 | Negative normal |
| 4 | Negative subnormal |
| 5 | Negative zero |
| 6 | Positive zero |
| 7 | Positive subnormal |
| 8 | Positive normal |
| 9 | Positive infinity |

The result is true if the input's class is included in the mask. Classification
reads integer sign/exponent/fraction bits directly, distinguishes signaling
and quiet NaNs without quieting them, and observes subnormals regardless of
host FP modes. It invokes no host FP, libm or LLVM and raises no FP exception.
Poison input propagates, even for empty/full masks; selected undef errors.
The input is masked to its declared precision, as with other scalar arguments.

Admission checks the exact name, scalar floating input width, i1 result, i32
mask, direct external declaration identity, signature, arity, calling convention
and address space. The mask must resolve to a nonsplat integer/zero constant
in the caller's constant pool, with value 0..1023. Arguments, instruction
results, poison/undef/opaque constants and masks outside those ten bits reject.
This validation runs for every call, including in unvisited blocks; caching
declaration attributes never caches a call's mask. Fast-math/tail flags,
call-site attributes, vectors, other precisions and AIR aliases reject.
Valid LLVM IR and matching immutable indexes remain preconditions.

Declaration validation retains the [existing harmless function attributes](SCALAR-INTRINSICS.md).
Classification and integer zero counts permit a second attribute group, containing exactly
parameter two's enum `immarg` (bitcode attribute 60). Other parameter/return,
string/type or duplicate slot groups reject. A fixed two-ID stack array handles
the groups under the existing shared 1,000,000-work budget. Mask constancy is
checked even when the declaration has no attribute list. Declaration cache
keys use the floating input width, keeping both overloads distinct despite
their shared i1 result. The cache reserves forty floating-overload slots within
the 488-entry fixed stack cache shared with integer bit intrinsics. No new owned
execution arrays are introduced; the existing three arrays and cleanup remain.
A CALL costs one executed instruction; primitive CALL/return takes two.

`scalar_fpclass_test.v` checks 40,960 exact results: all 1,024 masks against
twenty class/sign/boundary representatives in each precision. It also checks
name/arity/mask and exact immarg slot/encoding/attribute/duplicate/work guards.

`tests/ios/air-fpclass.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates 2,048
primitive functions and native LLVM wrappers, one per mask and precision. Every
mask receives twenty boundary inputs. Eighteen masks (each singleton, empty/
full, NaN, zero, subnormal, normal, infinity and finite) additionally receive
all 65,536 half encodings and 65,536 mixed-bit float inputs. All **2,400,256**
results compare bit-exactly, including NaN classifications. Incoming arguments
carry high-bit noise to check precision masking. Two branch/PHI chains exercise
classification as control flow with forty boundary cases and precise steps.
Two poison and two undef controls pass. Eighteen call-metadata/budget/integer-
isolation controls, twenty-four malformed-mask controls and ten result corruptions
check rejection. Twenty-four environment controls exercise upward, downward
and toward-zero modes with sNaNs, subnormals and negative zero. Production and
native LLVM both retain exact predicates and leave all FP exception flags clear.
Native LLVM/JIT code is not sanitizer-instrumented; retained allocation is not
measured. The checker only executes its generated fixture. IR, bitcode, every
comparison, binaries, identities and logs belong in complete external bundles.

This is scalar execution groundwork. It does not execute an AIR shader,
create a Metal device, submit GPU work or qualify an iOS application launch.

References: [LLVM classification semantics](https://llvm.org/docs/LangRef.html#llvm-is-fpclass-intrinsic),
[bitcode attribute IDs](https://github.com/llvm/llvm-project/blob/main/llvm/include/llvm/Bitcode/LLVMBitCodes.h).
