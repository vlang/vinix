# Software Metal vector comparisons — 2026-11-14

`32e264868fa0466a1c1e12ef0a150188b2be9905` adds vector `icmp` and `fcmp`
to the CPU AIR interpreter. Matching fixed vectors of 1..16 i1..i64/half/float
lanes produce i1 vectors. All ten integer predicates support per-lane
`samesign` poison; half/float support all sixteen ordered/unordered predicates
through the existing bit-based helpers. See [LLVM comparisons](https://llvm.org/docs/LangRef.html#icmp-instruction).

Sources may be supported constants or earlier insertion/shuffle/freeze/select/
comparison results. Preflight checks both complete sources, including inactive
blocks. Poison propagates per lane. Any undef input lane rejects at comparison,
even for a discarded result or extraction of a different lane. Constant FP
false/true predicates follow the existing scalar execution policy: defined
uniform masks without reading either source, after full preflight. Earlier
instructions still execute and may fail. This bounded policy does not model
arbitrary undef choices. Result snapshots may feed comparisons, per-lane
selection, freeze, insertion, shuffle and extraction. Old snapshots retain
their state. Each comparison costs one executed step and charges both source
counts plus result count against the shared 1,000,000-lane validation budget.
The existing 4,096-construction limit and execution-owned array include
comparison results; loop visits reuse static slots and all exits free the array.
No new ownership field or per-lane allocation is introduced. Vector PHIs,
arguments/returns, loads/stores, arithmetic, pointer comparisons, scalable or
other lane formats/counts, and floating comparison flags remain unsupported.

ASan/UBSan qualification passes:

- 2,088,960 independent integer lane comparisons cover i1..i64, all counts
  1..16, every predicate, `samesign`, raw-bit masking, localized poison and
  source snapshots. Another 43,520 half/float truth-table comparisons cover
  every predicate/count, both NaN classes, infinities, signed zeros and
  subnormals. Undef/count/type/flag guards and direct constant-predicate reader
  checks pass; ordinary predicates require available operands.
- 23,616 serialized shapes cover all 66 lane formats, six counts, integer
  predicates with/without `samesign`, and three result stages: raw mask,
  frozen mask and mask-selected data. All 112,098 defined native LLVM values,
  103,700 zero-mask freeze choices, 99,082 poison failures preserving earlier
  writes and 629,760 scalar/integer API checks pass. Frozen masks choose zero;
  selecting with those masks chooses the explicit false-arm value 11.
- 259,776 metadata/source, 47,232 budget and 550 focused controls pass,
  including undef on either operand, discarded results, source/result freezing,
  comparison results used by further comparisons, insertion/shuffle chains,
  unchanged older masks, constant predicates and unsupported profiles.
  Eight memory/void boundary checks admit 4,096 comparisons and exactly
  1,000,000 lane-work units; 4,097 constructions or 1,000,016 units reject
  before any output write.
- Per-lane/whole-vector select, freeze, shuffle and extraction references and
  their controls pass. Integer execution, scalar integer promise guards,
  overflow-pair flow and per-lane select units pass. Historical bundles and
  checkers remain unchanged.

LLVM verifies complete modules before projecting native comparison functions.
Only defined results execute natively. Frozen mask choices and indeterminate
failures use explicit interpreter expectations. Byte GEPs and align-1 accesses
match VM layout; MCJIT selects a compatible host layout.

All 24 software Metal groups pass in both Swift hash modes. Sixteen new deferred
integer/half/float samples exercise comparison masks selecting data, `samesign`,
localized poison, undef rejection, frozen masks, older masks, NaN/signed-zero
behavior, out-of-range extraction and input changes after encoding. Eleven
succeed; five fail. Three failures leave output untouched; two preserve an
earlier zero integer store before a poison store fails. Constant FP true masks
work with undef/poison operands. Floating comparison flags reject pipeline
creation. Both drained runtimes pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-compare-validation-20261114-r1.tar.zst`

The bundle retains binaries, generated fixtures/results/C, build receipts,
compiler snapshots, LLVM headers, selected identities and `source.tar` pinned
to the feature revision. An initial compilation misplaced a runtime branch in
preflight and failed before execution; its source/log remain. An early replay
build ran before its generated source existed and also did not execute.
The preliminary comparison unit has three groups; the final unit adds a direct
reader group. All final qualification runs pass. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A fresh extraction replaced the bundle path. The maintained
`tests/packages/wine-workspace-archive.v` checker matches complete bytes, sizes,
types, modes and link targets, including the root; all 744 selected identities
match. All thirteen restored runs exit 0: six references, five unit binaries
and both 24-group host modes, using separate output roots. Complete inventory,
selected identities and archive checksum match after replay. A fresh replay
archive extraction also matches its complete inventory. Original expanded
trees remain.

Standalone compiler capture followed builds; the harness captured its separate
toolchain before generation. SDKs, assembler, external library symlinks and
dylibs remain unsealed prerequisites. Native JIT code is uninstrumented.
Leak detection is disabled; retained heap was not measured. The ordinary runner
was not rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU
rendering, presentation, Vinix guest, Fortnite frame or launch gate is newly
verified. Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` | `227a19848d1d829ebf72c26540668f2b73a12b1ed4fa37564e22d9525b6d9255` |
| `.inventory.json` | `71ab01517088c2250ea3d07e6c0e6ffde3dc21b18b7546fb1ceaf9158318cb84` |
| `.replay.tar.zst` | `87ebb7945fa2c0fb08453f1344b69a270bf1a2de0e340a0285739d7b39a262a8` |
| `.replay-inventory.json` | `f900984b4ad6cadb758ecdf52d59a8e107e56c38d378d57374abc99e64b73e75` |
| `source.tar`, revision `32e264868` | `86bd8269877f1ba924199e8a037d2ddb4cb94cdc175d14ebd6aa8f029ab0eecd` |
