# Constant vector lanes in buffer indices — 2026-11-16

Source revision: `00ca5d70d44690b29368db83a8a3129f48968487`.

Pure buffer-address expressions now extract from supported literal integer
vectors with 1..16 i1..i64 lanes. Defined, data, aggregate, splat, zero, poison
and undef constants keep ordinary lane semantics. Unsigned width-masked selector
poison or range failure produces poison before any lane read. Scalar select/
freeze can recover poison; selecting undef is an immediate error even under
select/freeze and in a cold address dependency. Unselected undef/poison lanes
remain local. Constructed/loaded vectors and loaded selectors remain excluded.

Constant tables use contiguous existing scalar literal/poison leaf nodes. The
previously unused cache tag 3 identifies a table; full constant metadata is
validated before cache lookup. Every lane consumes a shared-budget node. The
first leaf retains an undef mask ignored by leaf evaluation and copied into
extraction nodes. Each extraction adds its selector height plus one level.
Literal lanes from direct arguments retain their prior single-leaf cost. No
owned field or map is added; existing graph/cache frees and noslices storage
remain. Generated C confirms bounds before narrowing, undef checks and fixed
array reads, with unchanged 256-node/32-level limits and value/poison stack
arrays. Successful constant selection adds no allocation; selected-undef errors
use ordinary error allocation. Heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 1,891,008 cases: 1,072,408 exact outputs and 818,600 prewrite refusals,
  including 210,998 selected-undef errors. All 64 lane widths use lengths
  1/2/3/16, and i32 additionally covers every length 1..16. Selector widths
  1/32/64, eight lane patterns, seven expression patterns and both conditions
  cover mixed poison/undef, unsigned indices, modular computed selectors,
  select/freeze recovery, literal lane zero, signed and widened final indices,
  and noisy argument padding. Defined native LLVM extracts supply the lane
  oracle; V models poison/undef and address bounds separately. No native invalid
  extraction or poisoned memory operation executes. Validation, ordinary and
  prepared execution agree and preserve all bytes on refusal.
- Nineteen controls cover shared tables, scalar/cache separation, exact
  256/257-node and cached 32/33-level boundaries, independent poison roots in
  both cache orders, cold defined/undef dependencies, undef under select/freeze,
  invalid/poison selectors into whole undef vectors, unsupported sources and
  malformed source type/identity.
- Focused table units pass 107,520 width/count/form/selector/freeze checks,
  including data/splat/zero/poison/undef, cache reuse and full metadata
  revalidation. Mixed aggregate state, exact table budget and cached unselected
  opaque lanes are checked separately. Existing vector suites pass 1,351,680
  extraction checks and 65,280 insertion checks. All 37 core programs pass;
  the dynamic-lane matrix replaces its former literal-vector exclusion with a
  loaded-vector exclusion, retaining 22 controls. Original bundles remain intact.
- The image shader uses <2,0,1> to permute its x-modulo-three lane selector.
  Independent red-channel readback observes z/x/y. Four image sizes pass exact
  RGBA and padding checks in both hashing modes. Each mode reports 106 geometry
  dispatches, eight shader images, 93,962 checked invocations, 106 rejected
  pipelines and two prewrite bounds failures, using fresh processes/binaries.

Evidence: `/Users/alex/Library/Caches/vinix-ios/constant-lane-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/constant-lane-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `f8a674dec4b2965d7b7627f00c0e173951e4f307cc416777d3b3eb426d2f1b96`.
- Inventory SHA-256: `afd4205821cbefd854955169eb3c9bdb3076b184efa1748c6cd50960cbcb1738`.
- Source archive SHA-256: `4081c30c1a89f238fd84626e236c66f144fe454132be073ec4c400dc9b38b3f5`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs are compared with the
feature commit. Reproduce with `tests/ios/air-memory-constant-lane-index.v LLVM_AS
FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`,
using repository module paths and the retained toolchain. Dependencies remain
referenced; this is not hermetic. Native JIT is uninstrumented and leak detection
is disabled. CPU software Metal only is qualified; no broad runtime suite, native
GPU, guest launch or new Fortnite frame is verified.
