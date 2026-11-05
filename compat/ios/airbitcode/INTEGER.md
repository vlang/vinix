# Bounded scalar integer execution

After building matching immutable `Stream`, `IRModule`, `IRConstantPools`,
`IRFunctionBodies` and `IRTypedProgram`, call:

```v
result := p.run_integer_function(ir, stream, pools, bodies, function_index,
    arguments, step_limit)!
```

The function must be valid LLVM IR within this deliberately small profile. It
must be a definition with ordinary calling convention, no attribute set, no
varargs, scalar integer arguments and a scalar integer return, all i1 through
i64. Arguments are u64 bit patterns masked to their declared widths. The result
retains its declared width, masked bits, poison state and executed step count.
Result bits must not be consumed when `poison` is true.

The interpreter supports flag-free integer add/sub/mul, unsigned/signed division
and remainder, shifts, and/or/xor, all ten integer comparisons, trunc/zext/sext,
scalar select, direct branches, PHIs and return. It rejects opaque/deferred
instructions and other instruction families, even in unvisited blocks. Nonzero
instruction flags are unsupported, including overflow/exact/disjoint/samesign
flags; they are not silently ignored. Function attributes are rejected rather
than assuming their boundary semantics. Floating point, vectors, pointers,
memory operations, calls, switch and freeze are outside this profile.

Arithmetic uses explicit unsigned bit patterns to avoid host signed-overflow
behavior. Flag-free arithmetic wraps at its declared width. Overshifts produce
poison. Poison propagates through arithmetic, casts and comparisons; select reads
only its chosen value and a poison condition produces poison. A return may
retain poison, while a poison branch condition errors. Division/remainder by
zero and signed minimum divided/remaindered by -1 error rather than invoke host
undefined behavior. Poison division/remainder operands are explicitly outside
this profile and error. Reading undef or an unsupported constant expression
errors; unchosen select/PHI values are not read. No freeze choice is invented.

On entry to a block, all selected PHI values are read before any PHI result is
written. This preserves simultaneous swaps across loop backedges. PHIs select
the actually executed predecessor, not an inferred list position. Value IDs
remain scoped; arguments/constants use the existing pools and results occupy
function-local slots. An unavailable result read, missing PHI predecessor,
executed unreachable or block without a control transfer errors.

The caller supplies a positive step limit up to 1,000,000. Every visited
instruction, including PHIs, branches and return, consumes one step. Exhaustion
returns an error and releases all execution arrays. No partial mutable state
escapes. Each run borrows its inputs and owns three temporary arrays: result
slots, known-slot flags and pending PHIs. Pending capacity is the maximum PHI
count in a block. The existing 262,144-instruction/result bounds apply.

Preflight checks the supported shape, types, arities and function-local target
ranges. It is not a general LLVM verifier and does not prove dominance or full
CFG/PHI validity. Parsed indexes alone do not establish those properties; only
valid LLVM IR is a supported execution input. Register availability checks are
additional runtime guards. No native or host function address is used by the
production interpreter, which is V only and has no LLVM runtime dependency.

`integer_exec_test.v` checks exact arithmetic/compare patterns, narrow and wide
wrapping, overshift poison, undefined division guards, both branch paths,
scoped values, precise budgets, a bounded infinite loop, lazy select, poison
return, unsupported flags/attributes and narrow argument/return masking.

`tests/ios/air-integer-execute.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
portable LLVM fixture IR in V and assembles it independently. LLVM verifies the
fixture, then MCJIT compiles reference functions for the host. The tool executes
122 scalar functions for 128 input triples each and compares 15,616 interpreter
results with actual native reference calls. These cover i1/i8/i16/i32/i64,
arithmetic, predicates, casts, a branch diamond, select and a loop whose PHIs
swap values simultaneously. Division and shift inputs avoid undefined reference
executions. Nine guarded cases and two poison-return cases run only in the V
interpreter; their undefined/poison results are not compared with native bits.
Four corrupted result controls must reject. Results and step counts are retained
in `comparisons.tsv`, alongside source, bitcode, assembler status and JIT target.

The test tool JITs only its generated fixture, using a uniform three-i64 argument,
i64-return ABI. It has no mode for executing arbitrary AIR or application input.
LLVM and its generated machine code are not sanitizer-instrumented. Build with
the [README flags](README.md); the reference tool uses Homebrew LLVM headers and
library under `/opt/homebrew/opt/llvm`.

This executes a scalar IR prerequisite, not an AIR shader, Metal command, iOS
application or GPU workload. Global storage, buffers, intrinsic lowering,
floating-point/vector execution, resource/pipeline objects and presentation
remain separate backend work. The default Metal device remains unavailable.

References: [LLVM integer semantics and poison](https://llvm.org/docs/LangRef.html),
[PHI semantics](https://llvm.org/docs/LangRef.html#phi-instruction) and
[LLVM execution-engine C API](https://llvm.org/doxygen/group__LLVMCExecutionEngine.html).
