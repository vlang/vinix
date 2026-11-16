# Checked-arithmetic buffer indices — 2026-11-16

Source revision: `98be0b0a3d5e5d1e92ea4feea8549dc5ad1de4fd`.

Pure buffer index graphs accept direct extractvalue fields from signed/unsigned
llvm.*.with.overflow add/subtract/multiply calls over i1..i64. Field zero is the
wrapped value; field one is the i1 overflow flag. Overflow itself is defined,
while poison in either input poisons either extracted field. Scalar select/
freeze may suppress or repair a poisoned field. Aggregate select/freeze/insert,
aggregate constants, loads and PHIs remain unsupported address dependencies.

The new POD node kind reuses existing fields and lowers a call plus extraction
to one scalar node. Both IR instructions count toward the depth limit, including
cached subtree heights through either operand. Extraction shape, literal pair
layout, field type, earlier direct-call identity and signature are checked.
Enclosing bounded declaration-attribute/duplicate checks remain shared. No owned
field or per-operation execution allocation is added. Private 256-node/32-level
bounds and cache/profile free paths remain. Generated C confirms fixed value/
poison stack arrays and a stack-local pair. Heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 1,382,400 cases cover 384 overloads, both fields, eight patterns and 15-by-15
  operand pairs: 798,529 exact outputs and 583,871 prewrite refusals. Native LLVM
  evaluates defined pure intrinsics; V checks model literal/computed poison and
  signed GEP bounds. Validation, ordinary and prepared APIs agree and preserve
  every byte on refusal. Cases cover direct/masked/zero-extended indices,
  non-power-of-two widths, poison in either input, computed operand wrap and
  scalar select/freeze. Interpreter padding is noisy; native words are canonical.
  No native poisoned memory operation executes.
- 6,912 controls cover both fields, both cached dependency depth boundaries
  (32 levels pass, 33 reject), cold poison roots, independent poison roots reused
  through freeze, and unsupported aggregate select/freeze/zero, loaded operands
  and undef dependencies. Poison-root validation/runs preserve all buffer bytes.
- Scalar overflow tests pass 524,280 exact wrapped-value/flag pairs against
  independent widened i1..i8 arithmetic, twelve i64 boundary cases, literal-pair
  layout checks and name/width/arity/evaluator guards.
- Thirty-two existing core programs pass, including all prior address matrices,
  overflow/pair-select/pair-insert memory tests, graph limits, aliases, cold
  checks and memory/layout/vector/intrinsic tests. Historical complete bundles
  and their checkers remain unchanged.
- Checked unsigned x-plus-zero supplies the image x channel and an overflow
  flag guarding its address. Four image sizes pass exact RGBA readback/padding
  in both hashing modes. Each mode reports 106 geometry dispatches, eight shader
  images, 93,962 checked invocations, 106 rejected pipelines and two prewrite
  bounds failures.

Evidence: `/Users/alex/Library/Caches/vinix-ios/overflow-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/overflow-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `04e04329db2b6c52c6d2f510696b7012ab78667fa8e6b6711dbf487d9224791c`.
- Inventory SHA-256: `36a84117ba4940565a812a016cbe8b618f8e9c6df6c610561b31e5f0dcf1b26a`.
- Source archive SHA-256: `fc47cae3b056741e23e6aa7380c9df4fff0fdd54b577cb0f70d3083e488eba50`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs are compared with the
feature commit. Reproduce with `tests/ios/air-memory-overflow-index.v LLVM_AS
FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`,
using repository module paths and retained toolchain. Dependencies remain
referenced; this is not hermetic. Native JIT is uninstrumented and leak detection
is disabled. CPU software Metal only is qualified; no broad runtime suite, native
GPU, guest launch or new Fortnite frame is verified.

Semantics follow the [LLVM language reference](https://llvm.org/docs/LangRef.html#arithmetic-with-overflow-intrinsics).
