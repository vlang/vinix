# G17 register value and selector recovery

This host V module owns conservative integer-expression tracing, stack-spill
recovery, reaching definitions, narrow control-flow merges, selector collection,
and UUID-pinned inline register-record proofs. `Instruction.offset` and spill
byte ranges use `math.big.Integer`; register words remain AArch64 `u32` values.
The JSON compatibility entrypoint retains the remaining Python recovery callers.
It does not invoke Python or change a kernel/generated table.

`ImageSource` supplies symbol addresses and immutable code bytes synchronously.
Expression trees, visit histories and alternate CFG instruction streams are
copied before mutation and live under the host GC. Producer image addresses are
64-bit Mach-O addresses; loop indexes and register identifiers use native host
integers. Exact integer JSON tokens preserve offsets beyond those native widths.

The reused static-register decoder compares a wrapped branch target with a use
address. For arbitrary signed offsets, a rank adapter retains that exact ordering
around its `1 << 63` end-of-stream sentinel; ordinary image offsets use the direct
native path. The `rank_static_*` query cases exist for independent adapter tests
and are not routed through the production compatibility bridge.

The 30 original independent test bodies were frozen before translation. Their
instruction/code fixtures and complete original results are committed as data in
`fixtures/original-expressions.json`; native tests retain those checks and input
immutability assertions. Additional native cases cover arbitrary-precision
addresses, spill ranges, ordered branch comparisons and index diagnostics.

Run with the compiler selected by `build-support/find-v.sh`:

```sh
. build-support/find-v.sh
"$V" -cc clang test tools/agx-re/g17expr
```

Qualification also compares the unchanged original test bodies and thousands of
mutated instruction/image controls against native ARM64, actual x86-64 and
ASan/UBSan executables. Machine-local controls remain under
`~/.cache/vinix-python-to-v/g17-expression-20261008/`; the repository migration
record holds the durable evidence summary. These are host analysis checks;
physical Apple GPU behavior is outside this stage.

The command recovery extension owns record parsing maps, checked scatter copies,
normalized descriptor provenance, register-emission graphs and predicates,
command-pool geometry and reclamation, queue/device/runtime/scheduler inputs,
and the handoff/dual-role/RTBuddy transport contracts. Fixed instruction and
field maps are V literals; image reads, target validation, graph traversal and
metadata reconstruction execute in native V. Provider fixture addresses remain
arbitrary precision through comparisons. Checked binary reads preserve negative
relative offsets and index-overflow diagnostics; pool names use strict UTF-8.

The 35 original command tests are retained as independent byte fixtures and
complete results in `fixtures/original-commands.json`. Native tests also check
wide addresses, negative byte indexes, UTF-8 error spans and nonfinite metadata.
The compatibility adapter transports render metadata as JSON text so native
parsing preserves NaN/Infinity and Python's integer conversion errors. Its only
exception work is constructing the original built-in exception from native
error metadata. There is no Python analysis implementation behind these calls.

Command qualification is frozen under
`~/.cache/vinix-python-to-v/g17-command-20261008/`, with full original-body
replay, randomized/mutated full-output controls, actual-image comparisons,
ARM64 and x86-64 shared ABI checks and host sanitizer gates. Existing power
suites qualify the two visibility-only shared JSON/integer helper changes.
