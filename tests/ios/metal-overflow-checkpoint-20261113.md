# Software Metal integer overflow pairs — 2026-11-13

`4c55c790f` admits all six signed/unsigned add/subtract/multiply
`*.with.overflow` families at i1..i64 in bounded AIR buffer kernels and opt-in
software Metal compute. Calls return literal unpacked `{iN, i1}` pairs with
separately tagged wrapped values and overflow flags. Overflow keeps both fields
defined; input poison propagates to both and undef rejects. `extractvalue`
validates pair shape, source/result types and field 0 or 1. Calls and extractions
each cost one step. Shared validation/evaluation now serves the scalar and
buffer interpreters. The fixed declaration cache grows to 1,768 entries and
the buffer profile admits 47 intrinsic families.

Normal and ASan/UBSan runs of `tests/ios/air-memory-overflow.v` each pass
665,592 exact native wrapped-value/flag pairs, including 368,832 overflow cases
and 55,296 boundary pairs. All 384 overloads execute; every i1..i8 input pair is
exhausted, with 256 mixed pairs per wider overload. Independent widened
arithmetic also checks 531,192 narrow pairs, including their boundary matrices.
The nine-step kernels store scalar fields separately; offsets, sentinels,
insufficient budgets and zero interpreter padding pass. Native value bits
compare exactly within their width; unspecified native padding is masked.

All 3,456 extraction metadata/index corruptions, 3,456 later cached-call
corruptions and 768 operand-type corruptions reject before earlier stores.
Restored extraction/cached-call baselines pass. Both fields are covered by
3,072 poison/undef guards and 1,536 scalar freeze/lazy choices. Another 384
constant cases check zero pairs, poison-field stores and rejection of undef
pairs. Aggregate stores, freeze, select and insertion reject before preceding
stores; general aggregate memory/arguments/returns remain unsupported.

The first normal/sanitized reference attempts aborted on a target-incompatible
data layout. Their binaries, exact checker source, fixtures and logs remain in
`failed-layout`. Successful reruns keep the interpreter's explicit 64-bit
layout and let MCJIT select its native layout, as the existing GEP checker does.
Only scalar fields are stored and the sole GEP uses a byte offset. Native target
and layout receipts are saved. MCJIT uses `arm64-apple-darwin27.2.0`, optimization
level 2 and FastISel off. Guard functions never execute natively; JIT-generated
reference code is not sanitizer-instrumented.

The shared extraction refactor passes the sanitized scalar overflow checker:
1,955,832 exact native pairs (3,911,664 extracted fields), 1,123,914 overflow
cases and all existing poison, branch/PHI, cache, freeze, metadata, layout, name
and corruption controls. Sanitized units pass 524,280 independent narrow pairs,
12 i64 limits, pair-shape guards and all 16 integer/mixed groups. Generated C
confirms fixed local declaration-cache storage; no execution-value layout or
numerical algorithm changed.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
Seven deferred dispatches check every i32 overflow family and i64 unsigned
multiplication through 98 exact u64 output words. Wrapped values retain high
bits independently of flags. Inputs change after encoding; sentinels persist
until commit. Pipeline/caller buffer handles are released before commit; seven
offset snapshots and two-runtime object drainage pass.

Canonical complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-overflow-validation-20261113-r1.tar.zst`

The 338 MiB bundle contains both failed attempts, successful build receipts,
binaries, fixtures/results, all scalar comparisons, generated C, compiler
snapshots, LLVM header, selected identity hashes and source.tar pinned to the
feature revision. Decode with
`zstd -dc --long=28 ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A fresh complete extraction replaced the original bundle path while retaining
the original under `original-bundle` in the same-prefix directory. The unchanged
maintained `tests/packages/wine-workspace-archive.v` inventory checker matched
every file byte, size, type, permission and link target, including the root.
Selected identities match. All five restored suites pass, including the full
scalar comparison table and all 24 software Metal groups with normal hashing.
The complete inventory matches after replay and the archive checksum passes.
Replay fixtures/logs are retained in the same-prefix `.replay.tar.zst`; its own
inventory matches a fresh extraction. Both expanded bundles and replay trees
remain on disk, with receipts beside the archives. No earlier completed evidence
was removed. These checks do not replace historical launch auditors.

The standalone compiler snapshot was saved after checks; the harness captured
its compiler before generation. External library symlinks, SDKs, assembler and
dylibs remain unsealed prerequisites. Leak detection is disabled and retained
heap is not measured. The ordinary runner was not rebuilt. Compute remains a
bounded single-thread CPU interpreter requiring valid LLVM IR. Synthetic
fixtures do not establish Apple compiler-produced kernel compatibility. No GPU
rendering, presentation, Vinix guest, Fortnite frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `77e8af80357af28288c4145d3d6e211866b4daf86727f733d4ca88213baa8e6c` |
| `.inventory.json` | `8e4a5fb950d9e7d876338b808cede09944c9fabdbfb27aca392f4d55b7f7fb96` |
| `.replay.tar.zst` | `0f21ceb50d88bb10384a64f0418a9306af954d9b01f55dbab3b48f76ba4373e9` |
| `.replay-inventory.json` | `e0cefa30f8790b9bd11d62b8711a694320220eb1cb565d61d5d6e0731c53ee4a` |
| `source.tar`, revision `4c55c790f` | `a1c06eef54497bc3f8c0679c4825426ce868ddf125345fa483a1194eb5af7226` |
