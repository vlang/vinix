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

The interpreter supports integer add/sub/mul, unsigned/signed division
and remainder, shifts, and/or/xor, all ten integer comparisons, trunc/zext/sext,
scalar select, freeze, direct branches/switches, PHIs and return. It rejects opaque/deferred
instructions and other instruction families, even in unvisited blocks. It checks
`nuw`/`nsw` on add/sub/mul/shl and `exact` on udiv/sdiv/lshr/ashr. Flags use
their serialized, family-specific bit positions. Unknown bits, wrong-family
flags, disjoint/samesign and cast flags reject; they are not silently ignored.
Function attributes are rejected rather than assuming their boundary semantics.
Floating point, vectors, pointers, memory operations and calls are
outside this profile.
The separate [mixed scalar entry point](BINARY32.md) adds software binary32
execution while preserving this integer-only API.
That mixed entry point also accepts the bounded unary
[integer bit intrinsics](SCALAR-INTEGER-INTRINSICS.md); this entry point retains
its no-call profile.

Arithmetic uses explicit unsigned bit patterns to avoid host signed-overflow
behavior. Flag-free arithmetic wraps at its declared width. `nuw`/`nsw` overflow
produces poison rather than a wrapped result. Multiplication checks unsigned
magnitudes against the appropriate signed/unsigned limit without widening to a
host signed type. Left-shift overflow checks whether reversing the shift
reconstructs the input. `exact` division with a remainder and `exact` right shifts
that discard nonzero bits produce poison. Overshifts produce poison independently
of flags. Poison propagates through arithmetic, casts and comparisons; select reads
only its chosen value and a poison condition produces poison. A return may
retain poison, while a poison branch condition errors. Division/remainder by
zero and signed minimum divided/remaindered by -1 error rather than invoke host
undefined behavior. Poison division/remainder operands are explicitly outside
this profile and error. Reading undef or an unsupported constant expression
errors; unchosen select/PHI values are not read. [Scalar freeze](SCALAR-FREEZE.md)
is the exception: direct undef constants and poison become a fixed zero choice;
defined inputs retain their exact bits. It does not admit undef computations
before the freeze or rescue preceding undefined behavior.

On entry to a block, all selected PHI values are read before any PHI result is
written. This preserves simultaneous swaps across loop backedges. PHIs select
the actually executed predecessor, not an inferred list position. Value IDs
remain scoped; arguments/constants use the existing pools and results occupy
function-local slots. An unavailable result read, missing PHI predecessor,
executed unreachable or block without a control transfer errors.

Switches compare masked i1..i64 bit patterns in decoded table order, stopping
at the first matching case or taking the default after the full scan. The
existing decoder validates literal cases, uniqueness, absolute case IDs and
function-local destinations. Shared destinations preserve the actual predecessor
for PHIs, including duplicate edges with identical incoming values. Empty
tables still evaluate their condition. Poison/undef conditions error. Wider
integers and the reverted legacy range encoding remain outside execution.

The caller supplies a positive step limit up to 1,000,000. Every visited
instruction, including PHIs, branches and return, consumes one step. Every
tested switch case consumes an additional step, bounding scans and repeated
dispatch within the same budget. An empty table adds no case-comparison steps.
`IRIntegerRun.steps` reports this combined count. Exhaustion
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
return, unsupported flags/attributes and narrow argument/return masking. It also
compares 1,397,052 exhaustive i1..i8 flagged operations against widened arithmetic,
checks 28 i64 limits and rejects unknown/wrong-family masks. Decoded-instruction
tests verify a flagged defined result, poison return and precise budget.
Switch tests cover first/middle/last matches, high-bit and zero cases, shared
destinations, default and empty tables, precise comparison/return budgets,
invalid conditions and bounded matched/default self-loops.

`tests/ios/air-integer-flags.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
five bounded fixture modules, one per i1/i8/i16/i32/i64 width. Its 10,240 functions
cover 128 input pairs for each supported flag combination/family at every width.
Vinix executes the original instructions. A separate LLVM module computes the
result and an explicit poison tag using unflagged i128 arithmetic and range
checks. Its masked shifts and nonzero divisors keep the reference fully defined.
LLVM verifies and folds that reference with instcombine. Exact values and tags
must match, with no unresolved results accepted. Division inputs avoid zero/overflow UB;
overflow, inexact and overshift cases remain included as poison comparisons.
Each width rejects four corrupted results. Source, original/oracle bitcode, folded IR,
assembler status and every comparison are saved externally. No fixture in this
tool runs through a JIT or a native function pointer. Folding the flagged
instructions directly cannot establish an exact poison oracle: LLVM may legally
[refine poison to an ordinary value](https://llvm.org/docs/LangRef.html#poison-values).

`tests/ios/air-integer-execute.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
portable LLVM fixture IR in V and assembles it independently. LLVM verifies the
fixture, then MCJIT compiles reference functions for the host. The tool executes
134 scalar functions and compares 17,280 interpreter results with actual native
reference calls. These cover i1/i8/i16/i32/i64,
arithmetic, predicates, casts, a branch diamond, select and a loop whose PHIs
swap values simultaneously. Switches cover nine widths including i2/i7/i31/i63,
shared PHI edges, empty tables, loop dispatch and every key in a dense 256-case
table. High input bits exercise truncation, and dense scans check exact budget
accounting. Division and shift inputs avoid undefined reference executions.
Twelve guarded cases and two poison-return cases run only in the V interpreter;
their undefined/poison results are not compared with native bits. A separate
test requires dense-scan budget exhaustion.
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
[PHI semantics](https://llvm.org/docs/LangRef.html#phi-instruction),
[switch semantics](https://llvm.org/docs/LangRef.html#switch-instruction) and
[LLVM execution-engine C API](https://llvm.org/doxygen/group__LLVMCExecutionEngine.html).
