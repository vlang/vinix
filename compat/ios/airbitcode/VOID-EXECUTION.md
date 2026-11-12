# Void-return scalar execution

`IRTypedProgram.run_void_function` executes defined ordinary functions whose
return type is void. Arguments and instructions use the existing mixed scalar
profile: i1..i64, binary16 and binary32 arithmetic, supported intrinsics and
bounded control flow. It returns `IRVoidRun{steps: ...}`. `ret void` costs one
step and reads no value. Nonvoid signatures reject; integer/scalar result APIs
continue to reject void signatures. Argument counts, function attributes,
calling conventions, decoded operands, poison branch conditions, selected undef,
unreachable instructions and step budgets retain their existing checks.

Valid LLVM IR and matching immutable indexes remain preconditions. This API
does not add memory instructions, pointer arguments, kernel ABI binding,
pipeline construction or dispatch. Discarded poison arithmetic has no returned
value; poison consumed as a branch condition still rejects.

The maintained serialized-bitcode check is `tests/ios/air-void-execute.v`.
Build it with the repository's V module path, then run its executable with
`LLVM_AS FRESH_EXTERNAL_DIR`. It assembles fixtures with llvm-as, parses them
through the production readers and checks 641 executions against explicit
path/step expectations. This is not a native-JIT result comparison: void
functions in this profile have no observable output besides interpreter steps.
