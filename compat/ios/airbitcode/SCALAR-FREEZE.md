# Scalar freeze execution

Both execution APIs accept unflagged `freeze iN` for i1..i64. The mixed scalar
API additionally accepts half and float. Preflight checks a single operand,
a result with that exact type, and the decoder's zero opcode. Unsupported types
and malformed freezes reject even in unvisited blocks. Vectors, aggregates,
pointers, double and integers wider than 64 bits remain outside execution.

For defined operands, freeze copies the raw bits. Signed zeros, infinity and
quiet/signaling NaN payloads are preserved. For poison and a direct scalar undef
constant, the interpreter chooses zero. The normal function-local result slot
stores that choice for all subsequent uses. Each dynamic evaluation consumes
one instruction step. Separate freezes and loop iterations can choose the same
value: LLVM permits this deterministic policy. See the
[LLVM freeze contract](https://llvm.org/docs/LangRef.html#freeze-instruction).

Only freeze's operand reader admits a direct undef constant. Undef arithmetic,
chosen undef select/PHI inputs, constant expressions, unavailable SSA values,
poison division/remainder operands and immediate undefined behavior remain
outside the supported profile. A later freeze does not bypass an earlier error.
Ordinary reads continue returning poison or rejecting undef as before. The
production path uses V, existing constant pools and existing result arrays;
it adds no valid-path allocation, host FP operation or LLVM dependency.

`integer_exec_test.v` covers all integer widths, half/float raw bit preservation,
poison/undef choices, computed overshift poison, repeated uses, exact steps,
budget exhaustion and preceding undef/UB rejection.

`tests/ios/air-freeze.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates fixtures
in V, independently assembles/verifies them, and uses native LLVM MCJIT with
raw-bit ABI wrappers. It compares defined results exactly: exhaustive i1..i16
and half inputs, 4,096 mixed values for each wider integer, 65,536 float values,
and sixteen edges for every type. High unused input bits exercise argument
masking. Arbitrary native freeze choices are never compared with the local
zero policy. Instead, repeated-use XOR and reflexive integer equality followed
by branch/PHI control flow must return zero for every permitted choice. Float
properties bitcast first, avoiding NaN's non-reflexive floating comparison.
Four-iteration PHI loops check repeated dynamic evaluation. Interpreter-only
controls verify fixed choices, computed poison, raw unfrozen poison/undef,
budgets, unsupported profiles, malformed metadata in live/dead blocks and
corrupted output values/kinds/widths/poison/steps. Fixtures, bitcode, all defined
comparisons and JIT identity are saved outside Git.

This executes portable scalar LLVM fixtures. It does not execute AIR shaders,
iOS applications or GPU commands, or establish a new Fortnite launch boundary.
