# Bitwise buffer indices checkpoint — 2026-11-16

Source revision: `fd3b918b6b891739266a33d172fafbe38b7f6121`.

Pure buffer index expressions now admit shl/lshr/ashr and AND/OR/XOR on i1..i64,
including nuw/nsw left shifts, exact right shifts and disjoint OR. Existing
scalar evaluation provides modular values and poison semantics. Every required
node resolves before any AIR write. Invalid shifts/promises, negative final
indices and invalid addresses reject before writes. Division/remainder, loads,
PHIs, select/freeze and constructed vector dependencies remain outside the
address profile. Graph limits remain 256 shared nodes and 32 levels.

Only the builder admission predicate changes. Nodes, caches, fixed stack
evaluation storage and ownership/free paths are unchanged. Retained heap is
unmeasured. There is no new allocation or resource lifetime in execution.

ASan/UBSan checks pass on macOS ARM64:

- 172,800 comparisons across all i1..i64 widths, six new operators and twelve
  flag forms: 50,651 native exact outputs and 122,149 prewrite refusals, including
  84,582 cases tagged poison by a defined LLVM oracle. Validation alone, prepared
  and ordinary execution agree; rejected cases preserve the entire output.
  Noisy high padding bits in interpreter arguments are tested separately from
  canonical native words. The oracle selects safe shift amounts and checks
  promises with i128 arithmetic, reverse shifts or overlap tests. Flagged native
  targets execute only after the oracle accepts a bounded address.
- The existing 76,800 add/sub/mul index comparisons, 4,096 vector-coordinate
  cases, graph depth/node limits, cold bounds, aliases and cast/poison controls
  pass. The unsupported XOR control becomes unsupported remainder. Historical
  bundles keep the original checker. Fifteen other maintained memory/layout/
  switch/vector/intrinsic programs pass under sanitizers.
- The image kernel now forms pixel addresses with flagged left shifts and
  disjoint OR. Both hashing modes pass exact texture readback and padding checks
  for all image shapes. Fresh processes of the same executable pass the existing
  builtin, grid, multidimensional, computed-index, size/image, group-coordinate,
  indirect, geometry-type, vector-memory and prepared-reuse runtime modes.

Evidence: `/Users/alex/Library/Caches/vinix-ios/bitwise-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/bitwise-index-20261116-r1.tar.gz`.
Complete inventory and archive byte/metadata comparison pass. Originals remain
retained; no restoration replay is claimed.

- Archive SHA-256: `840fa0106b5197a93190e37081b0abf4f9f9cf571b43bb3ee6a086a8d9682e10`.
- Inventory SHA-256: `cd2686a065f49021be783dd79640fc7917ef0bb2e34e244c15f1b4ad4b1eed50`.
- Source archive SHA-256: `fa23a39ee6b66f1f86048517ed9b6527ce820ee63127dee815523b078c0422a7`.

The bundle retains comparisons, IR/bitcode, generated C, images, binaries,
commands/logs, source hashes compared with the feature commit, tool identities
and ownership review. Reproduce with `tests/ios/air-memory-bitwise-index.v LLVM_AS
FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`,
using repository module paths and the retained toolchain. Dependencies remain
referenced; this is not hermetic. LLVM JIT code is uninstrumented and leak
detection is disabled. No broad runtime suite, native GPU, guest launch or new
Fortnite frame is verified.

The [LLVM language reference](https://llvm.org/docs/LangRef.html) defines shift and bitwise flag semantics.
