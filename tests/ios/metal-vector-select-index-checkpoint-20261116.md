# Selected vector lanes in buffer indices — 2026-11-16

Source revision: `0668119129611f9295fb8dd2555742bbed3bfb52`.

Pure buffer addresses now extract from vector selects with a scalar i1
condition. Arms may contain direct integer vector arguments, supported constants,
freezes and nested selects, with 1..16 i1..i64 lanes. Only the chosen arm supplies
lane undef/poison. Chosen undef errors at the final extraction, even under a
later scalar select/freeze; a source vector freeze may repair it first. Poison
conditions produce poison lanes, dropping unchosen undef. Invalid extraction
selectors remain poison through source freezes. Both arms and conditions are
validated even when unchosen; immediate arithmetic errors remain unmaskable.
Vector conditions, loads, PHIs and other constructions remain excluded.

Private scalar lane projections defer undef until the final extraction. A
fixed 256-bool stack array stores tags; scalar consumers never receive them.
Source freeze repairs selected tags after unsigned selector checks. Cache keys
now reserve nine low bits: scalar/pair/source tags 0..3 and projection tags
4..259 keyed by selector node 0..255, disjoint within u64 for u32 value IDs.
All source/selector/condition heights count, including cached subtrees. Existing
freeze-only paths retain their representation and costs. No owned field/map or
runtime heap array is added. Existing noslices graph storage/free paths and
256-node/32-level limits remain. Generated C confirms stack projection records,
fixed arrays and no added successful-path allocation. Heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 2,701,440 cases: 1,291,364 exact outputs and 1,410,076 prewrite refusals,
  including 88,662 selected-undef errors. All 64 lane widths use lengths
  1/2/3/16, and i32 additionally covers every length 1..16. Selector widths
  1/32/64, eight lane patterns, ten expression patterns and both conditions
  cover argument/constant arms, lazy undef, nested selects, source and result
  freezes, poison conditions, frozen/unfrozen cache isolation, signed/masked/
  widened final addresses and noisy argument padding. Native LLVM executes
  defined vector selects/freezes, with indeterminate lanes replaced by zero;
  V models lane errors, poison, the backend zero choice and address bounds.
  No native invalid extraction or poisoned memory operation executes. Validation,
  ordinary and prepared execution agree and preserve all bytes on refusal.
- Twenty-nine controls cover exact cached source/freeze/selector depths
  32/33, exact 256/257-node limits, shared projections with distinct selectors,
  unselected and chosen undef, scalar recovery limits, source freeze and invalid
  selectors, poison/frozen conditions, independent roots in both cache orders,
  cold dependencies, unsupported arms/vector conditions, malformed select
  flags/arity/result type, and divide-by-zero in an ignored source condition.
- Six existing vector unit suites pass: 26,112 scalar-condition select
  states, 11,016 vector-condition select states, their lazy-read/shape guards,
  and the existing extraction, insertion, freeze and constant-table suites.
  All 39 existing core programs pass unchanged, using three independent workers
  with distinct output paths. Historical bundles/checkers remain unchanged.
- The image shader chooses between two different permutations using x
  parity, then freezes the selected vector. Independent red-channel readback
  observes both choices, including a repaired undef lane. Four image sizes
  pass exact RGBA/padding readback in both hashing modes. Each mode reports
  106 geometry dispatches, eight shader images, 93,962 checked invocations,
  106 rejected pipelines and two prewrite bounds failures, using fresh
  processes and freshly compiled binaries.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-select-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/vector-select-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `8fccc4067a8433abd36020e804d05035b8f553a335cb3a765b906475fec07398`.
- Inventory SHA-256: `f2779042a8b4f572f0d256cb9f53a17cef61016851ef739cad2d82498bbe33f8`.
- Source archive SHA-256: `0a98812bfc613d1500c34485a0a17c1c5ab41b34dce23176d541e2496a052f52`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs are compared with the
feature commit. Reproduce with `tests/ios/air-memory-vector-select-index.v LLVM_AS
FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`,
using repository module paths and the retained toolchain. Dependencies remain
referenced; this is not hermetic. Native JIT is uninstrumented and leak detection
is disabled. CPU software Metal only is qualified; no broad runtime suite, native
GPU, guest launch or new Fortnite frame is verified.
