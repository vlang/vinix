# Vector mask selects in buffer indices — 2026-11-16

Source revision: `b95890103964d66976b6d93318cb975473f5973b`.

Pure buffer addresses now accept vector selects with matching 1..16-lane i1
conditions and i1..i64 arms. Each condition lane selects its own arm's value,
poison and deferred undef. Poison conditions produce lane-local poison without
observing arm states. Chosen arm undef errors at extraction unless a vector
freeze repairs it first. Every condition lane must be defined: any mask undef
rejects before writes, including ignored lanes, invalid selectors, cold blocks,
later unchosen dependencies and result freezes. Source mask freeze may repair
indeterminate conditions first. Both arms and all immediate dependency errors
still validate. Existing pure comparison, cast, arithmetic, insertion, shuffle,
select and freeze sources compose. Loaded/PHI and floating dependencies reject.

A separate guarded condition table uses cache tag 260, outside source tags 0..3
and selector projections 4..259. Static selectors project every mask lane;
existing extraction guards reject deferred undef and preserve poison. Dynamic
reads feed the existing projected select evaluator. POD metadata retains the
table base and maximum lane height. All arm/condition/selector/result heights,
including cached subtrees, share the existing 256-node/32-level limits. One
fixed 16-int builder array holds parent indices. Generated C confirms stack
arrays/push records, by-value metadata and existing fixed runtime arrays.
No node kind, runtime array, owner or free path is added. Existing noslices
graph/cache growth and normal error allocation remain; heap retention is
unmeasured. Scalar-condition selects retain their earlier representation.

ASan/UBSan checks pass on macOS ARM64:

- 978,432 address cases: 622386 exact outputs and 356046 prewrite
  refusals, including 122304 checks with unrepaired condition undef.
  All i1..i64 widths use count 3; widths 1/8/16/32/64 additionally cover every
  count 1..16. Eight mask patterns, eight arm patterns and selector widths
  1/32/64 cover direct arguments, unfrozen constants, source freezes and result
  freeze. High/low-bit folding observes selected values, with i1 preserving its
  selected bit. Validation, ordinary and prepared execution agree, preserving
  every output byte on refusal. Argument/mask/selector padding is nonzero.
- 219,392 defined native LLVM selection lane results match an independent
  lane-choice oracle. Native references replace indeterminate lanes with zero;
  V separately models poison, undef and fixed-zero freezes. No native poison
  or invalid memory access executes.
- Fifty-four controls cover exact cached left/right arm, condition, selector
  and result-freeze depths 32/33 and 256/257 nodes; unchosen/chosen arm undef;
  ignored condition undef under result/scalar freeze, invalid selectors and
  unchosen selects; source repair; localized/all-poison masks; shared masks
  and distinct selectors; old/frozen consumers and independent roots in both
  orders; cold dependencies; insertion, shuffle, comparison, arithmetic, cast
  and nested mask composition; immediate source errors; unsupported sources
  and malformed flags/opcode/arity/indices/result types.
- The earlier comparison matrix passes again: 1,834,560 address cases,
  411,360 native/oracle lanes and fifty controls. All 43 earlier core programs,
  eleven unit suites and the earlier cast checker's 52-control mode pass.
  The cast checker's full matrix was not repeated. The scalar-select checker's
  former vector-condition rejection now uses an unsupported loaded mask, with
  rejection assertions retained. Historical bundles/auditors are unchanged.
- Both image modes pass four sizes with exact RGBA/padding readback, using
  fresh processes and freshly compiled binaries. The shader uses its comparison
  mask to select between two integer vectors. Independent red-channel expected
  values observe the changed permutation. Each mode reports 106 geometry
  dispatches, eight shader images, 93,962 checked invocations, 106 rejected
  pipelines and two prewrite bounds failures.

The 54-control smoke passed first. Before full qualification the checker gained
unfrozen constant cases and an i1 fold preserving the selected bit. The complete
new matrix/native-oracle checks passed their first run. No executable production
changes occurred after qualification began. Modules are partitioned by width
and lane count.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-lane-select-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/vector-lane-select-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass.
Originals remain retained; no restoration replay is claimed.

- Archive SHA-256: `21c8cb8b4565fc1d3bd0a895591dcd95d61971d4378325c4fee2fefd5a496ba4`.
- Inventory SHA-256: `6a34716f8aa739c5c5220052159881a8286ab5f26fc5747e0fb7571623948afc`.
- Source archive SHA-256: `36a464620d1900ba6e7b82c124ebae0f5fc63cc292d19136e41f5073174a7f42`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs match the feature commit.
Reproduce with `tests/ios/air-memory-vector-lane-select-index.v LLVM_AS FRESH_EXTERNAL_DIR`
and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and the retained toolchain. Dependencies remain referenced; this is
not hermetic. Native JIT is uninstrumented and leak detection is disabled.
CPU software Metal only is qualified; no broad runtime suite, native GPU,
guest launch or new Fortnite frame is verified.
