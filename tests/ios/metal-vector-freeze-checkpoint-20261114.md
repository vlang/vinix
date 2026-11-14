# Software Metal vector freeze — 2026-11-14

`381c7cf0984f882f49d1cd327df52306da9036cb` adds `freeze` for fixed vectors
of 1..16 i1..i64/half/float lanes. Sources may be supported constants or
earlier insertion/shuffle/freeze results. Defined lanes retain exact bits;
each poison/undef lane independently becomes a fixed zero, a permitted choice
under [LLVM freeze semantics](https://llvm.org/docs/LangRef.html#freeze-instruction).
Every use of one dynamic result reads the same stored snapshot. Repeated
freezes are idempotent, older vectors retain their state, and frozen vectors
may feed insertion, shuffle, freeze and scalar extraction.

Integer, mixed scalar, void and memory APIs share validation/evaluation; the
integer API admits integer lanes only. Each vector freeze costs one executed
step and charges its full lane count against the shared million-lane
per-function budget. Insertions, shuffles and vector freezes together use at
most 4,096 static snapshot slots, reused on loop visits in the existing array
freed on every exit. Scalar and overflow-pair freezes retain their separate
paths. Source evaluation errors still stop execution; later operations can
introduce poison. Vector PHIs/selects, arguments/returns, loads/stores,
arithmetic, scalable vectors and other lane formats/counts remain unsupported.

ASan/UBSan checks pass:

- 278,528 independent lane-state checks cover widths i1..i64, all counts
  1..16, raw half/float patterns, defined neighbors, poison/undef/mixed
  choices, idempotence, immutable snapshots and count/scalar guards.
- 9,900 serialized shapes cover all 66 lane formats, counts 1/2/3/4/8/16,
  five constant forms and literal/computed/repeated/inserted/shuffled frozen
  snapshots: 15,708 unchanged native LLVM values, 34,452 permitted fixed-zero
  choices, 25,740 later poison failures preserving earlier writes, and
  151,800 scalar/integer API checks.
- 267,300 metadata/source, 1,716 indeterminate/snapshot/repeat/discard/loop/
  profile and 19,800 budget controls. Eight memory/void boundary checks admit
  exactly 4,096 combined constructions and 1,000,000 lane-work units, and
  reject 4,097 constructions or 1,000,016 lane-work units before execution.
- Shuffle and extraction regressions pass 83,226 and 76,560 native values,
  their poison/undef/scalar checks and remaining controls. Maintained guards
  that previously excluded vector freeze now check unsupported vector selects;
  historical archived checkers remain unchanged. All sixteen integer/scalar
  execution groups pass, including 1,397,052 narrow arithmetic-flag comparisons.
  Overflow-pair freeze passes 2,048 states and guards, insertion units pass
  65,280 lane states, and shuffle units pass 626,688 states and mask-tag guards.

LLVM verifies complete modules before native projection; retained
`native-input.bc` files contain only comparison functions. Only unchanged
defined selections compare with native LLVM. Fixed-zero choices use explicit
interpreter expectations; no assumption is made about LLVM's arbitrary
choices. Byte GEPs and align-1 accesses agree with the VM layout; MCJIT selects
a compatible host layout.

All 24 software Metal groups pass in both Swift hash modes. Deferred integer,
half and float kernels check repeated freezes, defined neighbors, poison/undef
zero choices, raw NaN/zero bits, snapshot preservation and insertion/shuffle
chains. Four failed commands preserve output: an undef insertion index before
freeze, a later out-of-range extraction, and reads of older poison/undef
snapshots. Pipeline creation rejects a seventeen-lane freeze. Both drained
runtimes pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-freeze-validation-20261114-r1.tar.zst`

The bundle retains binaries, fixtures/results, build receipts, compiler
snapshots, generated host C, LLVM headers, selected identities and `source.tar`
pinned to the feature revision. The host is
`software/NotificationChecks.app/Contents/MacOS/center-host`. An initial V
generator compilation failure is retained with its source and log; it did
not execute. All production qualification runs pass. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A completed fresh extraction replaced the bundle path. The maintained
`tests/packages/wine-workspace-archive.v` checker matches complete bytes, sizes,
types, modes and link targets, including the root; all 323 selected identities
match. All ten restored runs exit 0: three references, five unit binaries and
both 24-group host modes, using separate output roots. Full inventory, selected
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
| `.tar.zst` | `a542d064a933168ca4b92588c99efa21e4fa399eb4f2b1df7dbe9881f4ba06d0` |
| `.inventory.json` | `39f132d8f88986ea0f3661f352ed82703b60a79e70e0868eaaeac19e492c61c8` |
| `.replay.tar.zst` | `fa1c25ba347b029ddb63fe4383e4c70e1987df047044e14e6bb70947a7c57abe` |
| `.replay-inventory.json` | `bbf0243fedfed1d7fb811a294caa3c110e156bddbe78ac6762ebbad953bceb65` |
| `source.tar`, revision `381c7cf09` | `fdbeda0ce7c1df53e42e8675b8ef71f06b948e67bf6febf54ba4b09b5079cf9c` |
