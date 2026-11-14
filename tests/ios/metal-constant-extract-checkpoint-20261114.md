# Software Metal constant-vector lane extraction — 2026-11-14

`5ee08cdc2e07d1d591996eae6b77067ca9f7c83c` adds scalar `extractelement`
from literal fixed vectors of 1..16 i1..i64/half/float lanes. Runtime i1..i64
indices are masked to their width and interpreted as unsigned, following
[LLVM extraction semantics](https://llvm.org/docs/LangRef.html#extractelement-instruction).
Defined selections preserve exact scalar bits, including NaN payloads and signed
zeros. Out-of-range or poison indices produce poison; undef indices error.
Only the selected lane is evaluated: selected poison propagates, selected undef
errors, and other indeterminate lanes do not affect a defined selection.
Out-of-range indices produce poison even for a whole undef vector.

Data, scalar splat, aggregate-lane, zero, poison and undef constants are
supported. Preflight validates every lane, including inactive blocks and
unselected expressions, with a separate per-function limit of 1,000,000 lanes
charged by full vector count per extraction. Vector arguments, computed/loaded
vectors, vector storage/arithmetic, scalable vectors, larger vectors and other
lane formats remain unsupported. Extraction costs one executed step and
adds no buffer access requirement. Existing constant pools are borrowed; no
owned vector value array or cached-profile field is added.

Integer, mixed scalar, void and memory execution share validation/evaluation.
The integer API accepts integer lanes only. Discarded poison is allowed in void
functions, but selected undef still errors even for unused results. Existing
scalar arithmetic/casts, select/freeze, PHIs, stores and budgets remain in force.

ASan/UBSan checks pass:

- 1,351,680 exact lane/index checks cover all supported lane formats, every
  count 1..16 and every i1..i64 index width, including high incoming bits,
  out-of-range poison, constant forms, lazy undef and preflight guards.
- 6,336 serialized shapes across all 66 lane formats, vector counts
  1/2/3/4/8/16, index widths 1/8/32/64 and four constant forms: 76,560 defined
  native LLVM comparisons, 124,410 poison-store and 1,782 selected-undef
  failures preserving earlier writes, and 405,504 scalar/integer API checks.
- 31,680 metadata, 902 indeterminate/profile/void and 12,672 budget controls.
  Unsupported expressions reject even when unselected; inactive oversized
  extractions reject before stores. Both memory and void whole-function
  fixtures reject 62,501 sixteen-lane extractions at the lane-work limit;
  the earlier memory marker is untouched.
- Regressions pass 210,112 ordinary-conversion and 104,882 bit/sign-promise
  native comparisons, 75,342 promise poison-store failures and their remaining
  scalar/guard controls. All sixteen integer/scalar execution and five constant
  decoding groups pass, including 1,397,052 narrow arithmetic-flag comparisons.

LLVM verifies complete modules before unsupported/control/scalar-only functions
are projected out of native compilation. Projected `native-input.bc` files are
retained. Native calls use only defined lanes and in-range indices; poison,
undef and freeze choices use explicit interpreter expectations. Byte GEPs and
align-1 accesses agree with the VM layout; MCJIT selects a compatible host layout.

All 24 software Metal groups pass in both Swift hash modes. Deferred lookup
kernels select integer, half and float lanes after input changes, preserve
signaling/quiet NaN payloads and signed zeros, freeze out-of-range poison and
fail two invalid-index commands without changing output. Pipeline creation
rejects a seventeen-lane extraction. Both drained runtimes pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-constant-extract-validation-20261114-r1.tar.zst`

The bundle retains binaries, fixtures/results, build receipts, compiler
snapshots, generated host C, LLVM headers, selected identities and `source.tar`
pinned to the feature revision. Preliminary unit-compilation and oversized
work-fixture record-limit failures remain recorded; decoder limits were not
relaxed. Qualification uses `extract-qualified-final` and matching results;
the host is `software/NotificationChecks.app/Contents/MacOS/center-host`.
Decode with `zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A completed fresh extraction replaced the bundle path. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matches complete bytes, sizes,
types, modes and link targets, including the root; selected identities match.
All eight restored runs exit 0: three references, three unit binaries and both
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
| Complete `.tar.zst` | `fe085bf4431a30c9a85984c58b8817302fdbd595d5feb085ffa41d59b2d7aad1` |
| `.inventory.json` | `5b00b09aa1a87f3281ff096a86326d1a568a3124db1223bebc027f9b1d1382f3` |
| `.replay.tar.zst` | `d8a1178892af62f7713941390ffcb35a22cc82784a5274ed34018a93738d051f` |
| `.replay-inventory.json` | `dfa3b2ed035718e3bbfeb62b1bdcb4684be1c2332bab45672fdeeda098ab4041` |
| `source.tar`, revision `5ee08cdc2` | `e3a7be04de6e0f9f06f88a95864af17d09fbd47ce612d78e1560e93863f33f9f` |
