# Software Metal bit/sign promises — 2026-11-14

`eb682031f58fdb8329803e73bd22264cb4ebfef1` adds `or disjoint` and
`icmp samesign` across scalar i1..i64 in integer, mixed scalar, void and
memory execution. OR produces poison when any input bit overlaps; otherwise
it returns ordinary bitwise OR. Comparisons produce poison for different sign
bits, including i1 0 versus 1; all ten predicates retain their normal results
for same-sign operands. These follow the LLVM
[OR](https://llvm.org/docs/LangRef.html#or-instruction) and
[comparison](https://llvm.org/docs/LangRef.html#icmp-instruction) promises.

Input poison propagates and selected undef errors. Existing freeze/select
operations may resolve/discard poison; poison stores and branch conditions
error, retaining earlier writes. Flags add no execution steps. Unknown and
wrong-family bits reject in preflight. Floating/pointer comparison flags
remain unsupported; precomputed pointer comparisons use the unchanged,
flag-free helper. No owned runtime array or profile field is added.

ASan/UBSan validation passes:

- 1,095,580 independent checks: exhaustive i1..i8 operand pairs plus all
  i1..i64 boundary/pattern pairs, every comparison predicate, narrow masking,
  unflagged results, poison inputs and flag/type/width/predicate guards.
- All 704 width/operation shapes in four bounded LLVM modules: 104,882
  defined native comparisons, 75,342 poison-store failures preserving marker
  writes, and 540,672 integer/mixed/void API checks with high argument bits.
- 2,840 poison/undef/freeze/select/branch controls, 5,640 unknown/noninteger
  flag controls and 1,408 short budgets. Preflight failures precede stores;
  poisoned branches retain prior writes; frozen/discarded poison follows the
  defined branch with exact executed-step counts.
- Regressions: 131,072 defined widened LLVM arithmetic-flag comparisons
  (53,979 values, 77,093 poison-store failures), 2,178 pointer-comparison
  native comparisons and 66,963 flagged-cast native comparisons with 191,085
  poison-store checks and their remaining scalar/guard controls. All sixteen
  integer/scalar execution groups pass, including 1,397,052 narrow
  arithmetic-flag comparisons.

The new checker verifies each complete LLVM module. An independent carry/sign
range oracle decides poison; only defined cases invoke native flagged
operations. Poison/undef and freeze choices are never native value oracles.
Retained `native-input.bc` files record the host target and cleared layout
used by MCJIT; byte GEPs and align-1 accesses agree with the explicit VM layout.

All 24 software Metal groups pass in both Swift hash modes. Four synthetic
AIR kernels check disjoint OR and same-sign comparison, changed inputs after
encoding, successful results, frozen poison and two failed commands preserving
their destination. Both drained runtimes pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-bit-sign-promises-validation-20261114-r1.tar.zst`

The bundle retains binaries, fixtures/results, build receipts, compiler
snapshots, generated host C, LLVM headers, selected identities and `source.tar`
pinned to the feature revision. Qualification uses `promises` and matching
results; the host is `software/NotificationChecks.app/Contents/MacOS/center-host`.
Decode with `zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A completed fresh extraction replaced the bundle path. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matches complete bytes, sizes,
types, modes and link targets, including the root; selected identities match.
All eight restored runs exit 0: four references, two unit binaries and both
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
| Complete `.tar.zst` | `aa7fba687d8ff215516a6512aa87796e8049e23ebdaf65f910f946dcd67d709d` |
| `.inventory.json` | `ef48a5381382a0ae5d068bcabad0c35466b08796a1977a13646c16fb2ac04750` |
| `.replay.tar.zst` | `d6df6a6bd97a4ca95acd23b90b387afeead3e3d94191ea276cd2bab473dec252` |
| `.replay-inventory.json` | `2db6b8ba5b1a9acfc424cfda4bb776584808c9fe4532d0730d62a592c00fc70c` |
| `source.tar`, revision `eb682031f` | `2c3feac5f23713569c83c154e856a278c4faae3db5663b7fef21374e936b8600` |
