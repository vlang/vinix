# Software Metal pointer comparisons — 2026-11-14

`9164f2c61` adds `eq`, `ne`, `ugt`, `uge`, `ult` and `ule` pointer comparisons
to bounded AIR buffer execution and opt-in software Metal compute. Operands
must have exactly matching pointer types and resolve to the same binding.
Preflight compares their bounded offsets, including one-past addresses,
without reading source bytes, extending access requirements or exposing host
pointer bits. Each executed comparison costs one step and publishes a scalar
i1 for stores, branches and selects. A byte tag in the existing per-instruction
access records holds the result; no new owned array was added.

Cross-binding comparisons reject even when buffers alias. Signed ordering
requires an unknown numeric base and remains unsupported. Literal
null/poison/undef pointer operands reject. Earlier pointer selects still
evaluate their conditions when executed; precomputation cannot bypass them.
Existing pointer sources, bounds, permissions and forward-control limits apply.

The ASan/UBSan checker `tests/ios/air-memory-pointer-compare.v` passes 2,178
native LLVM comparisons across 216 main and 18 direct-argument functions.
It covers all six predicates, equal/forward/reversed offsets, spaces 0/1/2,
GEP/PHI/select/freeze/bitcast chains, scalar and pointer selects, branches,
aliases and different binding offsets. Sources need no read permission or
readable extent; exact 16-byte bindings admit one-past comparisons. Direct
argument comparisons also pass with empty source bindings. Native calls use
valid allocated pointers and mask unused i1 destination padding.

Main functions have a 30-step bound and execute 26 steps; direct functions
execute their five-step bound. All 11,664 metadata/type/address-space controls,
234 short budgets and 864 binding/permission controls reject before an earlier
store. Restored valid metadata passes. Forty-six static guards reject
cross-binding, literal-pointer or signed comparisons. Eight poison/undef
pointer-select controls error before a later comparison, with used/unused
results and with/without earlier writes. Defined frozen conditions and untaken
poison selects pass separately. Indeterminate and rejection guards never run
natively.

Sanitized regressions pass 54,712 pointer-identity comparisons and 86,016
scalar comparison/select comparisons with their controls. All 24 software
Metal groups pass with normal and deterministic Swift hashing. The deferred
branch kernel compares its address-space-1 PHI/select/freeze/bitcast pointer
with the output argument, feeds equality into a pointer select and uses that
result for stores/GEPs. Exact output words, sentinels until commit and both
drained runtimes pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-pointer-compare-validation-20261114-r1.tar.zst`

The 194 MiB bundle retains final and preliminary binaries, generated fixtures
and results, build receipts, compiler snapshots, harness-generated C, LLVM
header, selected identities and source.tar pinned to the feature revision.
Decode with `zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`. Inventory,
checksum and replay receipts use the same external prefix. Expanded originals
remain in `original-bundle` and `replay-original` alongside restored trees.

A fresh extraction replaced the original bundle path. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matches every file byte,
size, type, mode and link target, including the root; selected identities
match. All five restored runs pass: three reference suites and both runtime
hashing modes, using separate output roots. The complete bundle inventory
and archive checksum match after replay. A fresh replay-archive extraction
matches its complete inventory. Integrity checks do not replace historical
launch auditors.

The standalone compiler snapshot was saved after builds; the harness captured
its compiler before generation. External SDKs, assembler, library symlinks and
dylibs remain unsealed prerequisites. Native MCJIT code is not sanitizer
instrumented. Leak detection is disabled; retained heap was not measured.
The ordinary runner was not rebuilt. This remains single-thread CPU execution
of synthetic valid LLVM fixtures. No Apple-produced shader, GPU rendering,
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `3101c732505ea4b8db68726d121f75897e13d2ff154e04ddecd0cb60a9fbf5d5` |
| `.inventory.json` | `7f2828d30fcf989f1506f674d5ef77ae3bd47cddf854e701ffc1e5ba8ae2f353` |
| `.replay.tar.zst` | `05c8d0a297f7b9cd41411e5c750ed9a3a67539be1a27cfaf6e042a88c76bd339` |
| `.replay-inventory.json` | `bf1931237b3b419eed93ec35cc24136f7d4b9fc9aa5fd8c1dd0c1e9a05a15d42` |
| `source.tar`, revision `9164f2c61` | `195f885a2ed82c365b36b2ecd295fd098a1abdd9abca87184214647f751a2dcd` |
