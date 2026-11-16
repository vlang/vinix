# Inserted-pair buffer indices — 2026-11-16

Source revision: `ff1a8acc9fd24dc8d13034bdd00aa072b74d703c`.

Pure address graphs accept insertvalue into literal unpacked {iN,i1} pairs over
i1..i64. Field zero replaces data and field one replaces the overflow flag. Only
the replaced field receives the scalar replacement's value/poison; its neighbor
retains the base field. One or both fields of a poison pair can be repaired.
Insertions compose with select/freeze; freeze retains defined neighbors.
PHIs, loads and ordinary undef bases/replacements remain unsupported dependencies,
including ignored operands. Direct scalar/pair freeze can repair undef first.

The builder reuses the existing POD copy node and tagged field cache. Both the
base projection and replacement are validated/evaluated and count toward cached
height, even for overwritten/untouched fields. Copy left supplies value/poison;
right retains the other dependency without propagating its poison. Immediate
arithmetic errors still reject from ignored dependencies. Insert shape, literal
index and exact field/source/result types use the shared validator. Each insert
adds a node/level. No new node kind, owned field, map or evaluator allocation is
added. Shared 256-node/32-level bounds, fixed stack value/poison arrays, noslices
node storage and cache/profile free paths remain. Generated C confirms unchanged
evaluation and stack arrays. Heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 3,538,944 cases: 2,308,894 exact outputs and 1,230,050 prewrite refusals.
  Across 384 overloads and both fields, fifteen patterns use both conditions and
  12-by-12 operand pairs, with replacement data/flag derived from their XOR. They
  cover either replacement, literal/computed poison, partial/full repair, both
  overwrite orders, untouched neighbors, select/freeze, and direct/masked/wide
  indices. Included are 221,184 shared-field cases with both extraction orders.
  Native LLVM evaluates only defined calls/inserts; V models poison and signed
  bounds separately. Interpreter padding is noisy and native words are canonical.
  Validation, ordinary and prepared execution agree and preserve all bytes on
  refusal. No native poisoned memory operation executes.
- 11,520 controls cover cached depths through either base field/replacement
  (32 levels pass, 33 reject), exact 256/257-node limits, cold repaired/unrepaired
  roots, independent and cached poison roots, unsupported base/replacement
  operands, direct undef rejection, ignored divide-by-zero and frozen scalar
  undef repair. Both operands remain validated when only one supplies the field.
- Insert unit tests pass 2,048 width/pattern/poison states, both overwrite
  orders, field independence, masking and repair, plus shape/type/scope guards.
  Thirty-five existing core programs pass, including the direct-overflow, pair-
  select and pair-freeze address matrices. Their former insert rejection guards
  become pair-PHI guards; counts remain 6,912, 6,144 and 9,984. Original historical
  bundles and checkers remain retained unchanged.
- The image shader inserts both frozen fields into a poison pair before final
  extraction. Four image sizes pass exact RGBA readback/padding in both hashing
  modes. Each mode reports 106 geometry dispatches, eight shader images, 93,962
  checked invocations, 106 rejected pipelines and two prewrite bounds failures.

Evidence: `/Users/alex/Library/Caches/vinix-ios/pair-insert-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/pair-insert-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `195a8af991a3bdd46b19149552f41b27a1e59eccb83204db1b18ed4ded56e8e4`.
- Inventory SHA-256: `37b0e9d56c4ece15f383bbe21bd9dd807beea504b5f666b2452090e8af52f626`.
- Source archive SHA-256: `fcaf01bbc619a23e0e0c1fac9cc815256e4089a243f59c729a58200d3715df20`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs are compared with the
feature commit. Reproduce with `tests/ios/air-memory-pair-insert-index.v LLVM_AS
FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`,
using repository module paths and retained toolchain. Dependencies remain
referenced; this is not hermetic. Native JIT is uninstrumented and leak detection
is disabled. CPU software Metal only is qualified; no broad runtime suite, native
GPU, guest launch or new Fortnite frame is verified.

Semantics follow the [LLVM language reference](https://llvm.org/docs/LangRef.html#insertvalue-instruction).
