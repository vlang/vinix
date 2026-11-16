# Saturating add/sub buffer indices — 2026-11-16

Source revision: `36d65629a8653d886af64dd64155c3fc4668e25f`.

Pure address graphs accept scalar llvm.sadd.sat/uadd.sat/ssub.sat/usub.sat
over i1..i64. Overflow clamps to signed/unsigned integer limits without itself
producing poison. Poison in either input still propagates and composes with
existing select/freeze handling. Both dependencies and their cached subtree
heights are checked. Declaration identity, signature, attribute and duplicate
checks remain shared with ordinary execution. Other intrinsic dependencies
remain outside this profile.

The POD binary intrinsic kind reuses existing child/height/id fields and calls
scalar_integer_saturating_value after checking both poison flags. No owned field
or execution allocation is added. Shared 256-node/32-level limits, fixed stack
value/poison arrays and cache/profile free paths remain. Generated C confirms
stack storage. Retained heap is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 403,200 cases cover 256 overloads, seven patterns and 15-by-15 boundary
  pairs: 222,578 exact outputs and 180,622 prewrite refusals. A native LLVM
  reference evaluates defined saturating operations; separate V checks model
  literal/computed poison and signed bounds. Validation, ordinary and prepared
  APIs agree and preserve every byte on refusal. Cases cover signed/unsigned
  limits, direct/masked indices, poison in either input, right-hand wrap poison
  and select/freeze. Interpreter padding is noisy; native words are canonical.
  For each overload, cached chains through either operand pass at 32 levels and
  reject at 33. No native poisoned memory operation executes.
- Twenty-five existing core programs pass, including prior index matrices,
  graph limits, aliases, cold checks and memory/layout/vector/intrinsic tests.
  Scalar saturation tests also pass 1,303,888 independent margin/carry comparisons,
  including exhaustive i1..i8 pairs and boundaries across i1..i64. Unsupported
  unsigned saturating-add dependencies become funnel-shift guards; all eleven
  guards remain. Historical complete bundles retain original checkers.
- The image shader uses unsigned saturating overflow/subtraction to form zero
  and signed saturating addition/subtraction to preserve its final address. Four
  image sizes pass exact RGBA readback/padding in both hashing modes. Each mode
  reports 106 geometry dispatches, eight shader images, 93,962 checked invocations,
  106 rejected pipelines and two prewrite bounds failures.

Evidence: `/Users/alex/Library/Caches/vinix-ios/saturating-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/saturating-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `cccdc31ecd38c8f3488998a831ab3b5d375e79e559f183e27dc383d791f664be`.
- Inventory SHA-256: `e8f6807d21f32cd0c0c731bf42ab27a632144556717dd445784170c34a499fb3`.
- Source archive SHA-256: `60c8690bc0405afe75e2033de57a7647a6774a4b91595ec9b0319356174d8751`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs are compared with the
feature commit. Reproduce with `tests/ios/air-memory-saturating-index.v LLVM_AS
FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`,
using repository module paths and retained toolchain. Dependencies remain
referenced; this is not hermetic. Native JIT is uninstrumented and leak detection
is disabled. CPU software Metal only is qualified; no broad runtime suite, native
GPU, guest launch or new Fortnite frame is verified.

Semantics follow the [LLVM language reference](https://llvm.org/docs/LangRef.html#saturation-arithmetic-intrinsics).
