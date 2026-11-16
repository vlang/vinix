# Vector saturating shifts in buffer indices — 2026-11-16

Source revision: `29fe35c126f4cbd2ceb6373691f20a7ef8918e5a`.

Pure buffer addresses now accept vector `llvm.sshl.sat` and `llvm.ushl.sat`
for matching fixed 1..16-lane i1..i64 values and amounts. Amounts are truncated
to that width and interpreted as unsigned. Counts below the width saturate
normally; counts at or above it yield lane-local poison, including shifts of
zero. Counts never reduce modulo the width. Source poison stays lane-local and
undef in either input remains eager. Source freeze repairs indeterminate inputs
but cannot repair a defined overshift. Result freeze or a scalar freeze after a
valid extraction may repair poison. Extraction bounds remain independent.

The existing two-input table admits the new IDs and dispatches them to the
poison-aware scalar shift helper before ordinary scalar dispatch. No node kind,
array, owner, lifetime, free path or graph-limit change is added. Generated C
confirms existing fixed builder arrays, POD second-parent indices, runtime
arrays[256] and poison-aware dispatch. Limits remain 256 nodes/32 levels.
Existing graph/cache growth and ordinary error allocation remain; heap retention
is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 244,608 address cases: 90,290 exact outputs and 154,318 prewrite refusals,
  including 45,864 with unrepaired undef. Every i1..i64 width uses count 3;
  widths 1/8/16/32/64 additionally cover every count 1..16. Both operations,
  selector widths 1/32/64, eight operand pairs and four modes exercise arguments,
  constants, source freeze and result freeze. Counts cover zero, one, width-1,
  width, width+1, two, 63 and all-one patterns after width truncation. Masked,
  folded and unmasked widened indices check values and bounds. Validation,
  ordinary and prepared execution agree and preserve all output bytes on refusal.
- 54,848 safe native LLVM lanes match independent checked-doubling oracles.
  Native references replace 22,946 overshift amounts with zero and substitute
  zero for indeterminate sources. V separately models the original poison,
  undef and freeze. No native poison or invalid memory operation executes.
- 108 controls retain 88 earlier bit/minmax cases for graph/cache boundaries,
  source states, composition and malformed calls/operands. Twenty new cases
  check signed/unsigned saturation, zero/selected/ignored overshifts, result
  and scalar freeze repair, ineffective source freeze, right undef/poison
  repair, eager errors, extraction bounds, shared counts and mask consumers.
- Seven focused unit suites pass. Vector shifts check 1,251,520 independent
  value/tag comparisons (232,928 poison) and 34,816 source-state positions.
  Scalar shifts check 651,944 comparisons (206,750 poison), including 18,432
  edge pairs. Existing saturation, scalar saturation, extrema, abs and binary
  suites also pass.
- The full earlier saturation matrix passes 489,216 address cases and 109,696
  native/oracle lanes again. Computed-index, prepared-memory and scalar
  saturating-shift-index programs pass; the latter checks 230,400 address cases.
  Earlier bit/zero/abs/minmax control modes pass 50/73/75/88 cases. Their full
  matrices, broader 43-program regression, full cast/compare/lane-mask/binary
  matrices and broad runtime suite were not repeated. Five unsupported-call
  fixtures now use vector fshl instead of admitted ushl.sat, preserving rejection
  assertions. Historical bundles and auditors remain untouched.
- Both image modes retain three earlier kernels and add a shift kernel. Four
  sizes per kernel check exact RGBA and backing padding in fresh binaries and
  processes. Signed/unsigned values and counts through x=63 feed a bounded
  address root and an independently checked red channel; i32 overshift poison
  freezes to zero for x>=32. Asymmetric folding distinguishes frozen overshift
  zero from saturated endpoints. Each mode reports 106 geometry dispatches,
  32 images, 120,590 checked invocations, 106 rejected pipelines and two prewrite
  bounds failures. Both runtimes drain completely.

All execution checks passed first. Executable source remained unchanged after
qualification began.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-satshift-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/vector-satshift-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `c434a7c0938a218c238d1e8c86ec4947e6bf32bb901f388993d307f81c0a5403`.
- Inventory SHA-256: `ef0eb45b14a9bd29ea1491d032807e2a315b5f85111a409f9ad674c5c9631fb0`.
- Source archive SHA-256: `d19c825ddd450d1207c6b7759ae7edd0e89a7eb20b39fdb54fa7661ff8c7c518`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs match the feature commit.
Reproduce with `tests/ios/air-memory-vector-saturating-shift-index.v LLVM_AS FRESH_EXTERNAL_DIR`
and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and retained tools. Dependencies remain referenced; this is not
hermetic. Native JIT is uninstrumented and leak detection is disabled. CPU
software Metal only is qualified; no native GPU, guest launch or new Fortnite
frame is verified.
