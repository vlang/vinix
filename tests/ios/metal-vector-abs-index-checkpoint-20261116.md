# Vector absolute values in buffer indices — 2026-11-16

Source revision: `248cbe6ce9bfd4ae3855dc5ac5c608d78cee6e3c`.

Pure buffer addresses now accept vector `llvm.abs` across fixed 1..16-lane
i1..i64 operands. Each call requires an exact defined i1 minimum-poison flag.
False preserves the signed minimum bits; true yields lane-local poison for
that value. Other inputs yield magnitude bits. Source poison stays lane-local;
undef remains an eager whole-vector error before extraction, selection or result
freeze. Source freeze repairs indeterminate lanes to zero; result freeze may
repair minimum poison. Original extraction bounds and graph limits remain.

The existing intrinsic builder validates the call-local flag before table cache
lookup and copies it into each node's existing POD value word. The existing
evaluator dispatches abs to the scalar helper. Declaration, signature, identity,
attribute and immarg checks remain. Generated C confirms flag validation before
lookup, fixed parents[16], by-value records and fixed runtime arrays[256]. No
array, node kind, owner, lifetime or free path was added. Existing graph/cache
growth and ordinary error allocation remain; heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 244,608 address cases: 136,441 exact outputs and 108,167 prewrite refusals,
  including 30,576 with unrepaired undef. Every i1..i64 width uses count 3;
  widths 1/8/16/32/64 additionally cover all counts 1..16. Both flags, selector
  widths 1/32/64, eight operand patterns and four modes exercise arguments,
  constants, source freeze and result freeze. Masked, folded and unmasked
  widened indices check values and bounds. Validation, ordinary and prepared
  execution agree, preserving every output byte on refusal.
- 54,848 defined native LLVM abs lanes match an independent unsigned-subtraction
  magnitude oracle. Native references use false flags and substitute zero for
  indeterminate inputs. V separately models true-flag minimum poison, undef
  and freezes; native poison and invalid memory accesses never execute.
- Seventy-five controls retain fifty earlier bit-intrinsic cases for composition,
  eager errors, graph/cache limits and malformed calls. Twenty-five abs cases
  cover negative/minimum values, ignored minimum poison, both freezes, bounds,
  unrepaired undef, opposite flags on one declaration in both orders, shared
  selectors, mask consumers and dynamic/undef/poison/wrongly typed flag rejection.
- Eighteen unit suites pass. Vector abs checks 1,410,048 independent value/poison
  lanes, 655,424 exhaustive narrow/wide-pattern lanes and 208,896 lane-state
  checks across both flags, all widths/counts and overload/name/shape guards.
  Scalar abs checks 655,356 independent comparisons.
- The earlier bit-intrinsic matrix passes 298,176 address cases and 68,000
  native/oracle lanes; zero counts pass 489,216 cases and 109,696 lanes. Twelve
  focused core programs pass: computed/prepared/vector/execution, scalar
  bit/zero/abs indices, dynamic/constant lanes, vector freeze/select/shuffle.
  Cast control mode passes all 52 cases. The full 43-program regression and full
  cast/compare/lane-mask/binary matrices were not repeated. Earlier bit and
  zero-count checkers now reject unsupported vector smin in place of abs,
  preserving their assertions. Historical bundles and auditors remain untouched.
- Both image modes pass four sizes with exact RGBA/padding readback, fresh
  binaries and fresh processes. A separate bounded address root uses vector abs
  of negative x and signed minimum, both flags and result freeze. Its offset also
  changes the checked red channel. Each mode reports 106 geometry dispatches,
  eight shader images, 93,962 checked invocations, 106 rejected pipelines and
  two prewrite bounds failures. Graph limits remain 256 nodes/32 levels.

All execution checks passed their first executions. The initial evidence-finisher
helper failed compilation on fallible index calls in an assertion, before
execution or commit. Its source/diagnostic remain; the revised helper uses
nonfallible prefix inspection. Executable source remained unchanged after
qualification began. Modules are partitioned by width and lane count.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-abs-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/vector-abs-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `72e1689e5d9d4d5c535204cf95a443c30d9f520f96fff2e37d8e829388fbc031`.
- Inventory SHA-256: `96d57cc59f0104359cb8280171a18176a6061aa99410101fd9ac20540a0fc143`.
- Source archive SHA-256: `555881d03cfbde6902ebc5a1dbf563d72bc6d9794892997a760a6f8283a60e54`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs match the feature commit.
Reproduce with `tests/ios/air-memory-vector-abs-index.v LLVM_AS FRESH_EXTERNAL_DIR`
and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and the retained toolchain. Dependencies remain referenced; this is
not hermetic. Native JIT is uninstrumented and leak detection is disabled.
CPU software Metal only is qualified; no broad runtime suite, native GPU,
guest launch or new Fortnite frame is verified.
