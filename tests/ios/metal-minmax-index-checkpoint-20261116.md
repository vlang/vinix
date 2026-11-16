# Integer min/max buffer indices — 2026-11-16

Source revision: `bf7f176215e5d70f2b72748b48e250f8d941e3d6`.

Pure buffer index graphs accept scalar llvm.smin/smax/umin/umax over i1..i64.
Both operand dependencies are validated, including cached subtree heights. Poison
in either input poisons the result even if the other value would win; existing
select/freeze support can suppress/repair it. Declaration identity, signature,
attribute and duplicate checks remain shared with ordinary execution. Other
intrinsic dependencies remain outside this profile.

The binary intrinsic kind reuses existing POD intrinsic/left/right/height fields
and evaluates with scalar_integer_extremum_value. Both child poison flags are
checked first. No owned field or execution allocation is added. Shared
256-node/32-level bounds, fixed stack value/poison arrays and cache/profile
free paths remain. Generated C confirms stack storage. Retained heap is
unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 403,200 cases cover 256 overloads, seven patterns and 15-by-15 boundary
  operand pairs: 241,856 exact outputs and 161,344 prewrite refusals. A native
  LLVM reference evaluates only defined inputs; separate V checks model literal
  and computed poison and signed bounds. Validation, ordinary and prepared APIs
  agree and preserve every byte on refusal. Cases cover direct/masked indices,
  poison on either side, computed right-hand wrap poison and select/freeze.
  Interpreter padding is noisy; native words are canonical. Cached depth chains
  through either operand pass at 32 levels and reject at 33, for every overload.
- Twenty-three existing core programs pass, including prior index matrices,
  graph limits, aliases, cold checks and memory/layout/vector/intrinsic tests.
  Unsupported smin dependencies become abs guards; all eleven guards remain.
  Complete historical bundles retain their original checkers.
- The image shader clamps addresses with signed maximum against zero and
  unsigned minimum against 16383. Four image sizes pass exact RGBA readback and
  padding in both hashing modes. Each mode reports 106 geometry dispatches,
  eight shader images, 93,962 checked invocations, 106 rejected pipelines and
  two prewrite bounds failures.

Evidence: `/Users/alex/Library/Caches/vinix-ios/minmax-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/minmax-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `64a73097f58f74de15482fdf454e15378ea1ceddac5b0e4f3795cb845cfa15a4`.
- Inventory SHA-256: `d900e4b71a5cb4d741601ce231a5c17bf1cf0f14f73c97da0a3891e844941fc3`.
- Source archive SHA-256: `de82bfd5a3bb50df246ef2f1872c7ebb54fb6db0e382a9dc5a02ef2430f8c729`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs are compared with the
feature commit. Reproduce with `tests/ios/air-memory-minmax-index.v LLVM_AS
FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`,
using repository module paths and retained toolchain. Dependencies remain
referenced; this is not hermetic. Native JIT is uninstrumented and leak detection
is disabled. CPU software Metal only is qualified; no broad runtime suite, native
GPU, guest launch or new Fortnite frame is verified.

Semantics follow the [LLVM language reference](https://llvm.org/docs/LangRef.html).
