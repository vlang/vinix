# Software Metal bounded memmove — 2026-11-14

`971ad7ece` adds nonvolatile constant-length `llvm.memmove.pD.pS.i32/i64`
to bounded AIR memory execution and opt-in software Metal compute. Exact
ordinary void declarations, resolved pointer operands, defined literal lengths
and literal false volatility are required. Nonempty destinations use spaces
0/1; sources use 0/1/2. Preflight derives complete read/write extents and
permissions, including combined usage when one binding serves both roles.

Every call costs one instruction plus two steps per byte, sharing the static
million-step budget with fills, switches and scalar operations. One scratch
array per run holds the largest admitted move and is freed on every exit.
Each move snapshots all source bytes before writing, including aliases through
different bindings and borrowed slices. Later calls reuse the allocation and
observe earlier stores. Execution compares no host addresses and calls no host
memmove. The cached profile owns no additional array.

Zero length adds no access requirement or extent, allowing empty readonly
bindings in every supported space pair; preceding GEP requirements still
apply. Overlap and zero-length semantics follow the
[LLVM memmove definition](https://llvm.org/docs/LangRef.html#llvm-memmove-intrinsics).
Null/poison/undef pointer literals still reject, including at zero length.
Volatile or dynamic-length moves, call-site attributes, memcpy, inline/atomic
variants and general calls remain unsupported. Canonical declaration attributes
admit destination writeonly, source readonly, nocapture/captures(none), fourth
immarg and memory(argmem: readwrite) encodings 0/1/2, with bounded cached scans.
Existing scalar/void and memset policies retain their prior profiles.

ASan/UBSan `tests/ios/air-memory-memmove.v` passes 42,546 native LLVM
comparisons across 240 main functions, 18 direct zero-length bodies and a
two-move sequence. It checks ten lengths from zero through 257, both length
widths, every supported nonempty space pair, GEP/PHI/select/freeze/bitcast
chains, nonperiodic source bytes and untouched bytes. Alias cases include both
overlap directions, identical/disjoint ranges, distinct bindings and borrowed
slices with different data heads. The sequence uses different move lengths.

Straight bodies have a length * 2 + 7 bound and execute that cost. Branched
bodies have a length * 2 + 21 bound and execute length * 2 + 18. The sequence
executes 58 steps. All 8,640 metadata/type controls, 243 budget controls and
720 binding/permission controls pass. Fifty-four static guards reject bad
lengths, pointer literals, volatility, overflowing extents, space-2 writes,
call attributes and excluded operations before an earlier store. Sixteen
poison/undef pointer-select conditions error with zero/nonzero lengths,
source/destination selects and with/without prior writes. Frozen conditions
and untaken poisoned selects pass separately. A 499,999-byte direct move
executes exactly one million steps; short, cumulative and mixed fill/move
budgets reject before stores. Large and rejection controls are interpreter
checks, not additional native comparisons.

The complete LLVM module is verified before native compilation. Rejection-only
guard/condition bodies remain in the interpreter input but are excluded from
MCJIT compilation; the projected `native-input.bc` is saved and checksummed.
An initial native run including the atomic rejection body crashed at address
zero; the failed binary, fixtures and debugger log remain. The ordinary native
reference functions and all interpreter rejection checks retain their coverage.

Sanitized regressions pass 90,130 memset and 2,178 pointer comparisons with
their controls. Both memory-attribute groups and all four scalar-intrinsic unit
groups pass, including 327,680 integer square-root inequalities. All 24 software
Metal groups pass under both Swift hash modes. Seven deferred dispatches bind
one buffer at differing source/destination offsets, perform two moves each,
preserve all other bytes and use data populated after encoding. Resources stay
retained through commit in both drained runtimes. The destination metadata is
read/write because the second move reads the first move's output. The initial
host with write-only metadata correctly rejects that pipeline and is retained.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-memmove-validation-20261114-r1.tar.zst`

The 339 MiB bundle retains final/preliminary binaries, generated fixtures and
results, build logs, compiler snapshots, harness-generated C, LLVM headers,
selected identities and source.tar pinned to the feature revision. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`. Inventory/checksum receipts
and replay evidence use the same external prefix. Qualification uses the
`*-verified` standalone binaries and `software-final` host.

A completed fresh extraction replaced the original bundle path. The unchanged
maintained `tests/packages/wine-workspace-archive.v` checker matches every file
byte, size, type, mode and link target, including the root; selected identities
match. All seven restored runs pass: three reference suites, two unit binaries
and both runtime hash modes using separate output roots. Complete bundle
inventory and archive checksum match after replay. A fresh replay-archive
extraction matches its complete inventory. Original expanded bundle and replay
trees remain alongside restored evidence.

The standalone compiler snapshot was saved after builds; harnesses captured
their compilers before generation. External SDKs, assembler, library symlinks
and dylibs remain unsealed prerequisites. Native MCJIT code is not sanitizer
instrumented. Leak detection is disabled; retained heap was not measured.
The ordinary runner was not rebuilt. This remains single-thread CPU execution
of synthetic valid LLVM fixtures. No Apple-produced shader, GPU rendering,
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `d7ec098faffc7a84c3d6bd8fb5121e823dbf38efae7281fd5a817a79624194b3` |
| `.inventory.json` | `31587429449bf0d141a4d14cbefff689e7718a5d733de8a073a886b14c63a47a` |
| `.replay.tar.zst` | `375e5967c156b78fc312db4c01f692438b2a63b47cd88770c502d0a735c6a09f` |
| `.replay-inventory.json` | `bdef121fbe3aa6bea2e5dfc6a646344a978b499a0bc9e74683c4889cbdd7a39f` |
| `source.tar`, revision `971ad7ece` | `c0846421d4d2d5867ddfa150bd714135d91af06575e04424cf770ef776e09111` |
