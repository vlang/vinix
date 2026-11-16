# Vector zero counts in buffer indices — 2026-11-16

Source revision: `c71faad178ba270feebefef45c4c19bccd3f06ee`.

Pure buffer addresses now accept vector `llvm.ctlz` and `llvm.cttz` across
fixed 1..16-lane i1..i64 operands. Each call requires an exact defined i1
`is_zero_poison` literal. False returns the width for zero; true produces
lane-local poison for zero. Source poison stays lane-local. Every source lane
computes before extraction, so undef rejects before writes even in ignored
lanes, invalid selectors, cold blocks and later unchosen selects/result freezes.
Source freeze repairs indeterminate inputs to zero, which may itself become
poison under a true flag. Result freeze may repair that poison. Original
extraction bounds and the existing pure integer composition rules remain.
Other unsupported vector intrinsic families and loaded/PHI/floating dependencies reject.

The existing intrinsic builder revalidates the call-local flag before cache
lookup and stores it in each result node's existing POD value word. The existing
evaluator dispatches zero counts to the validated scalar helper. Canonical
declarations, call identity, signatures, attributes, duplicate checks and the
second-parameter immarg policy remain. No array, node kind, owner, free path or
graph-limit change is added. Generated C confirms the flag read before lookup,
per-node flag storage, unchanged stack/runtime arrays and scalar zero-count
dispatch. Existing graph/cache growth and normal error allocation remain;
heap retention is unmeasured. Limits remain 256 nodes/32 levels.

ASan/UBSan checks pass on macOS ARM64:

- 489,216 address cases: 287560 exact outputs and 201656 prewrite
  refusals, including 61152 with unrepaired undef. Both operations and
  flags cover every i1..i64 width with count 3; widths 1/8/16/32/64 additionally
  cover every count 1..16. Selector widths 1/32/64, eight operand patterns and
  four modes cover arguments, unfrozen constants, source freeze and result
  freeze. Masked, high/low-bit-folded and unmasked widened indices exercise
  exact outputs and bounds. Validation, ordinary and prepared execution agree,
  preserving every output byte on refusal. Argument/selector padding is nonzero.
- 109,696 defined native LLVM count results match independent division-based
  oracles. Native references use false flags and replace indeterminate inputs
  with zero; V separately models true-flag zero poison, undef and freeze.
  No native poison or invalid memory operation executes.
- Seventy-three controls include the earlier fifty bit-intrinsic controls,
  retaining exact cached source/selector/result/nested depth and node boundaries,
  composition, eager errors and call-metadata guards. Twenty-three additional
  controls cover both zero-count flags, trailing/leading counts, ignored zero
  poison, source/result freezes, unrepaired undef, invalid selectors, opposite
  flags on the same declaration in both orders, shared selectors, mask consumers,
  and rejection of dynamic, undef, poison and wrongly typed flag operands.
- Sixteen unit suites pass. Each leading/trailing-zero suite checks 1,410,048
  independent value/poison lanes, 655,424 exhaustive narrow/wide-pattern lanes
  and 208,896 lane-state checks across both flags, all widths/counts, overload
  identities and name/type/flag guards.
- The earlier bit-intrinsic matrix passes again: 298,176 address cases,
  68,000 native/oracle comparisons and fifty controls. All 43 earlier core
  programs and the cast checker's 52-control mode pass; its full matrix was
  not repeated. The existing bit checker now uses unsupported vector abs
  for its former ctlz rejection, preserving assertions. Historical bundles and
  auditors remain unchanged.
- Both image modes pass four sizes with exact RGBA/padding readback, fresh
  binaries and processes. Parallel vector leading/trailing counts supply an
  unused bounded address root checked by preflight, and mix their sum into the
  red channel. At x=0, false ctlz returns 32 while true cttz poison freezes to
  zero. Independent expected values use integer division. Each mode reports
  106 geometry dispatches, eight shader images, 93,962 checked invocations,
  106 rejected pipelines and two prewrite bounds failures.

All 73 controls and the new full matrix passed their first executions.
The initial unit runner named nonexistent `vector_cttz_intrinsics_test.v`
after fifteen successful suites. Its failed build/status remain; a fresh runner
uses the repository's `vector_trailing_zero_intrinsics_test.v` and passes.
Executable production code remained unchanged after qualification began.
Modules are partitioned by width and lane count.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-zero-count-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/vector-zero-count-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass.
Originals remain retained; no restoration replay is claimed.

- Archive SHA-256: `adca5806b0e681e41e687b56c8e1930a392a3bf4af9ea93b13da9adb0cf0bcb8`.
- Inventory SHA-256: `2fd9de2a22fd86389e0bb4eebd2efdf6cf07eb37f26dac42983084e8941bc1a7`.
- Source archive SHA-256: `0c9646b0dd5f86fd11b913e95950c73d2558e1ca8c1d1f191b9958993d0fdee0`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs match the feature commit.
Reproduce with `tests/ios/air-memory-vector-zero-count-index.v LLVM_AS FRESH_EXTERNAL_DIR`
and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and the retained toolchain. Dependencies remain referenced; this is
not hermetic. Native JIT is uninstrumented and leak detection is disabled.
CPU software Metal only is qualified; no broad runtime suite, native GPU,
guest launch or new Fortnite frame is verified.
