# Software Metal vector shuffles — 2026-11-14

`ec4672b6109fbd6b38490ed80d68f68882d587c6` adds `shufflevector` execution
for fixed vectors of 1..16 i1..i64/half/float lanes. Two same-type inputs may
be supported constants or earlier insertion/shuffle results. The fixed result
may independently contain 1..16 lanes. Constant i32 masks select across both
inputs, following [LLVM shuffle semantics](https://llvm.org/docs/LangRef.html#shufflevector-instruction).
Poison and legacy undef mask entries produce poison lanes. Selected source
undef remains undef until extraction. Defined scalar bits, per-lane state and
older snapshots survive permutations, duplication and length changes. Shuffle
results may feed further shuffles, insertions and scalar extractions.

Integer, mixed scalar, void and memory APIs share validation/evaluation; the
integer API admits integer lanes only. Each shuffle costs one executed step.
Both complete sources and the normalized mask's identity against its original
constant are checked in preflight, including unselected lanes and inactive
blocks. Defined negative integer indexes cannot impersonate poison sentinels.
Shuffle work charges both input counts and the output count against the
existing million-lane per-function budget. Insertions and shuffles together
use at most 4,096 static snapshot slots, reused on loop visits in one
execution-owned array freed on every exit. No new owned per-lane storage is
added. Vector PHIs/selects/freezes, arguments/returns, loads/stores, arithmetic,
scalable vectors and other lane formats/counts remain unsupported.

ASan/UBSan checks pass:

- 626,688 independent lane-state checks cover every input/output count 1..16,
  both sources, defined/poison/undef/mixed states, mask sentinels, immutable
  snapshots and count/range guards. Separate checks distinguish poison/legacy
  undef tags from negative integer mask indexes.
- 38,016 serialized shapes cover all 66 lane formats, input counts
  1/2/3/4/8/16, output counts 1/3/8/16, three source forms, four mask patterns,
  insertion/shuffle chains and old/new snapshots: 83,226 defined native LLVM
  comparisons, 247,830 poison and 11,088 undef failures preserving earlier
  writes, and 684,288 scalar/integer API checks.
- 760,320 metadata/mask, 1,716 indeterminate/repair/freeze/select/discard/loop/
  profile and 76,032 budget controls. Eight memory/void boundary checks admit
  exactly 4,096 combined constructions and 1,000,000 lane-work units, and
  reject 4,097 constructions or 1,000,016 lane-work units before execution.
- Insertion and constant-extraction regressions pass 314,754 and 76,560 native
  comparisons, their poison/undef/scalar checks and remaining controls. The
  obsolete shuffle exclusion now checks unsupported vector freeze; historical
  archived checkers remain unchanged. All sixteen integer/scalar execution
  groups pass, including 1,397,052 narrow arithmetic-flag comparisons.
  Insertion units pass 65,280 lane states, extraction units pass 1,351,680
  exact lane/index checks, and shuffle decoder checks pass their masks,
  scalable/forward/deferred handling, fourteen rejections and 75 mutations.

LLVM verifies complete modules before native projection. Retained
`native-input.bc` files contain only comparison functions. Only defined
selections execute natively; indeterminate states and freeze choices use
explicit interpreter expectations. Byte GEPs and align-1 accesses agree with
the VM layout; MCJIT selects a compatible host layout.

All 24 software Metal groups pass in both Swift hash modes. Deferred integer,
half and float kernels check both sources with distinct payloads, chained
length changes, snapshot independence, poison masks, undef repair, raw NaN/
zero bits, frozen poison and two failed commands preserving output. Pipeline
creation rejects a seventeen-lane shuffle. Both drained runtimes pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-shuffle-validation-20261114-r1.tar.zst`

The bundle retains binaries, fixtures/results, build receipts, compiler
snapshots, generated host C, LLVM headers, selected identities and `source.tar`
pinned to the feature revision. Qualification uses `shuffle-unit-final` and
`software-qualified/NotificationChecks.app/Contents/MacOS/center-host`.
Both failed preliminary hosts remain recorded. Their test expected a store
before an undef extraction that executes first; the expectation was corrected
without changing production semantics. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A completed fresh extraction replaced the bundle path. The maintained
`tests/packages/wine-workspace-archive.v` checker matches complete bytes, sizes,
types, modes and link targets, including the root; all 321 selected identities
match. All ten restored runs exit 0: three references, five unit binaries and
both 24-group host modes, using separate output roots. Full inventory, selected
identities and archive checksum match after replay. A fresh replay-archive
extraction also matches its complete inventory. Original expanded trees remain.

Standalone compiler capture followed builds; the harness captured separate
toolchains before generation. SDKs, assembler, external library symlinks and
dylibs remain unsealed prerequisites. Native MCJIT code is not sanitizer
instrumented. Leak detection is disabled; retained heap was not measured.
The ordinary runner was not rebuilt. This remains single-thread CPU execution
of synthetic LLVM fixtures. No Apple-produced shader, GPU rendering,
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` | `b75ef6ce3d8b0d964dbde1ed1fc2f1051c6ee87d86cb66767471398f9408d2b6` |
| `.inventory.json` | `e0bf62a8505fad8bd0119483086d303809468c302571e94b07e5954aef3f47ee` |
| `.replay.tar.zst` | `318b1b8b2785b9a108f1e12720045d04460418ed30f8265755df25cd7f32a1e1` |
| `.replay-inventory.json` | `594a99465054ffd02f1ffc7b3506bca0cc89612297a7c7d4598d14b852be1c69` |
| `source.tar`, revision `ec4672b61` | `17b5c44aca4719181ac2b4e414a1fb2ab980f81ec09280962d149e0335a9d883` |
