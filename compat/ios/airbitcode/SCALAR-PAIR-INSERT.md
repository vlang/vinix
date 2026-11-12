# Field insertion in bounded overflow pairs

The mixed scalar API supports unflagged `insertvalue` in instruction-produced
literal unpacked `{iN, i1}` pairs, for every i1..i64. Exactly one literal index
selects the arithmetic field (zero) or flag field (one). The inserted scalar
must have that field's exact type, and source/result pair types must match.
Preflight checks shape, index, types and source origin in every block.
Aggregate arguments, returns, constants, freeze, other layouts and nested
field paths remain unsupported. The integer-only API keeps its no-call profile.

Insertion replaces only the chosen field and its poison state. Inserting a
defined scalar can repair that field of a poisoned pair without affecting its
neighbor. Inserting poison poisons only that field. Replacing both fields with
defined scalars produces a defined pair. Overflow calls with poisoned inputs
and selects with poisoned conditions mark both fields poison; select/PHIs
preserve each field independently. Extraction reports the selected field's
poison state. Undef replacement scalars remain outside the bounded profile,
even if a later extraction would not observe them. See
[LLVM insertvalue semantics](https://llvm.org/docs/LangRef.html#insertvalue-instruction).

An additional internal flag-field poison boolean fits within the existing
16-byte runtime value. The data/scalar poison boolean retains its scalar
meaning. Production uses scalar masks/copies and the existing tagged pair
reader and owned execution arrays. Each insertion consumes one instruction
step. Public result types, numerical helpers, declaration caches and ownership
remain unchanged. No valid-path allocation is added. Retained allocation was
not measured.

`scalar_pair_insert_test.v` checks 2,048 width/pattern/poison states across
i1..i64, reinsertion and both overwrite orders, field independence, local/full
repair, masking, the 16-byte layout and value/profile/type/origin/index guards.

`tests/ios/air-pair-insert.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
portable fixtures in V and compares independently assembled/verified native
LLVM MCJIT results. Its 768 defined functions cover each field's replacement
and untouched neighbor, overwriting poison, repairing one field of an entirely
poisoned pair, and replacing both fields. Only defined extracted fields are
called natively. It compares 786,432 exact results, including 12,288 edge
results, with high unused input bits and exact kind/width/poison/step checks.
Interpreter-only controls cover poisoned fields, unaffected neighbors, undef
replacement rejection, freeze after extraction, separate field-poison states
through select and parallel pair/scalar loop PHIs, budgets, integer isolation,
malformed insertion metadata/types/indices/origin and output corruption,
including a lost flag-field poison tag. Fixtures, bitcode, comparison rows,
assembler status and JIT identity go to a fresh external directory. No AIR
shader, iOS app or GPU command runs.
