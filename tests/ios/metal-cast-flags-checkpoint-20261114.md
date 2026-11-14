# Software Metal integer cast promises — 2026-11-14

`50361807ed1a227f82c3b1f1189c374500401c2c` adds `trunc nuw`, `trunc nsw`,
their combination, and `zext nneg` across i1..i64. Integer, mixed scalar,
void and memory execution share validation and the bounded unsigned evaluator.
Violations produce poison; casts still cost one step. Unknown/wrong-family
flags and flags on other casts remain unsupported. No owned runtime array or
cached-profile allocation is added.

The [LLVM truncation promises](https://llvm.org/docs/LangRef.html#trunc-to-instruction)
require unsigned/signed value preservation respectively. The
[extension promise](https://llvm.org/docs/LangRef.html#zext-to-instruction)
requires a nonnegative source, including interpreting i1 true as negative.
Poison inputs propagate; selected undef errors. Stores of poison reject,
while existing select/freeze operations may discard or resolve it.

ASan/UBSan validation passes:

- 7,959,050 independent range/value checks: exhaustive short-source
  truncations and extensions, all i1..i64 width pairs with boundary patterns,
  unchanged unflagged resizing, poison inputs and profile exclusions.
- All 8,064 flagged width/flag shapes in eight bounded LLVM modules:
  66,963 defined native comparisons, 191,085 poison-store failures preserving
  earlier writes, and 516,096 integer/mixed scalar API checks.
- 80,640 metadata, 16,128 budget and 72 poison/undef/freeze/select/chain/void
  controls. Memory metadata and short-budget failures precede marker stores.
- Regressions: 210,112 ordinary conversion and 76,116 address-space native
  comparisons; 131,072 defined widened LLVM arithmetic-flag comparisons
  (53,979 values, 77,093 poison-store failures), plus their guard controls.
  Sixteen integer/scalar execution and four scalar-intrinsic groups pass,
  including 1,397,052 narrow arithmetic-flag comparisons and 327,680
  square-root inequalities.

Native flagged casts execute only when the independent mathematical range
oracle says their promises hold. Invalid casts and freeze(poison) are never
used as native value oracles. LLVM verifies each complete module; retained
`native-input.bc` records the host target and cleared layout used by MCJIT.
Align-1 integer loads/stores and byte GEPs agree with the explicit VM layout.

All 24 software Metal groups pass in both Swift hash modes. Four synthetic
AIR kernels exercise flagged truncation/extension, deferred input changes,
freeze of poison and failed-command completion when poison reaches a store.
Both drained runtimes pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-cast-flags-validation-20261114-r1.tar.zst`

The archive retains final binaries, fixtures, results, build receipts,
compiler snapshots, generated host C, LLVM headers, selected identities and
`source.tar` pinned to the feature revision. Earlier compile/CLI, decoder-budget
and native-layout failures remain recorded. Qualification uses `cast-flags`
with `cast-flags-final-results`; the host is
`software/NotificationChecks.app/Contents/MacOS/center-host`.
Decode with `zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A completed fresh extraction replaced the bundle path. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matches complete bytes, sizes,
types, modes and link targets, including the root; selected identities match.
All nine restored runs exit 0: four references, three unit binaries and both
24-group host modes, with separate output roots. Full inventory, selected
identities and archive checksum match after replay. A fresh replay-archive
extraction also matches its complete inventory. Original expanded trees remain.

Standalone compiler capture followed builds; the harness captured its separate
toolchain before generation. SDKs, assembler, external library symlinks and
dylibs remain unsealed prerequisites. Native MCJIT code is not sanitizer
instrumented. Leak detection is disabled; retained heap was not measured.
The ordinary runner was not rebuilt. This remains single-thread CPU execution
of synthetic LLVM fixtures. No Apple-produced shader, GPU rendering,
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `5f1ab0eca835828c313260d040a38f68988f8f16966a9746cea9b11a9dbe906f` |
| `.inventory.json` | `4b4903d79ae3e83a1d0c30022b90f77d4c5a12721ed1ca4aea36f529df35c658` |
| `.replay.tar.zst` | `61b254938db5851a10871341298dee163bcf66ae70a251e14e2e0060a70bfa15` |
| `.replay-inventory.json` | `59fa410cd696c6f84169d49ad08d19e590f32c021b537bc4c374339995a21012` |
| `source.tar`, revision `50361807e` | `67d659ea8711770645eabbcd37a3b4b851bd58c4d56251184bb2cf75ed93584b` |
