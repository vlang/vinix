# Half/float vector bitcast reshaping — 2026-11-16

Source revision: `d9fcc2bb1c156641d696ffe5c47e703d0bf346d7`.

Software Metal shader execution now accepts raw unflagged bitcasts between
equal-total-width 1..16-lane shapes containing i1..i64, half or float elements.
New cases include integer/FP packing and splitting, half/float reshaping and
floating identity casts. Little-endian packed positions preserve all defined
bits, including signaling NaN payloads, without floating arithmetic or quieting.
Poison propagates to every overlapping destination lane; undef rejects the
whole executed cast. Source freeze repairs individual inputs, while result
freeze clears whole poison result lanes. A round trip through wider lanes may
spread poison to previously defined neighbors. Integer-only execution still
rejects floating lanes. Floating address dependencies, big-endian reshaping,
scalar/vector casts, pointer casts and other floating formats remain excluded.

The profile charges source plus result counts to existing shared lane work.
A wrapper retains existing undef/scalar-tag diagnostics, then calls the bounded
integer bit-copy helper on fixed by-value snapshots. Generated C confirms the
integer helper call, fixed records and no new arrays or f32/f64 operations in
the wrapper. No owner, node kind, escaping pointer, lifetime extension or free
path is added. Construction storage remains 4,096 static slots; address graphs
retain their existing 256-node/32-level limits. Existing execution/graph/cache
allocations and ordinary error allocations remain; heap retention is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- All 364 supported shape pairs containing half/float: 392,352 execution cases,
  comprising 269,118 exact/frozen outputs, 74,190 poison-store failures and
  49,044 strict undef failures. Eight input patterns, four modes and selector
  widths 1/32/64 cover scalar insertion, constants, source/result freezes,
  non-byte integer boundaries, invalid selectors and ignored indeterminate
  lanes. Ordinary/prepared memory agree, preserving the preceding marker store
  on execution errors and every other byte. Validation itself preserves all
  bytes. Scalar results and integer-only rejections add 784,704 checks;
  34,944 short prepared budgets fail before writes.
- 95,840 native LLVM lanes match a separate flattened-bit-stream oracle.
  References use a pointer-only ABI and defined replacements for source
  poison/undef. Original states, zero freeze choices and invalid selectors are
  modeled separately; native poison and invalid memory operations never run.
- Unit checks add 1,572,864 packed/split values covering every half encoding
  and immutable snapshots, plus 26,349 overlap/undef/freeze states and stable
  diagnostics. Existing raw-bit, integer-bitcast, precision-cast, integer-cast
  and fneg unit suites also pass.
- 42 controls cover packing/splitting, floating identities, fneg, old snapshots,
  source/result freezes, poison spreading through round trips, discarded
  results, an unexecuted undef block, floating-address rejection, loop slot
  reuse, malformed metadata and big-endian guards. Eight memory/void storage
  and work limits pass. The work fixture charges 4,096 casts at 24 lanes plus
  56,356 extractions at 16 lanes, exactly 1,000,000 units; the next extraction
  rejects. Storage accepts 4,096 results and rejects 4,097 before writes.
- All five earlier standalone bitcast/integer-cast/precision/int-to-float/
  float-to-int checkers pass, including their shared limits and negative
  fixtures. They retain 266,516 raw-bitcast LLVM values, 283,192 integer-cast
  values, 323,722 precision values (including permitted NaN choices), 610,072
  integer-to-float comparisons and 511,264 defined float-to-integer values.
  Five old unsupported reshape fixtures now use bfloat shapes, and an old
  same-category mutation retains unequal total width. Rejection assertions
  remain. Computed-index and prepared-memory programs pass; the full previous
  integer-bitcast address matrix repeats 370,656 cases and 85,248 native lanes.
  Earlier cast/funnel/compare address control modes pass 52/125/50 controls.
  Other full address matrices, the broader 43-program regression, broad runtime
  and kernel/guest builds were not repeated.
- Both image modes retain six earlier kernels and add a raw floating reshape
  kernel. Half encodings pack into a signaling float NaN, fneg flips its sign,
  and successive half/byte splits feed a dynamic lane into the red channel.
  Independent byte arithmetic detects changed payloads, quieting and missing
  sign flips. Four sizes check exact RGBA and complete backing padding in fresh
  binaries/processes. Each mode reports 106 geometry dispatches, 56 images,
  147,218 checked invocations, 106 rejected pipelines and two prewrite bounds
  failures. Both runtimes drain completely. Its addresses remain integer-only.

All execution checks passed first. A clarified test header and explicit coverage
assertions were followed by a fresh full matrix run with identical counts.
Production source remained unchanged during qualification.

Evidence: `/Users/alex/Library/Caches/vinix-ios/vector-float-bitcast-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/vector-float-bitcast-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `257c7c2e2d0fa168a001997134b937f04af6c11f8cac2f3fae29fd8eaebbf37e`.
- Inventory SHA-256: `78bc64a4a5f47cd65ca3fe8a01b39559d0e81c71e70c59656b57ac424038cde4`.
- Source archive SHA-256: `95815bd823648abd198ba1b392909a025aff73c840edbc2106d9e745618094a9`.

The bundle retains rows, IR/bitcode, generated C, images, binaries, commands/logs,
source/tool hashes and ownership review. Source inputs match the feature commit.
Reproduce with `tests/ios/air-vector-reshape-bitcast.v LLVM_AS FRESH_EXTERNAL_DIR`
and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`, using repository
module paths and retained tools. Dependencies remain referenced; this is not
hermetic. Native JIT is uninstrumented and leak detection is disabled. CPU
software Metal only is qualified; no native GPU, guest launch or new Fortnite
frame is verified.
