# Funnel-shift buffer indices — 2026-11-16

Source revision: `b3bc1fa99b4b25630b4b0c42d805e2d09676b551`.

Pure buffer index graphs accept scalar llvm.fshl/fshr over i1..i64 with three
matching operands. The unsigned amount reduces modulo the integer width. At
zero effective shift, fshl chooses the left word and fshr the right word; equal
data words implement rotations. Poison in any input propagates under the
existing scalar profile, with select/freeze suppression or zero choice. All three
dependencies and their cached heights retain shared graph/declaration checks.

The POD funnel kind reuses existing left/right/condition indices, with condition
holding the amount dependency. The builder caches one plus the maximum of all
three subtree heights. Evaluation checks every poison flag before invoking
scalar_integer_funnel_value. No owned field or execution allocation is added.
Shared 256-node/32-level bounds, fixed value/poison stack arrays and cache/profile
free paths remain. Generated C confirms stack storage. Heap retention unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 983,040 cases cover 128 overloads, eight patterns, 8-by-8 data pairs and
  15 amounts: 434,949 exact outputs and 548,091 prewrite refusals. A native LLVM
  reference evaluates defined inputs; separate V checks model literal/computed
  poison and signed bounds. Validation, ordinary and prepared APIs agree and
  preserve every byte on refusal. Cases cover zero/modulo amounts, non-power-of-
  two widths, masks, poison in each input, computed amount wrap and select/freeze.
  Interpreter padding is noisy; native words are canonical. Cached chains through
  each of the three dependencies pass at 32 levels and reject at 33. No native
  poisoned memory operation executes.
- Scalar funnel tests pass 558,224 independent bit-concatenation comparisons,
  including exhaustive i1..i5 triples, rotation round trips, zero shifts and
  strict name/width/arity/evaluator guards.
- Twenty-seven existing core programs pass, including prior address matrices,
  graph limits, aliases, cold checks and memory/layout/vector/intrinsic tests.
  Unsupported funnel dependencies become carry-less multiplication guards; all
  eleven guards remain. Historical complete bundles retain original checkers.
- The image shader rotates its address left and right by 37. Four image sizes
  pass exact RGBA readback/padding in both hashing modes. Each mode reports
  106 geometry dispatches, eight shader images, 93,962 checked invocations,
  106 rejected pipelines and two prewrite bounds failures.

Evidence: `/Users/alex/Library/Caches/vinix-ios/funnel-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/funnel-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `ae241f1078a6c72f2c534873fb0c0123d75dc26d8cf7f51aafba7d18ed52fdaf`.
- Inventory SHA-256: `9dc8808ff5e19d1bc24dc5cea629559993b68a36ce9fa81ef1f120ac2693f6eb`.
- Source archive SHA-256: `1a11040517115817d90487626b76cf0be5743331a387e6db77b57b2fa656594f`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs are compared with the
feature commit. Reproduce with `tests/ios/air-memory-funnel-index.v LLVM_AS
FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`,
using repository module paths and retained toolchain. Dependencies remain
referenced; this is not hermetic. Native JIT is uninstrumented and leak detection
is disabled. CPU software Metal only is qualified; no broad runtime suite, native
GPU, guest launch or new Fortnite frame is verified.

Semantics follow the [LLVM language reference](https://llvm.org/docs/LangRef.html#llvm-fshl-intrinsic).
