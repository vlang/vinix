# Software Metal floating extrema — 2026-11-13

`d3f4ec154` admits direct LLVM `minimum` and `maximum` in bounded AIR buffer
kernels and opt-in software Metal compute. Matching half/float operands and
results share scalar validation/evaluation. Either NaN input produces the
preferred quiet NaN. Other results preserve the selected input bits; negative
zero sorts below positive zero in either argument order. Both operands are
evaluated; poison propagates and undef rejects. Calls cost one step. The
buffer profile admits 30 intrinsic families. Number-preferring/legacy variants,
general/indirect/tail calls, call-site attributes and fast-math calls remain
unsupported.

Normal and ASan/UBSan checks each pass 657,664 native primitive comparisons
and 657,664 native mixed-chain comparisons across four functions. Every half
encoding is paired with +0, -0, +1 and -1 for each operation. Float functions
each have 65,536 pattern pairs. Both precisions also have 24-by-24 class/limit
matrices, totaling 2,304 boundary pairs: both zero orders, subnormal/normal
limits, unit neighbors, infinities, and quiet/signaling NaNs in either operand.

Each set has 18,400 arithmetic NaN cases checked by class while requiring the
interpreter's preferred quiet representation. The other 639,264 results compare
exact raw bits. Mixed chains repeat the first declaration and then use the
other family: `max(min(min(x,y),y),x)` and its dual return exact x bits without
NaNs. This independent identity includes both zero signs. The checker also
verifies five/seven-step execution, byte offsets, sentinels, insufficient
primitive budgets, 16 poison/undef guards, eight freeze/lazy choices and nine
metadata rejections after a store. Guard functions never execute natively.
MCJIT uses the detected host target (`apple-m5`), optimization level 2 and
FastISel off.

Sanitized regressions pass 327,744 sqrt comparisons and 327,744 sqrt/fabs
compositions with their existing controls, all four scalar-intrinsic unit
groups and all 16 integer/mixed groups. The scalar groups include 264 exact
extrema cases and 327,680 integer root/remainder inequalities. JIT-generated
reference code is not sanitizer-instrumented; the interpreter/checkers are.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
Five deferred dispatches check both zero orders, NaNs in either input, and
opposite infinities in both precisions. Twenty exact words are stored via
bitcasts, half-to-integer extension and checked GEPs. Inputs change after
encoding; sentinels persist until commit. Pipeline and all caller buffer
handles are released before commit; five input/output offset snapshots and
two-runtime resource drainage pass.

Canonical complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-float-extrema-validation-20261113-r1.tar.zst`

The maintained V harness built and ran entirely on a temporary 512 MiB RAM
disk, including its unchanged compiler-preamble corrections. The completed
188 MiB bundle contains the standalone tests/results, complete software
harness tree, both compiler snapshots, header, source.tar at the feature
revision and identity manifest. The initial level-9 archive write failed with
ENOSPC; only its owned incomplete output was removed, retaining the failure
log. A level-19 archive with a 256 MiB window fit on disk. Decode with
`zstd -dc --long=28 ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

The saved archive's checksum matched its RAM copy. The complete bundle was
restored to a fresh RAM directory and moved to the original source path while
the original tree remained under another name. The unchanged maintained
`tests/packages/wine-workspace-archive.v` inventory checker verified every
file byte, size, type, permission and link target, including the root. Selected
identities also match. All five restored suites pass again, including all 24
software Metal groups with normal hashing. The complete inventory still
matches after replay, and the archive checksum passes afterward.

Replay fixtures and logs are retained beside the main archive in
`.replay.tar.zst`; its own complete inventory was checked against a fresh
extraction. Separate `.inventory.json` and `.replay-inventory.json` receipts
and build/restore/check logs remain beside the archives. The RAM disk was
detached only after these checks. Initial standalone evidence remains in the
same-prefix directory on disk. No earlier completed evidence or other sessions'
files were removed. These receipts do not replace historical launch auditors.

The standalone compiler snapshot was saved after checks; the harness captured
its compiler before generation. External library symlinks, SDKs, assembler
and dylibs remain unsealed prerequisites. Leak detection is disabled; object
drainage is checked, retained heap is not measured. The ordinary runner was
not rebuilt. Compute remains a bounded single-thread CPU interpreter requiring
valid LLVM IR. Synthetic fixtures do not establish Apple compiler-produced
kernel compatibility. No GPU rendering, presentation, Vinix guest, Fortnite
frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `f6cfa3b8ce03882a8b8300395ba8f0067ac044712deb04f416a7ff4dd7c4e83b` |
| `.inventory.json` | `970a5632bed8b109309599cf40b6ebd5275231a37db4383bb9c48e6fbb9d5fb1` |
| `.replay.tar.zst` | `3b3de36d0c81544b714ac2f5948b0cc9a38b29855cfb36d42c3f295b8ba1c30a` |
| `.replay-inventory.json` | `88459c09a36c2480e7068a8367acf07258066c7daabedb86e675479c0a66f38c` |
| `source.tar`, revision `d3f4ec154` | `b6860034f01db91ed415d8f5193cacc472db6494084e5ea52470d170fc7d0c48` |
