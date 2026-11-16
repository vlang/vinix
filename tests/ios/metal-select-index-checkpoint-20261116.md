# Select buffer indices checkpoint — 2026-11-16

Source revision: `235a7784c47aa93971a005a15558ba0b854e2d15`.

Pure buffer address expressions accept scalar integer selects with an i1
condition and matching i1..i64 values. Literal poison may enter the graph;
ordinary operations propagate it, while select ignores an unchosen poisoned
value. Poisoned conditions/chosen values reject before writes. Each GEP remains
an independently checked root, including unused/cold GEPs and cached expressions
reused by a later select. Immediate arithmetic errors and the existing poison
division/remainder profile errors remain unmaskable even in unchosen values.
Undef, freeze, loads, PHIs and pointer/vector selects remain outside this profile.

New nodes add a condition child index and a root flag, without owned per-node
storage. All three dependency heights count toward the shared 32-level/256-node
limits. Evaluation uses fixed 256-word value and 256-bool poison stack arrays,
confirmed in captured generated C. Existing transient-cache and profile lifetime
paths remain. Retained heap is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 230,400 LLVM reference cases cover i1..i64, eight select patterns and both
  conditions: 108,696 native exact outputs and 121,704 prewrite refusals,
  including 72,192 selected/condition-poison cases. Literal/computed poison,
  nested suppression, wrap promises and samesign comparison conditions are
  covered. Validation, prepared and ordinary execution agree; refusals preserve
  all output bytes. Interpreter padding is noisy and native words canonical.
  The independent oracle uses defined values and explicit poison tags; native
  targets execute only after the oracle accepts a nonpoison bounded address.
- Twenty-eight targeted cases verify shared independent roots, one-past and
  larger bounds, cold poison, propagation through arithmetic/comparison/casts,
  poisoned conditions, root poison and unmaskable division errors. Cached select
  condition subtrees pass at 32 levels and reject at 33.
- Nineteen existing core programs pass, including arithmetic/bitwise/division/
  comparison index matrices, graph limits, aliases, casts, cold checks and
  memory/layout/vector/intrinsic tests. Previously unsupported select and literal
  poison controls now use unsupported intrinsic and poison-freeze dependencies;
  the eleven unsupported/depth/node guards remain. Historical bundles retain
  their original checkers.
- The image shader uses a samesign comparison to select its final address or
  poison. Four image sizes pass exact RGBA readback/padding checks in both hashing
  modes. Fresh processes of that executable also pass all nine focused runtime
  modes: builtins, grids, multidimensional grids, computed indices, sizes/images,
  group coordinates, indirect dispatch, geometry types and vector/prepared memory.

Evidence: `/Users/alex/Library/Caches/vinix-ios/select-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/select-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `eea552159db101f25600a3e035193539288b746a15be96d758d3ac50a8cede9f`.
- Inventory SHA-256: `1451d780f7cadc90cb8b669df8663d43955e4b33977cfe53ecc21055e47d8b71`.
- Source archive SHA-256: `5f4bc29630b7547c0278327165d418a6c2c3f51b3cdf8ff00c14e8334eeffb44`.

The bundle preserves all comparison rows, IR/bitcode, generated C, images,
binaries, commands/logs, tool identities, ownership review and source hashes
compared with the feature commit. Reproduce with
`tests/ios/air-memory-select-index.v LLVM_AS FRESH_EXTERNAL_DIR` and
`tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and the retained toolchain. Dependencies remain referenced; this
is not hermetic. LLVM JIT code is uninstrumented and leak detection is disabled.
This qualifies CPU software Metal only; no full broad runtime suite, native GPU,
guest launch or new Fortnite frame is verified.

The [LLVM language reference](https://llvm.org/docs/LangRef.html) and
[undefined behavior manual](https://llvm.org/docs/UndefinedBehavior.html) describe
select poison suppression and immediate undefined behavior.
