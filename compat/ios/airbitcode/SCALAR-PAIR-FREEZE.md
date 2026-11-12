# Freeze for bounded overflow pairs

The mixed scalar API accepts unflagged `freeze {iN, i1}` for the existing
literal unpacked pair, for every i1..i64. It accepts instruction results,
zero/poison constants and a direct undef constant. Source/result types must
match exactly. Preflight validates shape, opcode, targets, indices and source
policy in every block, including unvisited ones. Other constant records,
aggregate arguments/returns, packed/named/nested layouts, vectors and other
field types remain unsupported. The integer-only API rejects pair freeze.

Freeze preserves defined fields and chooses zero independently for each poison
field. A direct pair undef chooses two zero fields. Both poison tags clear;
the aggregate tag survives. Each dynamic evaluation consumes one instruction
step and stores its complete choice in the existing result slot. Repeated
uses agree; separate freezes and iterations may choose the same value. This
implements LLVM's [element-wise freeze semantics](https://llvm.org/docs/LangRef.html#freeze-instruction).
No choice is made for ABI padding, which this execution profile never exposes.

Only this pair-freeze reader admits direct pair undef. Ordinary extraction,
insertion, select and PHIs retain their previous source policy. An earlier
undef scalar insertion, invalid division, unavailable SSA value or unsupported
operation still errors. Freeze does not bypass that error. The runtime uses
stack values and existing constant pools/result storage, adding no owned
array, cache entry, host operation or valid-path allocation. Values remain
16 bytes; retained allocation was not measured.

`scalar_pair_freeze_test.v` checks 2,048 width/pattern/poison states, independent
field preservation and zero choices, idempotence, layout, scoped constants,
freeze-only undef, shape/type/metadata guards and runtime availability.

`tests/ios/air-pair-freeze.v self-test LLVM_AS FRESH_EXTERNAL_DIR` generates
fixtures in V and independently assembles/verifies them with LLVM. Raw-bit
MCJIT wrappers compare 524,288 exact defined/property results across 1,152
functions, including 32,768 edge results. Every width covers both fields,
defined construction, overflow calls, zero, partial poison, select, branch
PHIs and loops with zero through five iterations. Native arbitrary choices
are never compared with the local zero policy. Repeated extractions/XOR
and loops instead check properties valid for every choice. Defined neighbors
are independently checked against input bits and loop accumulation.

Interpreter controls cover zero choices for direct poison/undef, partial
poison, poisoned overflow calls and poisoned select conditions; exact budgets,
long-loop limits, integer API isolation, preceding errors, unsupported layouts
and constant records, malformed metadata in live/dead blocks and corrupted
outputs. Fixtures, bitcode, every comparison, assembler status and JIT identity
are saved outside Git. No AIR shader, iOS application or GPU command runs.
