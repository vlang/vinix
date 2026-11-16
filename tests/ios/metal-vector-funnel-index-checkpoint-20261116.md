# Vector funnel shifts in buffer indices — 2026-11-16

Source revision: `84a302d593205f766596b6f7d8090a16904d66ab`.

Pure buffer addresses now accept vector `llvm.fshl` and `llvm.fshr` across three
matching fixed 1..16-lane i1..i64 inputs. Amounts are width-truncated and reduced
modulo the lane width. Zero selects the left word for fshl and right word for
fshr. Poison in any source stays lane-local, including an otherwise unused
word at zero count. Undef in any source remains an eager whole-vector error
before extraction, unchosen selects or cold blocks. Source/result freezes retain
their recovery rules and extraction bounds.

The shared builder validates four lane counts of work and adds one fixed 16-int
stack array for third projections. Existing POD result condition fields hold
those indices; other intrinsic calls retain -1. Cached height includes all three
operands. The existing evaluator checks their states before scalar funnel
evaluation. Generated C confirms three fixed builder arrays, by-value records,
third indices/height and unchanged runtime arrays[256]. No node kind, managed
array, owner, lifetime extension or free path is added. Limits remain 256 nodes
and 32 levels. Existing graph/cache growth and ordinary error allocations remain;
heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 244,608 address cases: 133,466 exact outputs and 111,142 prewrite refusals,
  including 45,864 with unrepaired undef. Every i1..i64 width uses count 3;
  widths 1/8/16/32/64 additionally cover every count 1..16. Both directions,
  selector widths 1/32/64, eight operand triples and four modes exercise
  arguments, constants, source freeze and result freeze. Counts cover zero,
  one, width-1, width, width+1, two, 63 and all-one patterns after truncation.
  Masked, folded and unmasked widened indices check values and bounds. Validation,
  ordinary and prepared execution agree, preserving every output byte on refusal.
- 54,848 defined native LLVM lanes match independent per-bit selection oracles.
  Native references substitute zero for indeterminate sources; V separately
  models original poison, undef and freeze. Native poison and invalid memory
  operations never execute. Three input arrays use a pointer-only native ABI.
- 125 controls include 88 earlier bit/minmax cases. Thirty-seven additions
  check the third source's cached depth, exact 256-node boundary (18 shared
  nodes plus 238 scalar extractions), opposite zero-count words, whole/huge
  counts, third poison/undef/freeze, strict poison in unused zero-count words,
  result/scalar freeze repair, extraction bounds, cached selectors, composition,
  masks, cold/unchosen errors and eleven malformed call/operand mutations.
- Nine focused unit suites pass. Vector funnels check 1,410,048 independent
  values, 558,240 exhaustive narrow/wide-pattern triples and 626,688 source-state
  checks across all three inputs and 2,048 overload identities. Scalar funnels
  check 558,224 independent comparisons. Existing shift, scalar shift,
  saturation, scalar saturation, extrema, abs and binary suites also pass.
- The full earlier shift matrix passes 244,608 address cases and 54,848 safe
  native/oracle lanes again. Computed-index, prepared-memory and scalar
  funnel-index programs pass; the latter checks 983,040 cases. Earlier
  bit/zero/abs/minmax/saturation control modes pass 50/73/75/88/98 cases. Their
  full matrices, broader 43-program regression, full cast/compare/lane-mask/binary
  matrices and broad runtime suite were not repeated. Six unsupported-call
  fixtures now use vector saturating float-to-int conversion instead of fshl,
  preserving rejection assertions. Historical bundles/auditors remain untouched.
- Both image modes retain four earlier kernels and add a funnel kernel. Four
  sizes per kernel check exact RGBA and backing padding in fresh binaries and
  processes. Distinct words and counts 32..95 feed both directions into a bounded
  address root and independently checked red channel. Per-bit expectations
  distinguish opposite zero-count halves and modulo counts. Each mode reports
  106 geometry dispatches, 40 images, 129,466 checked invocations, 106 rejected
  pipelines and two prewrite bounds failures. Both runtimes drain completely.

All execution checks passed first. Executable source remained unchanged after
qualification began.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-funnel-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/vector-funnel-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `c0a812588372b53bd21684cda373147614fd4cf0adea79e75c24a942ed9d853b`.
- Inventory SHA-256: `e46818a1d7f421fd4cd930d72ee9ae06a4479b8817b6e97687f9ea23084f8673`.
- Source archive SHA-256: `b494112116b49460516111872b5292dc58e02b0d42d200d69a9b02de448cdd56`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs match the feature commit.
Reproduce with `tests/ios/air-memory-vector-funnel-index.v LLVM_AS FRESH_EXTERNAL_DIR`
and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and retained tools. Dependencies remain referenced; this is not
hermetic. Native JIT is uninstrumented and leak detection is disabled. CPU
software Metal only is qualified; no native GPU, guest launch or new Fortnite
frame is verified.
