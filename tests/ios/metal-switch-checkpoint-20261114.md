# Software Metal forward integer switches — 2026-11-14

`64a7d1a3e` adds integer `switch` to bounded AIR buffer kernels and opt-in
software Metal compute. Conditions are i1..i64; zero through 64 defined integer
literal cases must have exactly matching types and distinct values. Default
and case destinations must be distinct forward blocks. Source/type/literal
metadata, scalar word bounds and masked duplicate values are checked before
stores. A fixed 64-word table bounds duplicate validation; its work and PHI
predecessor searches are charged against the existing preflight work limit.

Execution tests cases in encoded order and charges one additional step per
comparison, stopping at a match. Empty switches still read their condition;
poison/undef conditions reject and earlier writes remain visible. Pipeline
budgets include every static instruction plus every switch's maximum case
comparisons, while returned steps count the actual path and comparisons.
The existing predecessor table also enforces distinct switch destinations and
exact PHI incoming sets. No numerical helper, value format or owned-array
layout changed. Loops, backward edges and dynamic buffer indexes remain excluded.

Normal and ASan/UBSan `tests/ios/air-memory-switch.v` runs each pass 286,400
exact native comparisons. Its 450 main functions cover every integer condition
width, scalar integer/half/float outputs, all six overflow-pair families, every
case/default path and PHIs. Extra references cover empty switches at every
width, all 256 i8 inputs through 64 cases and defaults, and nested switches.
Exact executed comparison costs and conservative budgets pass, including
197-step and 21-step bounds for the 64-case and nested fixtures. The interpreter
also receives high padding bits; native references receive canonical bytes.

All 10,343 metadata/literal/target/PHI/default-block, 1,786 type and 450
conservative-budget controls reject before an earlier store; restored
baselines pass. Another 512 poison/undef cases cover empty/nonempty switches
with/without earlier stores, retaining exactly those earlier writes. Sixty-four
frozen-poison conditions choose defined zero. A 65-case body rejects before
stores. Sanitized unit checks cover empty/64/65-case edges, the exact 2,080-unit
literal-validation work bound, literal kinds/widths/word ranges, zero and masked
duplicates. Guard functions are never executed natively; MCJIT uses
optimization level 2 with FastISel off and saves target/layout receipts.

Sanitized regressions pass 144,320 forward-control comparisons and all their
guards, 665,592 native overflow pairs, 531,192 independent widened checks,
122,736 defined pair-freeze comparisons and the existing controls. All 16
integer/mixed unit groups pass. All 24 software Metal groups pass with normal
and deterministic Swift hashing. Per runtime, seven deferred switch dispatches
check 21 exact u64 value/flag/tag words, all three cases, defaults, simultaneous
scalar/pair PHIs and an overflowing multiply. Existing branch dispatches,
offset snapshots, sentinels until commit, released caller handles and two-runtime
drainage pass. A valid 65-case kernel rejects during pipeline creation.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-switch-validation-20261114-r1.tar.zst`

The 198 MiB bundle contains binaries, build receipts, fixtures/results,
generated C, compiler snapshots, LLVM header, selected identities and source.tar
pinned to the feature revision. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`. Receipts and replay evidence
use the same prefix outside Git. Original expanded evidence is retained.

A fresh extraction replaced the original bundle path while retaining
`original-bundle`. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matched every file byte,
size, type, mode and link target, including the root; selected identity hashes
also match. All six restored suites pass: sanitized switch, forward-control
and overflow/freeze references, switch-profile units, integer/mixed units and
all 24 software Metal groups with normal hashing. The complete bundle inventory
and archive checksum still match after replay. The replay archive also matches
its own inventory after a fresh extraction; both replay trees remain.

The standalone compiler snapshot was saved after builds; the harness captured
its compiler before generation. External SDKs, assembler, library symlinks and
dylibs remain unsealed prerequisites. Native MCJIT code is not sanitizer
instrumented. Leak detection is disabled; retained heap was not measured.
The ordinary runner was not rebuilt. This remains single-thread CPU execution
of synthetic valid LLVM fixtures. No Apple-produced shader, GPU rendering,
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `9f9f1239b078bb26417f1ac1081411bb193244cfa43f07e18f5103fb91e3dca5` |
| `.inventory.json` | `d7c74cfdd74a4510736362691571fb31b5c42cb8933e37f65b5cdf59868749f8` |
| `.replay.tar.zst` | `89b6d64ccb6287d2887e96113c25cbaa71175a752e9ae578740bffa8ea2c1cc5` |
| `.replay-inventory.json` | `4b8ccdd946c9552ee4fe23bdff07cc816c9fa5b8a4edce7feb719714377ef562` |
| `source.tar`, revision `64a7d1a3e` | `73c7730d4db22d493ef7835ffe98ce32738b907b147134c82be3de745ec1df65` |
