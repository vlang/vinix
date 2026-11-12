# Overflow pairs through select and PHIs

The mixed scalar API carries literal unpacked `{iN, i1}` pairs from instructions
or [zero/poison constants](SCALAR-PAIR-CONSTANTS.md) through unflagged select
and PHIs, for every i1..i64.
Incoming pair types must match the result type exactly. Select requires
a scalar i1 condition. PHIs retain the usual grouping, incoming-target and
function-local block checks. Every block is preflighted, including unvisited
ones. Pairs support [field insertion](SCALAR-PAIR-INSERT.md).
Aggregate arguments, returns, other constants, freeze and other
layouts remain unsupported. The integer-only API keeps its no-call profile.

Select reads only the chosen pair after evaluating the condition. A poison
condition produces a poison pair, so both extracted fields remain poison;
undef conditions error under the existing bounded profile. A selected poison
pair retains both field-poison states, while an unselected poison pair has no
effect. PHIs
read only the executed predecessor, and all incoming pair/scalar values are
collected before any result slot changes. This preserves simultaneous swaps
across loop backedges, including the arithmetic bits, overflow flag and poison.
See the LLVM [select](https://llvm.org/docs/LangRef.html#select-instruction) and
[PHI](https://llvm.org/docs/LangRef.html#phi-instruction) contracts.

The existing pending-PHI array, 16-byte runtime values and three owned arrays
are unchanged. A control-flow reader dispatches checked pair operands to the
existing tagged pair reader, and scalar operands to the ordinary scalar
reader. Each executed select, PHI, branch and return costs one step. No new
valid-path allocation, host pointer/FP operation, numeric helper or intrinsic
declaration-cache range is introduced. Retained allocation was not measured.

`scalar_pair_flow_test.v` checks pair select/PHI profile shapes and matching
types, scalar conditions, instruction-result IDs, runtime tags, availability,
scalar/pair separation and the unchanged 16-byte value layout.

`tests/ios/air-pair-flow.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
portable fixtures in V and uses independently assembled/verified native LLVM
MCJIT references. Its 384 defined functions cover selection, branch diamonds
and parallel loop PHIs for both fields across every width. It compares 327,680
exact results, including 20,480 edge results. Loops take zero through five
iterations, swapping two pairs alongside a scalar PHI and merging the zero/
loop exit through another pair PHI. High input bits exercise masking of the
integer inputs, i1 conditions and i8 loop counts. Both fields and every exact
step count must match. Further interpreter-only cases cover selected/unselected
poison, a PHI's unavailable unchosen pair, poison swapping across backedges,
poison/undef conditions, freezing extracted poison, incomplete/long loop
budgets, integer API isolation, unsupported constants/layouts, corrupt control
metadata/types/IDs and output corruption. Native poison results are never
consumed. Fixture IR, bitcode, assembler status, target and every defined
comparison are saved outside Git. No AIR shader or GPU command runs.
