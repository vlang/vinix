# Frozen-pair buffer indices — 2026-11-16

Source revision: `8684297ea896f818733baad7adb8d26ef5519cc5`.

Pure buffer address graphs accept fields extracted from frozen checked-arithmetic
pairs over i1..i64, including nested pair select/freeze graphs and direct frozen
zero/poison/undef constants. Defined fields survive; poison fields and direct
undef use the interpreter's stable zero choice. Ordinary undef dependencies
remain unsupported. Cached constants retain original poison, so freezing one
use cannot repair another unfrozen use. Insertvalue, loaded dependencies and
PHIs remain unsupported address inputs.

The builder reuses the existing POD freeze node and tagged field cache. Freeze
adds one node/depth level; cached heights count normally. Direct undef admission
is checked before cache lookup and never passes recursively through a select.
No new owned field, map or evaluator allocation is added. Shared 256-node/
32-level limits, fixed value/poison stack arrays, noslices node storage and
cache/profile free paths remain. Generated C confirms stack arrays and numeric
cache storage. Heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 2,875,392 cases: 2,573,772 exact outputs and 301,620 bounds refusals. Across
  384 overloads and both fields, twelve patterns use both conditions and 12-by-12
  operand pairs. They cover defined/poisoned checked calls, frozen poison/direct
  undef/zero pairs, repeated freezes, select/freeze composition, poison conditions
  and direct/masked/zero-extended indices. Included are 221,184 shared-field
  cases extracting both fields in both orders. Native LLVM evaluates only defined
  calls and freezes; V checks the stable zero choice and signed bounds separately.
  Interpreter padding is noisy and native words are canonical. Validation, ordinary
  and prepared execution agree and preserve every byte on refusal. No native
  poisoned memory operation executes.
- 9,984 controls cover cached freeze chains and source branches/conditions
  (32 levels pass, 33 reject), exact 256/257-node limits, cold/independent poison
  roots, accepted cold frozen roots, cached unfrozen poison/undef rejection,
  undef selection after a frozen use and unsupported branches/conditions.
- Pair-freeze unit tests pass 2,048 width/pattern/poison states, independent
  field repair, defined neighbors and idempotence, plus shape/type/layout/scope/
  availability guards. Thirty-four existing core programs pass, including the
  full pair-select and direct-overflow address matrices. Former freeze rejection
  guards become insert controls; their counts remain 6,144 and 6,912. Original
  historical bundles and checkers remain retained unchanged.
- The image shader freezes its selected checked/poison pair before extracting
  either field. Four image sizes pass exact RGBA readback/padding in both hashing
  modes. Each mode reports 106 geometry dispatches, eight shader images, 93,962
  checked invocations, 106 rejected pipelines and two prewrite bounds failures.

Evidence: `/Users/alex/Library/Caches/vinix-ios/pair-freeze-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/pair-freeze-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `e39d9fe5d228f83124cd41fb69d5f6efaea19e05c1938056ac64bc617ae366dd`.
- Inventory SHA-256: `f83af74795c47184a6d8261a547d4839af2d49f55338bede1e25cb059afdd16d`.
- Source archive SHA-256: `af6a7e44ed0ff723a541c0d1de8725e64371fd346601ef0c55ec343566d128bb`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs are compared with the
feature commit. Reproduce with `tests/ios/air-memory-pair-freeze-index.v LLVM_AS
FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`,
using repository module paths and retained toolchain. Dependencies remain
referenced; this is not hermetic. Native JIT is uninstrumented and leak detection
is disabled. CPU software Metal only is qualified; no broad runtime suite, native
GPU, guest launch or new Fortnite frame is verified.

Semantics follow the [LLVM language reference](https://llvm.org/docs/LangRef.html#freeze-instruction); zero is this interpreter's fixed choice, not a required LLVM value.
