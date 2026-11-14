# Software Metal integer-to-floating vectors — 2026-11-15

`5c714857f9c1e2a6abb4aab9aa9e242c929b8d16` adds unflagged `uitofp` and `sitofp` from i1..i64
to half/float for fixed AIR vectors of 1..16 lanes. Lane count is unchanged.
The existing integer-based scalar converters round nearest/ties-to-even,
independently of host rounding. Half overflow produces signed infinity;
signed i1 true converts to -1.

Complete sources must be supported literals or earlier constructions, including
in inactive blocks. Poison stays local; any undef source lane rejects the
executed cast, including discarded results. Source freezes repair indeterminate
lanes; result freezes do not suppress earlier errors. Independent snapshots
compose with existing vector operations. Dynamic errors preserve prior writes.

Each cast costs one step and source plus result lane work. The existing
1,000,000-lane budget, 4,096 static construction slots and execution-owned
array are reused; no ownership field or per-lane allocation is added. Mixed
scalar, void and memory APIs support the conversion; the integer-only API
rejects floating lanes. Floating-to-integer vector conversions, fast-math
flags, `uitofp nneg`, other formats, reshaping, vector arguments/returns,
PHIs and loads/stores remain unsupported.

ASan/UBSan qualification passes:

- 262,140 exact signed/unsigned i1..i16 float round trips check source masking
  and immutable snapshots. Known patterns cover signed i1, integer rounding
  ties, half overflow and i64 extremes. Another 417,792 lane-state checks
  cover every source width, format, sign and lane/count, including poison
  isolation, undef, freezing and shape/tag guards.
- 768 decoded shapes cover every source width, both signs, both destinations
  and 1/3/16 lanes. All 610,072 exact native LLVM comparisons pass, including
  524,280 exhaustive signed/unsigned i1..i16 samples and 80,928 wider
  rounding/boundary/random samples. There are 256 explicit frozen-zero choices,
  5,120 poison-store failures, 1,230,896 scalar/integer API checks, 7,680
  metadata/source rejections and 1,536 short-budget rejections.
- 590 focused controls cover literal/poison/undef sources, source/result
  freezing, discards, snapshots, composition, loop slot reuse, flags,
  unsupported profiles and independence from host rounding. Eight public
  memory/void boundaries admit exactly 4,096 constructions and 1,000,000
  lane-work units; exceeding either rejects before writes.
- Five unit and four LLVM reference regressions pass for shared cast dispatch,
  vector bitcasts/integer casts/precision casts, scalar half conversion,
  integer execution and vector floating arithmetic. Three maintained rejection
  fixtures now use unsupported `uitofp nneg` or vector `fptosi`, since their old
  unflagged integer-to-floating casts are supported. Historical bundles retain
  their original checkers and complete evidence.
- Both Swift hash modes pass all 24 software Metal groups, with two drained
  runtimes each. Each runtime checks 156 new deferred dispatches across 44
  kernels: 148 complete and eight fail as expected. Sparse bindings and writes
  after encoding, native LLVM expected bits, source/result freezes, old
  snapshots, raw bitcasts and composed operations are checked. Undef failures
  preserve the marker; poison failures also preserve a frozen-zero store.
  Flagged conversions reject during pipeline creation.

Only defined selections execute natively; no invalid native floating-to-integer
cast is used as an oracle. The first reference attempt supplied noncanonical
padding to native i1 loads and disagreed. Both failed attempts and their
fixtures/logs remain. Final native inputs have zero unused high bits; interpreter
padding masking is exercised separately. Numeric expected values come directly
from native LLVM; the host fixture retains 128 of those exact results.

The complete canonical workspace is retained in place:

`/Users/alex/Library/Caches/vinix-ios/air-vector-int-float-validation-20261115-r1`

It contains fixtures/results, binaries, generated host C and objects, toolchain
captures, commands, logs, helpers and `bundle/source.tar` pinned to the feature
revision. The receipt at the same path plus `.inventory.json` covers every
logical file byte, size, mode, directory/root mode and symlink target, with
source/tool hashes. Recording compares two complete inventories; a separate
`check-inventory` passes. The maintained checker is
`tests/packages/wine-workspace-archive.v`. Shared disk space was limited, so
no duplicate archive or restored replay was made. Original trees remain.

| Artifact | SHA-256 |
| --- | --- |
| Retained-workspace `.inventory.json` | `60f71666f3d34723bdde1af5606363eb6575b6e239a49ec4e04fa106728ff603` |
| `bundle/source.tar`, revision `5c714857f9c1e2a6abb4aab9aa9e242c929b8d16` | `26bea4b61eb33256d1fe870167a97df37bc568e721b9a68bd0785807a72369ad` |

The standalone compiler was captured after builds; the host compiler was
captured before generation. V libraries, SDKs, assembler, symlink targets and
dylibs remain external prerequisites. Native JIT code is uninstrumented. Leak
detection is disabled and retained heap was not measured. The ordinary runner
was not rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU
rendering/presentation, Vinix guest, Fortnite frame or launch gate is newly
verified. Inventory integrity does not replace historical launch auditors.
