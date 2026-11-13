# Software Metal number-preferring extrema — 2026-11-13

`4d11481f1` admits direct LLVM `minimumnum`/`maximumnum` in bounded AIR buffer
kernels and opt-in software Metal compute. Matching half/float inputs and
results reuse scalar validation and integer bit selection. A single NaN of
either class selects the exact numeric operand; two NaNs produce the preferred
quiet NaN. Negative zero sorts below positive zero in either operand order.
Both operands are evaluated; poison propagates and undef rejects even with
a NaN counterpart. Calls cost one step. The buffer profile admits 35 intrinsic
families; legacy `minnum`/`maxnum` remain unsupported there.

The expanded `tests/ios/air-memory-float-extrema.v` passes normally and under
ASan/UBSan: 1,315,328 native primitive comparisons plus 1,315,328 native/identity
cached chains across minimum/maximum/minimumnum/maximumnum in both precisions.
Every half encoding is paired with four anchors, float inputs use 65,536 mixed
pairs per operation, and eight 24-by-24 edge matrices add 4,608 boundary pairs.
Of the primitive comparisons, 18,544 require the native NaN class and exact
interpreter preferred quiet NaN; the other 1,296,784 compare exact raw bits.
Chains also restore the exact first numeric input when their result is numeric.

Unaligned offsets, sentinels, five/seven-step execution and insufficient
primitive budgets pass. Sixty-four poison/undef guards cover both operand
positions with zero and NaN counterparts; sixteen freeze/lazy choices pass.
Nine initial-call and 72 later cached-call metadata corruptions reject before
preceding stores, leaving sentinels intact. Restoring each cached call also
passes its six-step baseline. Guard functions never execute natively. MCJIT
uses the detected host target (`apple-m5`), optimization level 2 and FastISel
off. JIT-generated reference code is not sanitizer-instrumented.

Sanitized regressions pass four scalar intrinsic groups, including 264 exact
extrema results, all 16 integer/mixed groups, and all 656,128 buffer `ldexp`
comparisons plus existing chain, poison, rounding and metadata controls.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
Seven new deferred dispatches check both zero orders, a signaling NaN on the
left, a quiet NaN on the right, paired NaNs, infinities and signed subnormals
in both precisions.
Twenty-eight exact output words pass through bitcasts and checked GEPs. Input
bytes change after encoding; output sentinels persist until commit. Pipeline
and caller buffer handles are released before commit; seven snapshots use
different offsets and two-runtime object drainage passes.

Canonical complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-number-extrema-validation-20261113-r1.tar.zst`

The maintained V harness built on a temporary 512 MiB RAM disk, including its
outer temporary directory. The 188 MiB bundle contains build receipts, binaries,
fixtures/results, compiler snapshots, LLVM header, selected identity hashes and
source.tar pinned to the feature revision. Decode with
`zstd -dc --long=28 ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A fresh complete extraction replaced the original path while retaining the
original tree under another name. The unchanged maintained
`tests/packages/wine-workspace-archive.v` inventory checker matched every file
byte, size, type, permission and link target, including the root. Selected
identities match. All five restored suites pass, including all 24 software
Metal groups with normal hashing. The complete inventory matches after replay
and the archive checksum passes. Replay fixtures/logs are retained in the
same-prefix `.replay.tar.zst`; its own inventory matches a fresh extraction.
Receipts and build/restore/check logs remain beside the archives. The RAM disk
was detached after verification; no earlier completed evidence was removed.
These checks do not replace historical launch auditors.

The standalone compiler snapshot was saved after checks; the harness captured
its compiler before generation. External library symlinks, SDKs, assembler and
dylibs remain unsealed prerequisites. Leak detection is disabled and retained
heap is not measured. The ordinary runner was not rebuilt. Compute remains a
bounded single-thread CPU interpreter requiring valid LLVM IR. Synthetic
fixtures do not establish Apple compiler-produced kernel compatibility. No GPU
rendering, presentation, Vinix guest, Fortnite frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `f7181d619573622f8f54d361d7716f2920f340983ce79eefd8accf220a4950e3` |
| `.inventory.json` | `6ca951d92003f649559c1cc962b6843223dc5af69e58b00a071b71f475d3187c` |
| `.replay.tar.zst` | `1f1a90468bc42d670cd45ce5439ba78494d8cb88ade0d43d355a777d7a189ea0` |
| `.replay-inventory.json` | `b7b9613d95228bbe4d671328ead13239086696d6431249026f33a9a8bb8c9a4b` |
| `source.tar`, revision `4d11481f1` | `54eadb71e8d91836a7b498bd6e6c90667cc642246602785ce2a9f1d18146b5bf` |
