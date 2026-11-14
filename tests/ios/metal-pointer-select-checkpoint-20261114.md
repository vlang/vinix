# Software Metal invariant pointer selects — 2026-11-14

`6f81deeca` supports pointer selects whose two arms have exactly the result
pointer type and resolve to the same argument identity and byte offset.
Arguments, GEPs, invariant PHIs and earlier selects may converge. Both arms
must be supported and equivalent, even with a literal condition; different
arguments reject even when their bound buffers alias. The result resolves
during preflight and can feed selects, PHIs, GEPs and scalar accesses. Existing
extents, permissions and forward-control requirements remain in force.

Each executed pointer select costs one step and reads its scalar i1 condition.
This bounded profile requires the condition to be defined at that instruction:
poison/undef error immediately, including for unused results, retaining earlier
stores. Untaken selects do not read their conditions; scalar freeze can define
a condition. Runtime pointer poison propagation is not implemented. Scalar
select semantics are unchanged. No runtime pointer format, owned-array layout
or ownership changed.

ASan/UBSan `tests/ios/air-memory-pointer-select.v` passes 54,712 native LLVM
comparisons across 792 main functions and a nested fixture. It covers
i1..i64/half/float value types, branches/switches, three mixed PHI orders, direct
and derived arms, select/GEP/PHI chains in both directions, nonperiodic input
bytes and aliases. Native inputs use canonical narrow padding; comparisons
mask unused native output padding. Exact extents and costs pass: branch
bodies have a 31-step bound and execute 28 steps; switch bodies have a 35-step
bound and execute 28 or 29; the nested body has a 17-step bound and executes 14.

All 21,384 metadata/type/condition controls, 792 short budgets and 3,168 binding/
permission controls reject before an earlier store; restored baselines pass.
Five invalid-arm bodies reject different arguments/offsets and null/poison/
undef pointers, including unchosen arms and aliased bindings. Eight condition
controls check poison/undef with used/unused results and with/without earlier
writes. Frozen and untaken poison conditions pass separately. Rejection and
indeterminate-condition guards never run natively.

Sanitized regressions pass all 54,712 invariant pointer-PHI and 86,016 scalar
select comparisons and their controls. The corrected API fixture passes all
24 software Metal groups with normal and deterministic Swift hashing. Its
deferred branch kernel selects between an invariant address-space-1 pointer
PHI and its original argument, then stores through that result and derived
GEPs. Exact results, sentinels until commit and both drained runtimes pass.
The initial fixture placed the select between PHIs; LLVM correctly rejected
that invalid grouping. It was moved after all PHIs and rebuilt in a fresh
`software-final` directory. The original failed `software` tree is retained.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-pointer-select-validation-20261114-r1.tar.zst`

The 340 MiB bundle retains binaries, build receipts, failed/final fixtures and
results, compiler snapshots, harness-generated C, LLVM header, selected
identities and source.tar pinned to the feature revision. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`. Receipts and replay evidence
use the same prefix outside Git; original expanded evidence remains.

A fresh extraction replaced the original bundle path while retaining
`original-bundle`. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matches every file byte,
size, type, mode and link target, including the root; selected identities
match. Restored select, PHI and scalar reference suites and both runtime hashing
modes pass. The first parallel deterministic replay collided while creating
the shared compute output parent; a fresh separate output root passes and
the failed log remains. The complete bundle inventory and archive checksum
match after replay. A fresh replay-archive extraction matches its own complete
inventory; both replay trees remain.

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
| Complete `.tar.zst` | `19a69d9e70a7f4bd31809d5d3175a23a7b7649db6f21808598ce7b3beaee9947` |
| `.inventory.json` | `f5b3487b4974effde21b18959ac4b52ed65862634262ed1d3775a751a0c8a610` |
| `.replay.tar.zst` | `4779a57d8303f8d2fca0fd5f66e8854b35d933a21c12bb7a72f5c72645d862a9` |
| `.replay-inventory.json` | `90a088078e1648989cd075e765d6bed9a95f6527cb32ec29465881b7193ea782` |
| `source.tar`, revision `6f81deeca` | `b4598674d8ef042c06ad74af1d0e4fdf69d37145a361113a75cada5ee7393ede` |
