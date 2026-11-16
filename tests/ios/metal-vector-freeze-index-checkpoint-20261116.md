# Frozen vector lanes in buffer indices — 2026-11-16

Source revision: `ace5074524136add76f28923c7c4b5d9e16217d7`.

Pure buffer addresses now extract from earlier vector freezes over direct
arguments or supported literal vectors with 1..16 i1..i64 lanes. Repeated
freezes preserve defined bits and independently choose stable zero for poison/
undef lanes before extraction. They do not repair a poisoned or out-of-range
extraction selector; an outer scalar freeze may do so. Unfrozen consumers keep
the original lane states, including selected-undef errors, even when the same
constant table was previously used through a freeze. Other vector constructions,
PHIs, loads and memory-dependent selectors remain unsupported dependencies.

Argument leaves and each source freeze use POD metadata nodes in the existing
vector cache tag. Constant tables retain their original values/poison/undef
masks. Source and selector heights both count plus one extraction level,
including cached subtrees. Existing direct argument-lane costs are unchanged.
The evaluator handles metadata without lane reads and repairs selected constant
poison/undef only after unsigned selector checks. No owned field/map or runtime
array is added. Existing noslices storage, graph/cache frees, 256-node/32-level
limits and fixed value/poison arrays remain. Generated C confirms stack source
records and no added successful-path allocation. Heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 2,161,152 cases: 1,105,192 exact outputs and 1,055,960 prewrite refusals,
  including 25,332 unfrozen selected-undef errors. All 64 lane widths use
  lengths 1/2/3/16, and i32 additionally covers every length 1..16. Selector
  widths 1/32/64, eight lane states and eight expression patterns cover literal
  and argument sources, two/three freezes, preserved neighbors, scalar select/
  freeze recovery, invalid/poison selectors, frozen/unfrozen consumers, signed/
  widened/masked final addresses and noisy argument padding. Native LLVM
  evaluates defined frozen vectors with indeterminate lanes replaced by zero;
  V models the backend zero choice, original lane errors and address bounds.
  No native invalid extraction or poisoned memory operation executes. Validation,
  ordinary and prepared execution agree and preserve all bytes on refusal.
- Twenty-one controls cover exact cached source and selector depths 32/33,
  exact 256/257-node limits with shared frozen argument sources, independent
  poison/undef roots in both cache orders, cold repaired/unrepaired dependencies,
  selector poison surviving a source freeze, outer scalar recovery, unsupported
  loads/inserts/PHIs and malformed freeze flags/arity/result type.
- Existing units pass 278,528 vector-freeze states, 1,351,680 extraction
  checks, 65,280 insertion states and 107,520 constant-table checks, with their
  shape/type/cache guards. All 38 existing core programs pass unchanged, using
  three independent workers with distinct output paths. Historical evidence
  bundles and checkers remain unchanged.
- The image shader repeatedly freezes a permutation vector containing undef
  and freezes its direct gid argument. Stable zero preserves the expected
  z/x/y selection. Four image sizes pass exact RGBA and padding readback in
  both hashing modes. Each mode reports 106 geometry dispatches, eight shader
  images, 93,962 checked invocations, 106 rejected pipelines and two prewrite
  bounds failures, using fresh processes and freshly compiled binaries.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-freeze-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/vector-freeze-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `5093fc8e649c585fc2ca0b00b176dad003d5d840cfd0d5bafb8f587cd86f1a9a`.
- Inventory SHA-256: `fc0ae9b7a9e16a613f7b6215f57f7f13802c395f593f0a99310fbaa47174a46b`.
- Source archive SHA-256: `1bf5fbad03d06c87beb34bc66016a69c534e362077a6c2db18b41f249d20d7b7`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs are compared with the
feature commit. Reproduce with `tests/ios/air-memory-vector-freeze-index.v LLVM_AS
FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`,
using repository module paths and the retained toolchain. Dependencies remain
referenced; this is not hermetic. Native JIT is uninstrumented and leak detection
is disabled. CPU software Metal only is qualified; no broad runtime suite, native
GPU, guest launch or new Fortnite frame is verified.
