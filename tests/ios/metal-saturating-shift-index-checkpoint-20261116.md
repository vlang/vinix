# Saturating left-shift buffer indices — 2026-11-16

Source revision: `38c5a5e9b1ac410c855a4ea3971d6368b4262ab6`.

Pure buffer index graphs accept scalar llvm.sshl.sat/ushl.sat over i1..i64.
Valid shifts clamp arithmetic overflow; amounts at or above the width produce
poison even for zero input. Amounts are width-truncated unsigned words without
modulo reduction. Input/overshift poison composes with existing select/freeze;
independent roots still reject poison. Both dependencies and cached heights are
validated with existing declaration/signature/attribute/duplicate checks.

The POD binary intrinsic node and its fields are reused. Evaluation preserves
input poison and takes the tagged result of scalar_integer_saturating_shift_value
so overshift poison is retained. No owned field or execution allocation is added.
Shared 256-node/32-level limits, fixed value/poison stack arrays and cache/profile
free paths remain. Generated C confirms stack storage. Heap retention is
unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 230,400 cases cover 128 overloads, eight patterns and 15-by-15 value/amount
  boundary pairs: 97,661 exact outputs and 132,739 prewrite refusals. The defined
  LLVM oracle replaces overshifts with zero amounts before native operations;
  separate V checks model overshift/literal/computed poison and signed bounds.
  No native poisoned shift executes. Validation, ordinary and prepared APIs agree
  and preserve all bytes on refusal. Cases include masks, both poisoned operands,
  right-hand wrap poison, select, freeze and frozen overshifts. Noisy interpreter
  padding and cached depth through either operand are checked: 32 levels accept,
  33 reject for each overload.
- Focused controls check cold zero overshift versus freeze and independent
  poisoned roots through all three APIs. Scalar shift tests pass 651,944
  independent checked-doubling comparisons, including 206,750 poison cases,
  exhaustive i1..i8 pairs and boundaries across i1..i64.
- Twenty-six existing core programs pass, including prior address matrices,
  graph limits, aliases, cold checks and memory/layout/vector/intrinsic tests.
  No unsupported-dependency guards changed. Historical complete bundles retain
  original checkers.
- The image shader doubles its address with unsigned saturating shift, halves
  it with an exact right shift and applies signed saturating shift by zero. Four
  image sizes pass exact RGBA readback/padding in both hashing modes. Each mode
  reports 106 geometry dispatches, eight shader images, 93,962 checked invocations,
  106 rejected pipelines and two prewrite bounds failures.

Evidence: `/Users/alex/Library/Caches/vinix-ios/saturating-shift-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/saturating-shift-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `39154c1319d387417bd11ec901ac1ff5213fb3faf41c5a9dfa2589ebc277d508`.
- Inventory SHA-256: `cb88bceb2b76a01c0afbc064c26083374dd9989add670b24333e44ffbead5c2b`.
- Source archive SHA-256: `c01da1fe33e3c99533fc07256bb9d691eb46a1949b974835d21539ac696ee2ec`.

The bundle retains initial/final comparison runs, rows, IR/bitcode, generated C,
images, binaries, commands/logs, ownership review and source/tool hashes. Source
inputs are compared with the feature commit. Reproduce with
`tests/ios/air-memory-saturating-shift-index.v LLVM_AS FRESH_EXTERNAL_DIR` and
`tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and retained toolchain. Dependencies remain referenced; this is not
hermetic. Native JIT is uninstrumented and leak detection is disabled. CPU
software Metal only is qualified; no broad runtime suite, native GPU, guest
launch or new Fortnite frame is verified.

Semantics follow the [LLVM language reference](https://llvm.org/docs/LangRef.html#saturation-arithmetic-intrinsics).
