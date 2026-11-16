# Inserted vector lanes in buffer indices — 2026-11-16

Source revision: `9cc609bb509f25194f9b0856ab5f27bd196265b5`.

Pure buffer address graphs now accept `insertelement` over integer vector
arguments, constants, freezes, scalar-condition selects and earlier insertions.
Vectors have 1..16 i1..i64 lanes. Replacement values and insertion indices use
the existing scalar expression rules. Valid insertion overwrites one lane and
preserves all others; a poison or unsigned out-of-range insertion index poisons
the entire new vector. A later valid insertion repairs its own lane. Literal
undef replacements remain deferred until the final extraction, and overwriting
an undef source lane repairs it. Vector freeze chooses stable zero for remaining
poison/undef, but cannot repair an invalid extraction selector. A later scalar
select/freeze cannot conceal an extracted-undef error. All dependencies validate
and evaluate, including inactive blocks and ignored source/replacement paths.
Undef insertion indices, immediate arithmetic errors, loaded/PHI dependencies,
vector conditions and unsupported constructions still reject before writes.

The new projection kind uses existing POD fields, selector-keyed cache and
fixed stack values/poisons/undefs arrays. Literal undef replacement shares the
scalar poison leaf internally, with a private insertion flag restoring undef
only for a selected replacement lane. Ordinary scalar undef checks still precede
cache lookup. No owned field/map/array is added; graph storage/free paths and
256-node/32-level limits remain. Source, replacement, insertion-index and
extraction-selector heights include cached subtrees. Generated C confirms
unsigned bounds/poison guards, by-value projection return and no added
successful-path allocation. Heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 5,069,120 cases: 2172130 exact outputs and 2896990 prewrite refusals,
  including 375386 selected-undef errors. All 64 lane and insertion-index
  widths, selector widths 1/32/64, lengths 1/2/3/16 plus every length at i32,
  eight lane patterns and ten expression patterns cover arguments/constants,
  poison/undef replacements and sources, lane repair, invalid insertion,
  insertion/select/freeze composition, signed/masked/widened addresses and noisy
  argument padding. An independent lane-state model and defined native LLVM
  insertion/select/freeze references check values; native inputs use zero for
  indeterminate lanes and explicit bounds guards. No invalid native extraction,
  insertion or poisoned memory operation executes. Validation, ordinary and
  prepared execution agree and preserve all bytes on refusal.
- Forty-one controls cover exact cached source/replacement/insertion-index/
  selector depths 32/33, exact 256/257-node limits, distinct selector cache keys,
  undef repair and scalar recovery limits, invalid indices and later repair,
  cold dependencies, independent roots in both orders, scalar undef cache
  isolation, unsupported dependencies and malformed insertion flags/arity/type.
- All 40 existing core programs and six vector unit suites pass. Four maintained
  constructed-source rejection fixtures now use unsupported shuffles because
  insertion is admitted; rejection assertions remain. Other core checks are
  unchanged. Historical retained bundles and auditors remain untouched.
- The image shader inserts a lane selected by y into an x-parity-selected
  permutation, then freezes it. Independent red-channel expectations observe
  both replaced and untouched lanes. Four image sizes pass exact RGBA/padding
  readback in both hashing modes, using fresh processes and freshly compiled
  binaries. Each mode reports 106 geometry dispatches, eight shader images,
  93,962 checked invocations, 106 rejected pipelines and two prewrite bounds
  failures.

The initial control smoke exposed a test depth-count error: its selector chain
omitted the extra source lane projection level. Corrected 28/29 operations to
27/28 for the exact 32/33-level boundary. The failed smoke is retained; no
production fix was needed. The subsequent controls and complete matrix passed.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-insert-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/vector-insert-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass.
Originals remain retained; no restoration replay is claimed.

- Archive SHA-256: `997a2e7e753e2d132c17c956c235cbc571e7bc4d69541350096cb44965c23a23`.
- Inventory SHA-256: `3016c354d5c7194b5b1993c699851442d75d62916bb3dd1f111682a9cfa6d071`.
- Source archive SHA-256: `77847d771aa942ed8f23da6771b83d8d6e6120ddb3dd971e895b8e79ec60a830`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs match the feature commit.
Reproduce with `tests/ios/air-memory-vector-insert-index.v LLVM_AS FRESH_EXTERNAL_DIR`
and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and the retained toolchain. Dependencies remain referenced; this
is not hermetic. Native JIT is uninstrumented and leak detection is disabled.
CPU software Metal only is qualified; no broad runtime suite, native GPU,
guest launch or new Fortnite frame is verified.
