# Software Metal per-lane selection — 2026-11-14

`d095852aaec854f103e5627ddfda0de9d3a7a62f` adds fixed i1 vector conditions
to AIR vector `select`: each lane independently chooses its corresponding
arm, following [LLVM select semantics](https://llvm.org/docs/LangRef.html#select-instruction).
Vectors contain 1..16 i1..i64/half/float lanes. Constants and earlier
insertion/shuffle/freeze/select results may supply the condition or arms.
Preflight checks all three sources, including unchosen lanes and inactive
blocks. Runtime reads an arm only if some defined condition lane chooses it;
all-poison conditions read neither arm. Chosen bits and poison/undef tags
are copied exactly into an independent snapshot.

Poison conditions affect only their own result lanes. Any undef condition
lane rejects at select, including discarded results; this is a bounded policy,
not LLVM's arbitrary undef-condition choice semantics. Freezing the condition
first independently chooses zero for poison/undef lanes. Earlier instructions
still execute and may fail. Existing scalar-conditioned selection is preserved.
Each select costs one step and charges condition + both arms + result lane
counts against the shared 1,000,000-lane preflight budget. It reuses the existing
4,096-construction snapshot limit and execution-owned array, with loop slot
reuse and cleanup on every exit. No new ownership field or per-lane allocation
is introduced. Vector PHIs, arguments, returns, loads/stores, arithmetic,
scalable vectors, other lane formats/counts and select flags remain unsupported.

ASan/UBSan qualification passes:

- 11,016 independent lane-state checks across counts 1..16, plus direct lazy
  reader checks, undef-condition/count/tag guards and snapshot preservation.
- 9,900 serialized shapes across all 66 lane formats, six lane counts, five
  paired constant forms and five result stages. Conditions pass through
  insertion, shuffle, freeze and whole-vector selection. Results pass through
  per-lane select, freeze, nested select, insertion and shuffle. The checker
  passes 34,716 defined native LLVM comparisons, 27,192 permitted
  freeze-dependent choices, 82,962 poison and 6,930 undef failures preserving
  earlier writes, and 303,600 scalar/integer API checks.
- 356,400 metadata/source, 1,848 profile/loop/discard/indeterminate and 19,800
  budget controls, plus 389 focused lane-condition controls. Eight memory/void
  boundary controls admit 4,096 combined constructions and 1,000,000 lane-work
  units, rejecting 4,097 constructions or 1,000,016 units before execution.
- Whole-vector select, freeze, shuffle and extraction regressions pass all
  native comparisons and remaining controls. Integer execution, overflow-pair
  flow, whole-vector select units and shuffle units pass. Obsolete per-lane
  exclusions now test seventeen-lane conditions; historical bundles are unchanged.

LLVM verifies complete modules before projecting native comparison functions.
Only fully defined selections execute natively. Freeze-dependent values and
indeterminate failures use explicit interpreter expectations. Byte GEPs and
align-1 accesses agree with VM layout; MCJIT selects a compatible host layout.

All 24 software Metal groups pass in both Swift hash modes. Sixteen new
deferred integer/half/float samples cover independent lane choices, high
condition bits, mixed poison, undef rejection, frozen conditions, older
snapshots, raw NaN/signed-zero bits and input changes after encoding. Ten
succeed; six fail. Four failures leave output untouched, while two preserve
one earlier integer store before a poison store fails. Both drained runtimes
pass; pipeline creation rejects seventeen-lane conditions.

Complete bundle and archive prefix:

`/Users/alex/Library/Caches/vinix-ios/air-vector-lane-select-validation-20261114-r1`

The `.tar.gz` archive retains binaries, generated fixtures/results/C, build
receipts, compiler snapshots, LLVM headers, 604 selected identities and a
`source.tar` pinned to the feature revision. Two failed reference attempts
retain their exact sources/binaries: an all-false boundary fixture selected
undef, then focused controls lacked explicit GEP layout. A failed host
generation due to variable shadowing and an evidence-helper compilation
failure are also retained. Final qualification runs all pass.

The maintained `tests/ios/swift-staging-archive.v` checker decodes every
logical archive byte and matches the complete named bundle root: paths,
file bytes/sizes, types, modes and link targets. Its corruption and sparse-file
selftests pass. All 604 selected identities match before and after twelve
in-place replay runs: five references, five unit binaries and both 24-group
host modes, each exiting 0 in separate output roots. The complete typed
inventory and archive/root comparison still match after replay. The replay
archive also matches its complete root and typed inventory. A fresh expanded
restore was not performed because disk space was limited. All original trees
remain; this qualification does not authorize deleting them.

Standalone compiler capture followed builds; the harness captured its separate
toolchain before generation. SDKs, assembler, external library symlinks and
dylibs remain unsealed prerequisites. Native JIT code is uninstrumented.
Leak detection is disabled; retained heap was not measured. The ordinary runner
was not rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU
rendering, presentation, Vinix guest, Fortnite frame or launch gate is newly
verified. Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.gz` | `7d46aa5b642681bfb0aa6a9bea25a8b3154fe6aceee9b52f96f8e153522607ee` |
| `.inventory.json` | `9413567f8f05608f0a366e468422af7548d0124ad294615166a07a9d6cc38f67` |
| `.replay.tar.gz` | `7e5fc3fe8fa1dc9ee1c038d53e243cb6a22f266163fa91fb37acf063f7f59595` |
| `.replay-inventory.json` | `20f0d881274625a96f300435677deaf259f54f50cc400cc99ce04c440f4f4abd` |
| `source.tar`, revision `d095852aa` | `ee210de2e5baf85ec7183adcb6cbf820de77d5621cfdf024369a0e6ccfc3643a` |
