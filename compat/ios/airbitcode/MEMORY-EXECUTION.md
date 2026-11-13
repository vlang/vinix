# Bounded scalar memory execution

`run_memory_function` executes a defined ordinary void function with pointer
arguments, one basic block, scalar loads/stores, scalar binary operations,
comparisons, scalar select/casts/freeze, floating negation, forward constant GEPs
and a final ret void.
It accepts i1..i64, half and float memory values.
Integer binary opcodes and half/float fadd/fsub/fmul/fdiv/frem reuse the scalar
interpreter's arithmetic, undefined-operation guards and poison propagation.
Fast-math flags, alloca, pointer casts, branches, atomics,
volatile accesses, general calls or aggregate loads/stores
are rejected. The separate scalar/void APIs retain their existing profiles.

Integer add/sub/mul/shl accept `nuw`, `nsw` or both. Integer udiv/sdiv/lshr/ashr
accept `exact`. Their existing scalar evaluator propagates poison for violated
wrap/exact promises and overshifts. Unknown and wrong-family flag bits reject
during preflight. Floating arithmetic still requires zero flags. Division by
zero, signed division overflow and poison division inputs retain their dynamic
error behavior. Storing poison rejects; select may discard it and freeze can
make a defined choice. Flags add no execution steps.

Integer comparisons support all ten signed/unsigned/equality predicates;
half/float comparisons support all sixteen ordered/unordered predicates.
Results are scalar i1. Select requires an i1 condition and matching scalar
value/result types. Comparison and selection reuse the scalar interpreter's
helpers, including constant true/false FP predicates and poison propagation.
Select reads its condition and only the chosen value. Unselected poison/undef
constants do not reject; selected undef errors, and poison conditions/chosen
values propagate to a rejected poison store. Selection does not skip earlier
instructions. Pointer, vector and aggregate comparisons/selects and all
comparison/select flags remain unsupported.

Scalar casts share validation and value conversion with the scalar executor:
integer truncation/zero extension/sign extension across i1..i64, signed and
unsigned conversions between those integers and half/float, float-to-half
truncation, half-to-float extension, and same-width integer/floating bitcasts
at 16/32 bits. Integer width changes require the correct direction. Flags,
pointer casts, vector/aggregate casts, double and bfloat remain unsupported.
Float-to-integer conversion truncates toward zero; NaN, infinity and values
whose truncated result is outside the destination range produce poison.
Poison inputs propagate. Selected undef still errors. Storing a poisoned cast
rejects; a later select can discard its poison result. All casts cost one step.

Floating `fneg` toggles only the sign bit of half/float, preserving zeros,
subnormals, infinities and NaN payload/quiet bits. Poison propagates; undef
rejects. Scalar `freeze` preserves defined i1..i64/half/float bits and makes a
fixed zero choice for poison or undef. Every use of its SSA result sees that
same choice. It does not prevent an earlier instruction from rejecting undef
or another dynamic error. Both operations require zero flags and cost one
step. Pointer/vector/aggregate freezes remain unsupported by this API.

Direct LLVM integer bit intrinsics `ctpop`, `bitreverse`, `bswap`, `ctlz` and
`cttz` are supported using the scalar executor's declaration/signature,
attribute and value checks. Counts and reversal accept i1..i64; byte swap
accepts i16/i32/i48/i64. Zero-count calls require a literal defined i1
zero-poison flag. With that flag false, zero returns the width; with it true,
zero produces poison. Poison input propagates, undef input rejects, and
freeze may consume a poison result. Each call costs one step.

Direct LLVM `fabs`/`copysign` support half and float. Absolute value clears
the sign bit; copy-sign replaces the first operand's sign with the second's.
All other bits, including NaN payload and quiet/signaling bits, are preserved.
Copy-sign requires matching operand/result types and evaluates both operands.
Poison propagates and undef rejects, including in the sign donor. Each call
costs one step and shares scalar validation/evaluation. No floating arithmetic
or host rounding mode participates in these operations.

Direct LLVM `floor`/`ceil`/`trunc`/`round`/`roundeven` support matching half/float
operands and results. They round to integral floating values toward negative
infinity, positive infinity, zero, nearest with ties away from zero, and
nearest with ties to even, respectively. Zero results preserve the input sign;
infinities and already integral finite values are unchanged. NaNs use the
scalar evaluator's preferred quiet NaN choice. Poison propagates and undef
rejects. Each call costs one step and shares scalar validation/evaluation,
independent of host rounding mode. `rint` and `nearbyint` remain unsupported
by this buffer profile.

Direct LLVM `sqrt` supports matching half/float operands and results. It uses
the scalar evaluator's integer root/remainder algorithm and rounds to nearest
with ties to even, independent of host rounding mode. Positive finite values
produce correctly rounded roots, signed zero retains its sign, and positive
infinity remains positive infinity. Negative nonzero inputs and NaNs produce
the evaluator's preferred quiet NaN. Poison propagates and undef rejects.
Each call costs one step and shares scalar validation/evaluation.

Direct LLVM `minimum`/`maximum` support matching half/float operands and results.
They propagate a NaN from either input, using the scalar evaluator's preferred
quiet NaN representation. Other results preserve the selected input bits;
negative zero sorts below positive zero in either operand order. Both operands
are evaluated; poison propagates and undef rejects. Each call costs one step
and shares scalar validation/evaluation. Number-preferring and legacy
`minimumnum`/`maximumnum`/`minnum`/`maxnum` remain outside this buffer profile.

Direct LLVM `is.fpclass` accepts a half/float input and a literal defined i32
mask from 0 through 1023, returning scalar i1. Bits 0..9 select signaling NaN,
quiet NaN, negative infinity/normal/subnormal/zero, positive zero/subnormal/
normal/infinity, respectively. Mask zero selects nothing; 1023 selects all
defined inputs. Classification reads raw bits, distinguishing signaling and
quiet NaNs without floating arithmetic or exceptions. Poison propagates even
with zero/full masks; undef rejects. Calls cost one step and share scalar
validation/evaluation. Parameter two's exact immarg is admitted; every call's
mask is checked even after its declaration is cached. Invalid masks reject
in preflight before earlier stores. The i1 result can feed select, casts and
stores; its byte store has zero high padding bits.

Direct LLVM `fma` accepts three matching half/float operands and result. The
scalar evaluator forms the exact product-plus-addend on fixed integer limbs
and rounds once to nearest with ties to even, independently of host rounding
mode. Finite cancellation, overflow avoidance and subnormal ties therefore
retain fused semantics. Defined zero/infinity/NaN cases use the scalar FMA
rules and preferred quiet NaN choice. All three operands are evaluated; poison
propagates and undef rejects, including with a zero product. Calls cost one
step and share scalar validation/evaluation. Optional-fusion `fmuladd` and
constrained floating operations remain unsupported by this buffer profile.

Direct LLVM `ldexp` supports a half/float value, a signed i32 exponent and a
matching floating result. Scaling by a power of two uses the scalar integer
unpack/pack evaluator with nearest-even rounding, independent of host rounding
mode. Overflow becomes signed infinity; underflow rounds through subnormals
to signed zero. Zeros and infinities preserve their bits even at INT_MIN/MAX
exponents; NaNs use the preferred quiet choice. Both operands are evaluated,
so poison/undef in the exponent is not bypassed for a zero value. Calls cost
one step and share scalar validation/evaluation. The exponent must be i32,
not the floating input's type or another integer width.

Direct LLVM `fshl`/`fshr` also support i1..i64. All three operands must match
the result type. The amount is reduced modulo the width, so equal operands
produce rotations and oversized amounts are defined. A zero amount selects
the first input for fshl and the second for fshr. All operands are evaluated;
poison propagates even in an otherwise unused half at zero shift, and undef
rejects. These calls reuse scalar evaluation and cost one step each.

Direct LLVM `smin`/`smax`/`umin`/`umax` support matching scalar i1..i64
operands and results. Signed variants use two's-complement ordering, including
i1 true as -1 and i64 minimum. Unsigned variants compare the raw masked words.
Both operands are evaluated; poison propagates and undef rejects. Results
preserve the chosen input bits. Each call costs one step and reuses the scalar
intrinsic validator and evaluator.

Direct LLVM `abs` supports i1..i64 and requires a literal defined i1
minimum-poison flag. With that flag false, the signed minimum retains its raw
bits; with it true, the minimum produces poison. Other defined inputs produce
their absolute-value bit pattern. Poison input propagates and undef rejects;
freeze can consume the poisoned minimum. Each call costs one step and shares
the scalar validator, immediate checks and evaluator.

Direct LLVM `sadd.sat`/`uadd.sat`/`ssub.sat`/`usub.sat` support two matching
scalar i1..i64 operands and results. Signed variants clamp to the signed
minimum/maximum; unsigned variants clamp to zero/unsigned maximum. Defined
arithmetic overflow saturates instead of producing poison. Poison operands
still propagate and undef rejects. Each call costs one step and reuses the
scalar validator and evaluator.

Direct LLVM `sshl.sat`/`ushl.sat` support matching scalar i1..i64 values,
amounts and results. Valid amounts below the width shift left and clamp to
signed/unsigned bounds. Amounts are interpreted as unsigned width-masked words;
amounts at or above the width produce poison, even for zero input. Amounts do
not reduce modulo the width. Poison operands propagate and undef rejects.
Freeze or select may consume/discard computed overshift poison. Each call
costs one step and shares scalar validation/evaluation.

Direct LLVM `pext`/`pdep` support matching scalar i1..i64 operands and results.
In low-to-high bit order, extraction packs the input bits selected by the mask
into low positions; deposition scatters low input bits to the mask's selected
positions. A zero mask yields zero and a full mask preserves the input.
Both operands are evaluated; poison propagates even with a zero mask or value,
and undef rejects. Each call costs one step and shares scalar validation/evaluation.

Only ordinary direct calls to these thirty-three families' exact declarations are admitted:
no call-site attributes, fast-math flags, tail calls, indirect calls or other
intrinsics. Harmless declaration properties and parameter two's immarg use
the existing scalar allowlist and cumulative attribute-work limit. Each
declaration's attributes are checked once per profile; each call's signature
and constant flag are checked independently. No declaration or host pointer
is invoked by execution. Unsupported calls after stores reject in preflight.

`memory_function_profile` validates the supported signature and complete body
without accessing buffer data. Its owned `arguments` array describes required
address spaces, minimum extents, alignment and read/write usage; release it
with `profile.free()`. The executor uses the same validation, then checks
actual bindings and budget before execution. A store through address space 2
is rejected when building the profile.

GEPs resolve to a binding identity and a byte offset, using the existing ABI
layout/offset planner. They require an explicit little-endian data layout,
64-bit pointer/index widths and literal, defined nonnegative i1..i64 indexes.
Arrays, structures (including packed fields), byte-addressable fixed vector
elements and chains of earlier GEPs are supported. Every offset/stride/source
allocation size stays within 64 MiB; multiplication and addition are checked
before computing an offset. Negative, dynamic, poison/undef and wider indexes
reject. Constant-expression pointers, casts and numerical pointer inputs reject.

Known GEP inbounds/nusw/nuw flags are accepted only within this forward,
nonwrapping profile; unknown bits reject. All intermediate forward offsets
and unused GEP results must fit the binding's extent. A one-past result is
allowed; dereferencing it needs additional bytes and rejects. Profiles retain
an owned per-instruction access table, released by `profile.free()`. GEPs cost
one step but never construct host pointers or enter the scalar value slots.

Each pointer argument binds to an IRMemoryBinding with borrowed mutable data,
a byte offset, declared virtual base alignment and write permission. At most
64 bindings of at most 64 MiB each are accepted. Address spaces 0 and 1 are
supported; space 2 requires a readonly binding. Pointer operands must directly
name arguments or earlier supported GEP results. No host pointers are accepted.
Bindings may share byte storage;
execution observes earlier stores through aliases. Callers retain ownership
and must prevent concurrent access/mutation during a run.

All accesses and instruction shapes are preflighted before any store. Bounds,
explicit power-of-two alignment and write permission are checked. Alignment
zero (unresolved ABI default) rejects. The virtual base must satisfy the
declared alignment; the binding offset must satisfy each access alignment.
Derived offsets must also satisfy the access alignment independently of the
binding offset; offsets that would compensate for an unaligned binding reject.
Big-endian layouts reject; without GEPs, absent layouts use this API's
little-endian profile.
Valid LLVM IR and matching immutable parsed indexes remain preconditions.

Loads assemble little-endian bytes and mask narrow integer padding bits.
Stores write only the scalar's ceil(bits/8) bytes, zeroing unused high bits.
Loads/stores preserve floating raw bits. Nonzero padding in a narrow integer
load uses the profile's masked defined choice rather than tracking LLVM load
poison. Native reference comparisons require zero input padding. Buffer bytes are treated as defined values;
uninitialized-memory/poison shadow tracking is not implemented. Poison stores
and selected undef reject. Dynamic value errors can leave earlier stores
visible; errors do not roll back memory. Every load, store, binary operation,
comparison, select, cast, fneg, freeze, intrinsic, GEP and return costs one step, with the existing
maximum step limit. Preflight rejects an insufficient budget.
Execution scratch arrays are freed on success and failure; binding data is not.

`tests/ios/air-memory-execute.v` assembles LLVM fixtures and checks 16,896 copies
against independent byte expectations, guards and constant stores. Execution is
also checked against native LLVM by `tests/ios/air-memory-arithmetic.v` for
load/compute/store bodies, including poison consumption and budget guards.
`tests/ios/air-memory-gep.v` compares indexed loads/stores with native LLVM,
including narrow padding, layouts, GEP flags, chains and preflight failures.
`tests/ios/air-memory-casts.v` checks load/cast/store bodies against defined
native LLVM conversions, with separate poison and unsupported-input controls.
`tests/ios/air-memory-unary.v` checks fneg/freeze against native LLVM and exact
raw-bit expectations, all half encodings, and separate indeterminate choices.
`tests/ios/air-memory-flags.v` checks integer flags across all widths against a
defined widened LLVM value/poison-tag reference without executing native poison.
`tests/ios/air-memory-bits.v` checks bit intrinsic buffer functions against
defined native LLVM execution, with separate zero/poison/undef/call controls.
`tests/ios/air-memory-funnel.v` checks three-input funnel buffer functions,
rotation/amount boundaries and separate poison/undef/padding-choice controls.
`tests/ios/air-memory-extrema.v` checks signed/unsigned min/max buffer functions
against native LLVM, including boundary matrices and separate poison controls.
`tests/ios/air-memory-abs.v` checks absolute-value buffer functions, defined
native inputs, minimum-poison flags and per-call flag checks after cache hits.
`tests/ios/air-memory-saturating.v` checks saturating add/sub buffer functions
against defined native LLVM, boundary matrices and separate poison controls.
`tests/ios/air-memory-saturating-shift.v` checks valid native saturating shifts
and interpreter-only loaded/constant overshifts, zero overshifts and selection.
`tests/ios/air-memory-bit-permutation.v` compares extraction/deposition and both
round-trip chains against native LLVM, checks independent masked identities,
and exercises poison/undef, freeze/select, budgets and call-metadata controls.
`tests/ios/air-memory-float-sign.v` checks absolute value and copy-sign against
native LLVM and independent bit masks, including every half encoding, float
class/payload boundaries, cached-declaration chains and poison/undef controls.
Its native JIT uses the host CPU target to avoid generic ARM64 half-to-float
promotion quieting signaling NaNs; target receipts are saved with results.
`tests/ios/air-memory-rounding.v` compares all five rounding operations with
native LLVM, including every half encoding, float class/tie/precision limits,
cached idempotent chains, host rounding modes and poison/undef controls.
Arithmetic NaNs compare by class; the interpreter's preferred choice is
checked separately. Other results compare exact raw bits, including zero signs.
With a trailing `sqrt` argument, the same checker tests square root and
`sqrt(fabs(x))`, every half encoding, float midpoint-square neighbors across
the normal exponent range, domain/NaN cases and host rounding independence.
`tests/ios/air-memory-float-extrema.v` compares minimum/maximum and mixed cached
chains with native LLVM, including every half encoding with zero/unit anchors,
both precisions' class/NaN/zero-order matrices and independent chain identities.
`tests/ios/air-memory-fpclass.v` checks all 1024 masks against native LLVM and
independently labeled class boundaries, exhaustive half encodings under each
individual class and empty/full masks, i1 padding, cached-call immediate
validation, poison/undef and rounding/exception behavior.
`tests/ios/air-memory-fma.v` compares fused results and cached-call chains
against native LLVM, exhausts half inputs in two cancellation/scaling patterns,
checks boundary triples, and distinguishes fused results from separate
multiply/add for cancellation, overflow and underflow in both precisions.
`tests/ios/air-memory-ldexp.v` compares scaling and zero-scale chains against
native LLVM, exhausts half inputs under signed scales, checks exponent limits
and subnormal ties, and rejects malformed later cached calls before stores.
The opt-in software Metal runner uses this profile for its bounded single-thread
compute pipeline. General shader execution and GPU dispatch remain pending.
