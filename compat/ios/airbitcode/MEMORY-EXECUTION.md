# Bounded scalar memory execution

`run_memory_function` executes a defined ordinary void function with pointer
arguments, one basic block, scalar loads/stores, flag-free binary operations,
comparisons, scalar select/casts/freeze, floating negation, forward constant GEPs
and a final ret void.
It accepts i1..i64, half and float memory values.
Integer binary opcodes and half/float fadd/fsub/fmul/fdiv/frem reuse the scalar
interpreter's arithmetic, undefined-operation guards and poison propagation.
Arithmetic flags (including fast-math), alloca, pointer casts, branches, atomics,
volatile accesses, calls or aggregate loads/stores
are rejected. The separate scalar/void APIs retain their existing profiles.

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
Loads/stores preserve floating raw bits. Buffer bytes are treated as defined values;
uninitialized-memory/poison shadow tracking is not implemented. Poison stores
and selected undef reject. Dynamic value errors can leave earlier stores
visible; errors do not roll back memory. Every load, store, binary operation,
comparison, select, cast, fneg, freeze, GEP and return costs one step, with the existing
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
The opt-in software Metal runner uses this profile for its bounded single-thread
compute pipeline. General shader execution and GPU dispatch remain pending.
