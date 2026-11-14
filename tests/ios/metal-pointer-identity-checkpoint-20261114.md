# Software Metal pointer freeze and bitcast — 2026-11-14

`671556ee2` adds pointer `freeze` and same-address-space pointer `bitcast` to
bounded AIR buffer execution and opt-in software Metal compute. Both preserve
an already resolved argument identity and byte offset. Freeze requires exactly
matching operand/result types; bitcast requires scalar pointer types in the
same address space. Direct arguments, GEPs, invariant PHIs/selects and earlier
pointer freezes/bitcasts may feed each other. Each operation resolves during
preflight and costs one executed step without entering scalar value slots.

Original bounds, alignment and permissions remain attached to the binding.
Literal null/poison/undef pointers, integer-pointer conversions and address-space
casts remain unsupported. Freeze does not bypass an earlier pointer select's
defined-condition requirement. No runtime pointer poison representation or
owned-array layout was added; scalar numeric and freeze semantics are unchanged.

ASan/UBSan `tests/ios/air-memory-pointer-identity.v` passes 54,712 native LLVM
comparisons across 792 main functions and a nested fixture. It covers i1..i64,
half and float value types, direct arguments, freeze/bitcast chains in both
orders, select/GEP/PHI dependencies, branches/switches, three mixed PHI orders,
nonperiodic input bytes and aliases. Native fixtures use opaque pointer
bitcasts. Exact extents and costs pass: branch bodies have a 37-step bound and
execute 34; switch bodies have a 41-step bound and execute 34 or 35; the nested
body has a 19-step bound and executes 16. Native inputs use canonical narrow
padding; comparisons mask unused native output padding.

All 42,768 metadata/type/address-space controls, 792 short budgets and 3,168
binding/permission controls reject before an earlier store; restored baselines
pass. Nine guard bodies reject literal pointer sources or forbidden pointer
conversions. Eight poison/undef select-condition controls still error before
a following pointer freeze, with used/unused results and with/without prior
writes. Defined frozen conditions and untaken poison selects pass separately.
Rejection and indeterminate-condition guards never run natively.

Sanitized regressions pass 54,712 pointer-select comparisons, 147,456 unary
LLVM/raw-bit comparisons with all half encodings and 132 scalar freeze choices,
and 210,112 defined numeric/precision/bitcast comparisons with their controls.
The old unary fixture incorrectly expected `{i32, i1}` pair freeze to reject.
A separate build against prior revision `fc98198f8` reproduces the same
`guard_aggregate` failure. The fixture now uses an unsupported three-field
aggregate, retaining its rejection check and all nine controls. Both failures,
the prior source tree/compiler receipts and the corrected run are retained.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
The deferred branch kernel feeds an address-space-1 pointer PHI/select through
freeze and bitcast, then uses the result for stores and derived GEPs. Exact
results, sentinels until commit and both drained runtimes pass. Legacy typed
pointer pointee changes are not separately verified by these modern fixtures.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-pointer-identity-validation-20261114-r1.tar.zst`

The 212 MiB bundle retains binaries, build receipts, baseline/final fixtures
and results, compiler snapshots, harness-generated C, LLVM header, selected
identities and source.tar pinned to the feature revision. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`. Receipts and replay evidence
use the same prefix outside Git; original expanded evidence remains.

A fresh extraction replaced the original bundle path while retaining
`original-bundle`. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matches every file byte,
size, type, mode and link target, including the root; selected identities
match. All six restored runs pass: four sanitized reference suites and both
runtime hashing modes, using separate output roots. The complete bundle
inventory and archive checksum match after replay. A fresh replay-archive
extraction matches its own complete inventory; both replay trees remain.

The standalone compiler snapshot was saved after builds; the harness captured
its compiler before generation. External SDKs, assembler, library symlinks and
dylibs remain unsealed prerequisites. Native MCJIT code is not sanitizer
instrumented. Leak detection is disabled; retained heap was not measured.
The ordinary runner was not rebuilt. This remains single-thread CPU execution
of synthetic valid LLVM fixtures. No Apple-produced shader, GPU rendering,
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `ecbb3ec70b8127d4110ea9e91f51e82ff3163293aee37acd15575febd86f1c9f` |
| `.inventory.json` | `f724e07967126d183b4e69f190b73b0562080fb9c1b82ab191675856e867a009` |
| `.replay.tar.zst` | `e5fafdda243f28a4af33432acc5d244ef81df5dfd90f85709605ede873437ca1` |
| `.replay-inventory.json` | `0f35abff2aef920ac66a64f93ea7fc07f8aa327c4d173ead09676ef6ffc46739` |
| `source.tar`, revision `671556ee2` | `210b739f071ba4e32f0b04ad812cd3a8484a28e3f02ba9164b463b00d4820467` |
