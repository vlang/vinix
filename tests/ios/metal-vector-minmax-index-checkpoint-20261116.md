# Vector min/max in buffer indices — 2026-11-16

Source revision: `92cf26dd793beae9a2e1884ab8064bbcbb12b00f`.

Pure buffer addresses now accept vector `llvm.smin`, `llvm.smax`, `llvm.umin`
and `llvm.umax` for matching fixed 1..16-lane i1..i64 inputs. Both sources
compute before extraction. Undef in either is an eager whole-vector error,
including ignored lanes, unchosen selects and cold blocks. Poison from either
input stays lane-local, even if a defined input would win a normal comparison.
Source freeze repairs indeterminate inputs; result freeze may repair poison
but cannot hide earlier undef errors. Original extraction bounds remain.

The existing intrinsic builder admits three lane counts of work (two inputs
plus the result) and uses one additional fixed 16-int stack array for right
projections. Each existing POD result node stores the second projection in its
right field; unary calls retain -1. Cached height includes both input graphs.
Generated C confirms fixed builder arrays, by-value records, both undef/poison
checks, scalar extremum dispatch and unchanged runtime arrays[256]. No node kind,
managed array, owner, lifetime or free path was added. Graph limits remain
256 nodes/32 levels. Existing graph/cache growth and ordinary error allocations
remain; heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 489,216 address cases: 267,678 exact outputs and 221,538 prewrite refusals,
  including 91,728 with unrepaired undef. Every i1..i64 width uses count 3;
  widths 1/8/16/32/64 additionally cover all counts 1..16. All four operations,
  selector widths 1/32/64, eight operand pairs and four modes exercise arguments,
  constants, source freeze and result freeze. Masked, folded and unmasked
  widened indices check values and bounds. Validation, ordinary and prepared
  execution agree, preserving every output byte on refusal.
- 109,696 defined native LLVM results match an independent comparison oracle
  that partitions negative/nonnegative patterns without the production sign-key
  flip or overflowing signed conversion. Native references substitute zero for
  indeterminate inputs; V separately models undef, poison and freeze. No native
  poison or invalid memory access executes.
- Eighty-eight controls include fifty earlier bit-intrinsic cases. Thirty-eight
  new cases check both cached input depth boundaries, selector depth and exact
  node limits (241 scalar extractions plus 15 shared nodes), two-input states,
  cold/unchosen errors, source/result freezes, composition, mask consumers,
  shared selectors and ten malformed call/operand mutations.
- Twenty unit suites pass. Vector extrema checks 2,820,096 independent values,
  1,267,072 exhaustive narrow/wide-pattern pairs and 835,584 lane-state cases
  across all widths/counts and all 4,096 overload/cache identities. Scalar extrema
  checks 1,267,024 independent comparisons.
- Earlier full matrices pass again: bit intrinsics 298,176 cases/68,000 native
  lanes, zero counts 489,216/109,696, and abs 244,608/54,848. Twelve focused core
  programs and all 52 cast controls pass. The full 43-program regression and full
  cast/compare/lane-mask/binary matrices were not repeated. Earlier bit/zero/abs
  unsupported-call fixtures now use vector uadd.sat instead of admitted smin;
  assertions and historical bundles/auditors remain intact.
- Both image modes retain the original image fixture and add a small min/max
  kernel. Four sizes per kernel check exact RGBA and all backing padding using
  fresh binaries/processes. Signed negative bounds and unsigned clamping feed
  a bounded address root and the independently checked red channel. Each mode
  reports 106 geometry dispatches, sixteen images, 102,838 checked invocations,
  106 rejected pipelines and two prewrite bounds failures.

The first combined image fixture exceeded the unchanged node limit; its pipeline
failure and direct `expression node limit` diagnostic remain. A duplicate run
after a helper compilation error captured that same oversized fixture and also
failed. Successful evidence is under `software-bits-separated`. Initial image
edit helpers also encountered a nonunique declaration guard and unescaped V
interpolation; their sources and summaries remain. AIR evaluator/builder code
stayed unchanged after execution qualification began; only the image fixture
was revised. The min/max matrix and focused regressions passed first execution.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-minmax-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/vector-minmax-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `e97cae2a773186b214656328210ec2b8667f28fc0c37df0f31705aa537bc5a7d`.
- Inventory SHA-256: `7a03a4cd9a6b969e8e6d7afda5a75a91de655109b5d802ff8ba044a8d9259401`.
- Source archive SHA-256: `6848f1301c0a4907a1d59b3c44ee8dc07f3afd0c2992625e89780208b53ab848`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs match the feature commit.
Reproduce with `tests/ios/air-memory-vector-minmax-index.v LLVM_AS FRESH_EXTERNAL_DIR`
and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and the retained toolchain. Dependencies remain referenced; this is
not hermetic. Native JIT is uninstrumented and leak detection is disabled.
CPU software Metal only is qualified; no broad runtime suite, native GPU,
guest launch or new Fortnite frame is verified.
