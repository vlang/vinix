# Checked-pair select buffer indices — 2026-11-16

Source revision: `6428ff403e97352245953672480638cdbc0486e9`.

Pure buffer address graphs accept fields extracted from selects between
signed/unsigned checked add/subtract/multiply results over i1..i64, nested
pair selects and zero/poison literal pairs. A poison condition poisons either
selected field; poison in an unselected pair is suppressed. Both branches and
the condition are validated under existing declaration/type/profile rules.
Scalar select/freeze retains its existing behavior. Aggregate freeze/insert,
undef pairs, loaded dependencies and PHIs remain unsupported address inputs.

Pair fields are projected into scalar nodes. The existing transient cache now
uses u64 keys with distinct tags for ordinary scalar results and each pair
field, without collisions across u32 value ids. Every projected call/select/
constant and every extraction consumes a node/depth level. Cached subtree
heights include both branches and the condition. Calls plus extractions still
consume two levels; separate nodes can reach the 256-node limit sooner than
the former fused direct-call representation. The shared 256-node/32-level bounds,
noslices node storage and cache/profile free paths remain. No owned field or
execution allocation is added. Generated C confirms fixed stack value/poison
arrays and local node/key temporaries. Heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 2,875,392 cases: 1,698,660 exact outputs and 1,176,732 prewrite refusals.
  Across 384 overloads and both fields, twelve patterns use both conditions and
  12-by-12 operand pairs. They cover checked/zero/poison/nested pair selections,
  poisoned calls/conditions, computed condition wrap, scalar freeze and direct/
  masked/zero-extended indices. Another 221,184 cases within that total extract
  both shared fields in both orders and combine them into one checked index.
  Native LLVM evaluates defined calls/selects; V models poison and signed bounds.
  Interpreter padding is noisy and native words are canonical. Validation,
  ordinary and prepared execution agree and preserve every byte on refusal.
  No native poisoned memory operation executes.
- 6,144 controls cover cached depth through both branches and the condition
  (32 levels pass, 33 reject), exact 256/257-node limits for both fields, cold/
  independent poison roots and unsupported unselected branches/conditions.
- Pair-flow and pair-constant unit suites pass shape/type/scope/availability/
  layout checks, runtime tags and scalar/aggregate separation. Thirty-three
  existing core programs pass, including the full direct-overflow address matrix.
  Former pair-select/zero rejection cases become value/flag insert guards; the
  count remains 6,912. Complete historical bundles retain original checkers.
- The image shader selects its checked pair or a poison pair according to
  whether x is inside the grid before extracting either field. Four image sizes
  pass exact RGBA readback/padding in both hashing modes. Each mode reports
  106 geometry dispatches, eight shader images, 93,962 checked invocations,
  106 rejected pipelines and two prewrite bounds failures.

Evidence: `/Users/alex/Library/Caches/vinix-ios/pair-select-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/pair-select-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `c5dfe8346e37f9fbb8c87b41d26d615d536b6925ada4db03c1492b91da04e50d`.
- Inventory SHA-256: `9abaea4bb2a505cb73784a1bb8495c05cfe43c995fd3c71e4d1e493027b6d257`.
- Source archive SHA-256: `8cae12184177114365edef330f654c6e97301f3d09f339cedcb612ed89c69ca0`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs are compared with the
feature commit. Reproduce with `tests/ios/air-memory-pair-select-index.v LLVM_AS
FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`,
using repository module paths and retained toolchain. Dependencies remain
referenced; this is not hermetic. Native JIT is uninstrumented and leak detection
is disabled. CPU software Metal only is qualified; no broad runtime suite, native
GPU, guest launch or new Fortnite frame is verified.

Semantics follow the [LLVM language reference](https://llvm.org/docs/LangRef.html#select-instruction).
