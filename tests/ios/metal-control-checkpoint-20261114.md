# Software Metal forward control flow — 2026-11-14

`683e3bf58` extends bounded AIR buffer kernels and opt-in software Metal compute
with unconditional branches, scalar i1 conditional branches, and matching
i1..i64/half/float/overflow-pair PHIs. Branch targets must be strictly later
blocks in function order; conditional destinations must be distinct. A new
preflight checks the complete block partition, terminators, local forward
targets, leading PHIs, exact predecessor sets and bounded target work.
Unsupported operations in unvisited blocks still reject before stores.

All memory accesses retain statically resolved buffer arguments/offsets.
Extents, alignment and permissions combine every block's requirements.
`IRMemoryProfile.steps` is the total static instruction count, required before
execution even when a shorter path is taken. `IRVoidRun.steps` counts only
executed instructions, including branches, PHIs and returns. Incoming PHI
values are collected before any result is published and only the executed
predecessor is read. Poison/undef branch conditions error; dynamic errors
retain earlier writes. Untaken dynamic errors and unchosen scalar PHI undef
values are not evaluated. Undef pair constants retain their preflight rejection.

The new per-block predecessor/stamp table is local to validation and freed
on success/error. Execution owns a pending-PHI array sized to the maximum
leading PHI group and frees it with the existing value/known arrays. Both new
arrays have zero length for ordinary one-block bodies without PHIs. Numerical
helpers and the 16-byte execution value remain unchanged. Loops, backward
edges (including acyclic ones in a different block order), switches, pointer
PHIs, dynamic GEPs and general aggregate PHIs remain unsupported.

Normal and ASan/UBSan runs of `tests/ios/air-memory-control.v` each pass
144,320 exact native comparisons. Its 450 diamonds cover every integer width,
both floating precisions and all six overflow families, each through both
branches with 12x12 edge matrices and 16 mixed pairs. Another 320 comparisons
exercise nested branches and parallel PHI groups. Actual path counts, output
bits, offsets and sentinels match. Native conditions use canonical bytes while
the interpreter also checks low-bit masking with 0xfe/0xff.

All 11,250 branch/PHI/target/dead-block metadata, 1,350 operand-type and 450
conservative-budget controls reject before preceding stores; restored
baselines pass. The 512 integer/pair poison/undef/freeze cases produce 384
expected rejections and 128 defined choices. Eleven additional scenarios
check inactive-path buffer extents, early returns, untaken/executed division
errors, loop/backward-edge/pointer-PHI/dead-alloca rejection and an earlier
write surviving a dynamic poison-branch failure. MCJIT uses optimization level
2 with FastISel off; guard functions are not executed natively.

Final sanitized regressions pass 665,592 native overflow pairs, 531,192
independent widened checks, 122,736 defined pair-freeze comparisons, 245,760
insertion comparisons, 86,016 scalar-select comparisons and all their existing
guards. All 16 integer/mixed unit groups pass. All 24 software Metal groups
pass under normal and deterministic Swift hashing. Per runtime, seven deferred
branching dispatches preserve 21 exact u64 value/flag/tag words, with both
paths, simultaneous scalar/pair PHIs and an overflowing multiply. Sentinels,
offset snapshots, caller-handle release before commit and two-runtime drainage
pass. A loop kernel rejects during pipeline creation.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-control-validation-20261114-r1.tar.zst`

The 354 MiB bundle includes final and intermediate passes, build receipts,
binaries, fixtures/results, generated C, compiler snapshots, LLVM header,
selected identity hashes and source.tar pinned to the feature revision.
`intermediate` retains the first software/overflow passes before control checks
were finalized; final regressions and software builds use the committed code.
Decode with `zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`. Receipts and
replay evidence use the same prefix outside Git. Originals remain retained.

A fresh extraction replaced the original bundle path while retaining
`original-bundle`. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matched every file byte,
size, type, mode and link target, including the root; selected identities also
match. All six restored suites pass: sanitized control-flow, overflow/freeze,
insertion and scalar-select references, integer/mixed units, and all 24
software Metal groups with normal hashing. The complete bundle inventory and
archive checksum still match after replay. The replay archive also matches its
own inventory after a fresh extraction; both replay trees remain.

The standalone compiler snapshot was saved after builds; the harness captured
its compiler before generation. External SDKs, assembler, library symlinks and
dylibs remain unsealed prerequisites. Native MCJIT code is not sanitizer
instrumented. Leak detection is disabled; retained heap was not measured.
The ordinary runner was not rebuilt. Execution remains single-thread CPU
interpretation of synthetic valid LLVM fixtures. No Apple-produced shader,
GPU rendering, presentation, Vinix guest, Fortnite frame or launch gate is
newly verified. Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `67355baf82e3184756d1f81b679b584c06487e66a1c1d62f18505a9c7b2e26b6` |
| `.inventory.json` | `9ab0ab5dc495a839cb77a1c8452977c3211cdc22453d9bb1b360fc5d1c0fdc3a` |
| `.replay.tar.zst` | `cccd5507d2f3c3cb4c18caa97a1a363f2483e8ac700ed4e268b19d811b721873` |
| `.replay-inventory.json` | `b48c08facb4dc0e44bf70fa7558c5708cced59f29873c126cbb831e9392c8d09` |
| `source.tar`, revision `683e3bf58` | `6a2a6a9b988af56bb97ad7213e47a94d44650684d80029741a7593b8c0367cef` |
