# Bounded scalar memory execution

`run_memory_function` executes a defined ordinary void function with pointer
arguments, one basic block, scalar loads/stores, flag-free binary operations
and a final ret void. It accepts i1..i64, half and float memory values.
Integer binary opcodes and half/float fadd/fsub/fmul/fdiv/frem reuse the scalar
interpreter's arithmetic, undefined-operation guards and poison propagation.
Flags (including fast-math), GEP, alloca, pointer casts, branches, atomics,
volatile accesses, calls or aggregate loads/stores
are rejected. The separate scalar/void APIs retain their existing profiles.

`memory_function_profile` validates the supported signature and complete body
without accessing buffer data. Its owned `arguments` array describes required
address spaces, minimum extents, alignment and read/write usage; release it
with `profile.free()`. The executor uses the same validation, then checks
actual bindings and budget before execution. A store through address space 2
is rejected when building the profile.

Each pointer argument binds to an IRMemoryBinding with borrowed mutable data,
a byte offset, declared virtual base alignment and write permission. At most
64 bindings of at most 64 MiB each are accepted. Address spaces 0 and 1 are
supported; space 2 requires a readonly binding. Pointer operands must directly
name arguments. No host pointers are accepted. Bindings may share byte storage;
execution observes earlier stores through aliases. Callers retain ownership
and must prevent concurrent access/mutation during a run.

All accesses and instruction shapes are preflighted before any store. Bounds,
explicit power-of-two alignment and write permission are checked. Alignment
zero (unresolved ABI default) rejects. The virtual base must satisfy the
declared alignment; the binding offset must satisfy each access alignment.
Big-endian layouts reject; absent layouts use this API's little-endian profile.
Valid LLVM IR and matching immutable parsed indexes remain preconditions.

Loads assemble little-endian bytes and mask narrow integer padding bits.
Stores write only the scalar's ceil(bits/8) bytes, zeroing unused high bits.
Loads/stores preserve floating raw bits. Buffer bytes are treated as defined values;
uninitialized-memory/poison shadow tracking is not implemented. Poison stores
and selected undef reject. Dynamic value errors can leave earlier stores
visible; errors do not roll back memory. Every load/store/binary/return costs
one step, with the existing maximum step limit. Preflight rejects an insufficient budget.
Execution scratch arrays are freed on success and failure; binding data is not.

`tests/ios/air-memory-execute.v` assembles LLVM fixtures and checks 16,896 copies
against independent byte expectations, guards and constant stores. Execution is
also checked against native LLVM by `tests/ios/air-memory-arithmetic.v` for
load/compute/store bodies, including poison consumption and budget guards.
The opt-in software Metal runner uses this profile for its bounded single-thread
compute pipeline. General shader execution and GPU dispatch remain pending.
