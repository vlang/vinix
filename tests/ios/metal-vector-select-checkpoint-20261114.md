# Software Metal whole-vector selection — 2026-11-14

`cd97367c437d1cc8f95b8a76c538f990b014f3fb` adds whole-vector `select`
with a scalar i1 condition to the CPU AIR interpreter. Fixed vectors contain
1..16 i1..i64/half/float lanes. Constants and earlier insertion, shuffle,
freeze and select results may supply either arm. This follows LLVM's
[scalar-condition selection](https://llvm.org/docs/LangRef.html#select-instruction):
one condition chooses the entire vector, preserving exact lane bits and tags.
Poison conditions produce an entirely poison vector. Undef conditions reject
execution at the select, retaining the existing scalar interpreter policy;
the backend does not implement LLVM's arbitrary undef-condition choices.

Both arms receive full preflight validation, including unchosen and inactive
operands. Execution reads only the chosen arm; poison conditions read neither.
Earlier instructions still execute and may fail. Each dynamic result has an
immutable snapshot that can feed insertion, shuffle, freeze, select or scalar
extraction. Older results retain their state. Each select costs one executed
step and charges both source lane counts plus the result lane count against
the shared 1,000,000-lane validation budget. The existing snapshot array holds
at most 4,096 combined insertions/shuffles/freezes/selects, with fixed slots
reused on loop visits and the array freed on every exit.

Integer, mixed scalar, void and memory APIs share the implementation; the
integer API admits integer lanes only. Per-lane vector conditions, vector
PHIs, arguments/returns, loads/stores, arithmetic, scalable vectors, other
lane formats/counts and select fast-math flags remain unsupported.

ASan/UBSan checks pass:

- 26,112 independent lane-state checks cover all counts 1..16, both arms,
  condition bits, poison/undef mixtures, poison conditions, immutable
  snapshots and guards. A separate reader test uses unavailable unchosen
  arms and verifies poison conditions read neither arm.
- 9,900 serialized shapes cover all 66 lane formats, counts 1/2/3/4/8/16,
  five paired constant forms and selected/frozen/chained/inserted/shuffled
  snapshots: 40,524 defined native LLVM values, 25,740 permitted frozen zero
  choices, 79,068 poison failures and 6,468 undef failures preserving earlier
  writes, plus 303,600 scalar/integer API checks.
- 237,600 metadata/source, 1,848 indeterminate/lazy-arm/snapshot/discard/loop/
  profile and 19,800 budget controls pass. Eight memory/void boundary checks
  admit exactly 4,096 combined constructions or 1,000,000 lane-work units,
  and reject 4,097 constructions or 1,000,016 work units before execution.
- Freeze, shuffle and extraction regressions pass 15,708, 83,226 and 76,560
  defined native LLVM comparisons, respectively, and their remaining controls.
  All 16 integer execution groups, both overflow-pair flow groups, 278,528
  freeze lane-state checks and 626,688 shuffle lane-state checks pass.
  Maintained exclusions now exercise unsupported per-lane vector conditions;
  historical archived checkers remain unchanged.

LLVM verifies complete modules before the native comparison projection.
Retained `native-input.bc` files contain only comparison functions. Defined
values compare with native LLVM; frozen zero choices use explicit interpreter
expectations. Native indeterminate results are not compared. Align-1 accesses
and byte GEPs agree with VM layout; MCJIT selects a compatible host layout.

All 24 software Metal groups pass in both Swift hash modes. Deferred integer,
half and float dispatches cover both arms, frozen scalar conditions, poisoned
conditions, preserved older snapshots, insertion/shuffle chains, raw NaN and
signed-zero bits, and input mutation after encoding. Eight dispatch samples
succeed. Five failures check write ordering: four fail before any write;
one poison-condition chain writes a defined frozen value before a later
poison store fails. Pipeline creation rejects per-lane conditions. Both
drained runtimes pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-select-validation-20261114-r1.tar.zst`

The bundle retains binaries, fixtures/results, build receipts, compiler
snapshots, generated host C, LLVM headers, selected identities and `source.tar`
pinned to the feature revision. Its host is
`software/NotificationChecks.app/Contents/MacOS/center-host`. The preliminary
select unit run is retained; the final unit adds direct lazy-reader checks.
Decode with `zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A completed fresh extraction replaced the bundle path. The maintained
`tests/packages/wine-workspace-archive.v` checker matches complete bytes, sizes,
types, modes and link targets, including the root; all 462 selected identities
match. All eleven restored runs exit 0: four references, five unit binaries
and both 24-group host modes, using separate output roots. Full inventory,
selected identities and archive checksum match after replay. A fresh replay
archive extraction also matches its complete inventory. Original expanded
trees remain.

Standalone compiler capture followed builds; the harness captured its separate
toolchain before generation. SDKs, assembler, external library symlinks and
dylibs remain unsealed prerequisites. Native MCJIT code is not sanitizer
instrumented. Leak detection is disabled; retained heap was not measured.
The ordinary runner was not rebuilt. These checks exercise synthetic LLVM
fixtures on the CPU. No Apple-produced shader, GPU rendering, presentation,
Vinix guest, Fortnite frame or launch gate is newly verified. Integrity checks
do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` | `9af4671ee51debfaa82df39dcce1ff9f8f78cb5c10b444a599f77517e848bb22` |
| `.inventory.json` | `9544050438f9d89bb7a311b7157d5a109650a3a686b812d917db32db4453494b` |
| `.replay.tar.zst` | `c084e0f2dd08fd6dcc569380d6bdee76f3f70de9e7364ce25104e1bc9b8503eb` |
| `.replay-inventory.json` | `286ac157eb5c1fea51eff30633a7f8aa5912928a0c418865f8f14c2b3b69f7b0` |
| `source.tar`, revision `cd97367c4` | `2b549a6da13a67fbeccc9fae34edac50011ce3820a168dc993e1fb8207eca5b6` |
