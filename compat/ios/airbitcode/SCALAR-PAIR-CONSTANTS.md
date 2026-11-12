# Zero and poison pair constants

The mixed scalar API accepts `zeroinitializer` and `poison` of the existing
literal unpacked `{iN, i1}` type, for every i1..i64. Extraction, insertion,
select and PHIs share a checked source policy: an exactly typed instruction
result or one of these two constant kinds. Constant-pool lookup preserves
module/function scope and rejects arguments, declarations, mismatched types,
splats and other constant kinds. All blocks are preflighted, including
unchosen sources. Other parsed constant records, including aggregate
field-list and undef records, remain unsupported, as do aggregate
arguments/returns and other layouts. [Pair freeze](SCALAR-PAIR-FREEZE.md)
additionally accepts a direct undef pair without broadening other consumers.
The integer-only API retains its scalar profile.

Zero creates two defined zero fields. Poison marks both fields poison.
Insertion can replace one or both field-poison states, enabling the common
`insertvalue {iN, i1} poison, ...` construction. Select/PHIs preserve both
states, and extraction reports only the selected field. See LLVM's
[zero initialization](https://llvm.org/docs/LangRef.html#complex-constants)
and [aggregate operations](https://llvm.org/docs/LangRef.html#aggregate-operations).

The resolver reads immutable constant-pool metadata and returns the existing
16-byte tagged value. It does not walk aggregate records or allocate storage.
Instruction-result availability and scalar/pair separation guards remain.
Numerical helpers, declaration cache and three owned execution arrays are
unchanged. Constant reads add no instruction steps. No valid-path allocation
is introduced; retained allocation was not measured.

`scalar_pair_constants_test.v` covers module zero/local poison, all consumers,
tag/layout preservation, argument/scope/range/type guards, six unsupported
constant kinds and corrupt metadata. Existing flow/insertion unit checks
retain rejection of unavailable constants and mismatched sources.

`tests/ios/air-pair-constants.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
portable fixtures in V, independently assembles/verifies them, and compares
native LLVM MCJIT references through raw-bit ABI wrappers. It checks 524,288
exact results across 1,024 functions, including 32,768 edge results. Every
width covers direct zero extraction, zero/poison field construction, partial
repair, constant select, branch PHIs, repair after a poison PHI, and zero-seeded
loop accumulation. Loops cover zero through five iterations and exact budgets.
Only defined extracted outputs cross the native ABI. Interpreter controls
check direct/selected/PHI poison, unchosen poison, partial repair/freeze,
integer API isolation, long-loop limits, 1,024 unsupported undef/field-list
constant uses, extraction/constant metadata corruptions and altered outputs.
Fixtures, bitcode, every defined comparison, assembler status and JIT identity
go to a fresh external directory. No AIR shader, iOS app or GPU command runs.
