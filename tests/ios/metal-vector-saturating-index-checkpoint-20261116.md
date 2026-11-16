# Vector saturating arithmetic in buffer indices — 2026-11-16

Source revision: `19c2aac6348a2684f53720a6ebef6354d9b6399f`.

Pure buffer addresses now accept vector `llvm.sadd.sat`, `llvm.uadd.sat`,
`llvm.ssub.sat` and `llvm.usub.sat` across matching fixed 1..16-lane i1..i64
inputs. Signed overflow clamps to the appropriate signed endpoint; unsigned
addition clamps to the unsigned maximum and unsigned subtraction to zero.
Saturation itself yields defined values. Both source vectors compute before
extraction: undef in either remains an eager whole-vector error and poison
propagates lane-locally from either input. Source/result freezes and extraction
bounds retain their behavior.

The existing two-input intrinsic table handles these operations. Its admission
predicate expands, and its evaluator uses the scalar intrinsic dispatcher after
checking both undef/poison states. No node kind, array, owner, lifetime, free path
or graph-limit change is added. Generated C confirms existing fixed builder
arrays, POD second-parent indices and runtime arrays[256]. Limits remain
256 nodes/32 levels. Existing graph/cache growth and ordinary error allocations
remain; heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 489,216 address cases: 262,775 exact outputs and 226,441 prewrite refusals,
  including 91,728 with unrepaired undef. Every i1..i64 width uses count 3;
  widths 1/8/16/32/64 additionally cover all counts 1..16. All four operations,
  selector widths 1/32/64, eight operand pairs and four modes exercise arguments,
  constants, source freeze and result freeze. Masked, folded and unmasked
  widened indices check values and bounds. Validation, ordinary and prepared
  execution agree, preserving every output byte on refusal.
- 109,696 defined native LLVM lanes match independent checked signed-margin
  and two-limb unsigned-addition oracles. Native references substitute zero for
  indeterminate inputs; V separately models undef, poison and freeze. No native
  poison or invalid memory operation executes.
- Ninety-eight controls retain the earlier 88 bit/minmax cases for graph/cache
  boundaries, source states, composition and malformed calls/operands. Ten new
  cases check signed upper/lower clamps, unsigned carry/borrow, defined sums,
  mixed signs and differences. Their address folds observe upper and lower bits.
- Five focused unit suites pass. Vector saturation checks 2,820,096 independent
  values, 1,267,072 exhaustive narrow/wide-pattern pairs, 835,584 lane states and
  36,864 boundary pairs across all widths/counts and 4,096 overload identities.
  Scalar saturation checks 1,303,888 margin/carry comparisons. Existing vector
  extrema, abs and binary suites also pass.
- The full earlier min/max matrix passes 489,216 address cases and 109,696
  native/oracle lanes again. Computed-index, prepared-memory and scalar
  saturating-index programs pass; the latter checks 403,200 address cases.
  Earlier bit/zero/abs control modes pass 50/73/75 cases. Their full matrices,
  broader 43-program regression, full cast/compare/lane-mask/binary matrices
  and broad runtime suite were not repeated. Four older unsupported-call
  fixtures now use vector ushl.sat in place of admitted uadd.sat, preserving
  rejection assertions. Historical bundles/auditors remain untouched.
- Both image modes retain the two earlier kernels and add a saturation kernel.
  Four sizes per kernel check exact RGBA and all backing padding in fresh
  binaries/processes. All four clamps feed a bounded address root and the
  independently checked red channel. Each mode reports 106 geometry dispatches,
  24 images, 111,714 checked invocations, 106 rejected pipelines and two prewrite
  bounds failures. Both runtimes drain completely.

All execution checks passed their first runs. Executable source remained
unchanged after qualification began. Evidence focuses on changed dispatch and
shared binary/unary behavior without repeating large unrelated result sets.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-saturating-index-20261116-r1`.
Complete typed inventory: `/Users/alex/Library/Caches/vinix-ios/vector-saturating-index-20261116-r1.inventory.json`.
The original bundle matches its complete byte/metadata inventory again after
the archive attempt. Originals remain retained. Archive qualification and a
restoration replay are not claimed.

- Inventory SHA-256: `a322b202876cdcc749f79947261fd5f8b802644ebf3e6e8b4f61289f0dce18ff`.
- Source archive SHA-256: `0318da2573628cc98b3633b99bbf139cc35744368be07f233cb9483fe6763b19`.

Compression hit a full volume. The attempted `/Users/alex/Library/Caches/vinix-ios/vector-saturating-index-20261116-r1.tar.gz`
is truncated (`gzip -t` reports unexpected end of file) and remains unqualified.
Its earlier audit and failed sealing log remain untouched. The full original
bundle and inventory are the retained evidence; no result file was removed.
The partial archive SHA-256 is `8bce7aeadec4f372994ed171c3d2895d2429c82c0db1c970cd4f7aa23bfcbbed`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs match the feature commit.
Reproduce with `tests/ios/air-memory-vector-saturating-index.v LLVM_AS FRESH_EXTERNAL_DIR`
and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and the retained toolchain. Dependencies remain referenced; this is
not hermetic. Native JIT is uninstrumented and leak detection is disabled.
CPU software Metal only is qualified; no native GPU, guest launch or new Fortnite
frame is verified.

Subsequent archive recovery — 2026-11-16: after space became available, the
original bundle passed its unchanged complete inventory again. A fresh archive
`/Users/alex/Library/Caches/vinix-ios/vector-saturating-index-20261116-r1.recovered.tar.gz`
passes the full logical-byte/metadata comparison and original before/after
inventory checks. Archive SHA-256: `3f4fdcb82b5599cb3decd4c86e7400cd1c516e49e782649c0db8cc3ca5b46597`.
Archive inventory SHA-256: `3edb0e3661c71b0a1af52595c5991008af84f80aa91df3fc9e3183225f0b91fe`.
The successful audit is under `/Users/alex/Library/Caches/vinix-ios/vector-saturating-index-20261116-r1.recovered.tar.gz.audit`.
The earlier truncated archive, failed audit and original bundle remain retained.
This repairs archival preservation for source revision `19c2aac6348a2684f53720a6ebef6354d9b6399f`;
no execution checks or restoration replay were repeated, and launch qualification
is unchanged.
