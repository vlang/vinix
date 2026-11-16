# Integer vector bitcast reshaping — 2026-11-16

Source revision: `39117725c80f3766db091786fa16b3cdfb3f6933`.

Software Metal shader execution and pure buffer addresses now accept unflagged
integer vector bitcasts between 1..16-lane i1..i64 shapes with equal total bit
width. Lane zero supplies the lowest packed bits, without padding at non-byte
boundaries. Packing, splitting and crossing source boundaries preserve defined
bits. Every overlapping source lane contributes poison to its destination lane.
Undef is an eager whole-vector error; source freeze repairs inputs, result freeze
clears whole poison destination lanes, and invalid extraction remains checked.
Big-endian and floating reshaping, scalar/vector casts and pointer casts remain
excluded. Integer, mixed, void and memory APIs share construction slots,
source-plus-result work and ordinary step budgets.

Ordinary reconstruction uses bounded chunks and by-value fixed snapshots.
Address construction uses one fixed parents[16] array, existing scalar source
observation nodes and a new POD bitcast node kind in the unchanged node record.
All source observations run before results. Cached metadata retains maximum
height across every source lane; graph limits remain 256 nodes and 32 levels.
Generated C confirms fixed arrays, by-value records and unchanged runtime
values/poisons/undefs[256]. No managed array, owner, escaping pointer or free path
is added. Existing graph/cache growth and ordinary error allocations remain;
heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- All 3,468 supported shape pairs: 220,064 independent per-bit values and round
  trips, plus 272,324 poison-overlap/undef states. Inactive storage, malformed
  widths/counts/total widths, scalar tags, freeze and immutable snapshots pass.
- 399 integrated shapes cover every source width with source count 3 and all
  valid count pairs for widths 1/8/16/32/64. Eight patterns, four modes and
  selector widths 1/32/64 produce 370,656 address cases: 220,733 exact outputs
  and 149,923 prewrite refusals, including 46,332 unrepaired undef cases.
  Validation and ordinary/prepared execution agree and preserve every byte on
  refusal. Integer and mixed scalar APIs also check 741,312 results.
- 85,248 native LLVM lanes match a separate flattened-bit-stream oracle. The
  native reference uses a pointer-only ABI and defined replacements for source
  poison/undef. Original states, zero freeze choices and invalid selectors are
  modeled separately; native poison and invalid memory accesses never execute.
- 44 controls cover packing/splitting/crossing, poison isolation/overlap,
  source/result/scalar freezes, discarded results, immutable old snapshots,
  insertion/shuffle/arithmetic/select/mask composition, round trips, independent
  selectors, cold/unchosen undef, rejected loaded/PHI/floating dependencies,
  malformed operations and big-endian guards. Cached source chains straddle
  26/27 selects; 17 shared nodes plus 239/240 extractions straddle 256 nodes.
- Five unit suites pass: new integer bitcast, floating bitcast, integer casts,
  binary arithmetic and vector funnels. Computed-index and prepared-memory
  programs pass. The full earlier floating-bitcast checker passes 266,516 exact
  LLVM values and 557,744 scalar/integer checks; integer casts pass 283,192 exact
  LLVM values and 1,354,752 scalar/integer checks. Their shared work/storage
  limits pass. Earlier address cast/funnel/shift/compare control modes pass
  52/125/108/50 controls. Two old negative fixtures now reject unequal integer
  widths or floating reshaping instead of newly supported casts. Full earlier
  address matrices, broader 43-program regression, broad runtime and
  kernel/guest builds were not repeated.
- Both image modes retain five earlier kernels and add an integer packing and
  splitting kernel. It packs x/y bytes and distinct high bytes into i32, splits
  into i16 lanes, then dynamically extracts and folds a lane into both an
  address root and the red channel. Independent arithmetic expectations check
  all RGBA bytes and complete backing padding at four sizes in fresh binaries
  and processes. Each mode reports 106 geometry dispatches, 48 images, 138,342
  checked invocations, 106 rejected pipelines and two prewrite bounds failures.
  Both runtimes drain completely.

Development probe failures and their fixture/tool fixes are recorded in
`attempts.txt`; final qualification passed. A final EOF-only test cleanup was
followed by a fresh full matrix run with identical counts. Production source
remained unchanged during qualification.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-integer-bitcast-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/vector-integer-bitcast-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `5e0772e67057f74e1aa810f79eae96505104b42e91ad5ac922c47044e8e4c4da`.
- Inventory SHA-256: `dc21e0e3f12df803497d83435ff8f36e61a97f613f6a8be4d4d69657d0759a31`.
- Source archive SHA-256: `05b281f2107338668e4e6bc6570466cb2d92ebd4e97e9a72a6e52655db7d056f`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs match the feature commit.
Reproduce with `tests/ios/air-memory-vector-integer-bitcast-index.v LLVM_AS FRESH_EXTERNAL_DIR`
and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and retained tools. Dependencies remain referenced; this is not
hermetic. Native JIT is uninstrumented and leak detection is disabled. CPU
software Metal only is qualified; no native GPU, guest launch or new Fortnite
frame is verified.
