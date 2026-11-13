# Software Metal legacy extrema — 2026-11-13

`03857c3bd` admits direct LLVM `minnum`/`maxnum` in bounded AIR buffer kernels
and opt-in software Metal compute. Matching half/float inputs and results
reuse scalar validation and the existing permitted number-preferring
`minimumnum`/`maximumnum` refinement, including for signaling NaNs. A single
NaN selects the exact numeric operand; two NaNs produce the preferred quiet
NaN. Negative zero sorts below positive zero. Both operands are evaluated;
poison propagates and undef rejects even with a NaN counterpart. Calls cost
one step. The buffer profile now admits 37 intrinsic families.

The expanded `tests/ios/air-memory-float-extrema.v` passes normally and under
ASan/UBSan: 1,972,992 primitive comparisons and 1,972,992 native/identity cached
chains across six extrema families in both precisions. Legacy calls compare
against native modern number-preferring operations to qualify the chosen
refinement. Every half encoding is paired with four anchors; float inputs use
65,536 mixed pairs per operation. Twelve 24-by-24 edge matrices add 6,912
boundary pairs. The 18,688 primitive NaN-class cases require native NaN and
the exact interpreter preferred quiet NaN; the other 1,954,304 compare exact
raw bits, including signed zeros.

Another 1,408 eight-step chains mix all four legacy/modern declarations in one
buffer function, compared against native modern equivalents. Declaration cache
identities remain distinct. `legacy-native.tsv` separately records all 2,304
native legacy edge results: 288 permitted signaling-NaN propagation choices
and no signed-zero violations. Diagnostics never relax refinement comparisons.

Unaligned offsets, sentinels, five/seven-step execution, insufficient primitive
budgets, 96 poison/undef guards with zero/NaN counterparts, and 24 freeze/lazy
choices pass. Nine initial-call and 108 later cached-call metadata corruptions
reject before preceding stores; restored cached calls pass six-step baselines.
Guard functions never execute natively. MCJIT uses the detected host target
(`apple-m5`), optimization level 2 and FastISel off. JIT-generated reference
code is not sanitizer-instrumented.

Sanitized regressions pass four scalar intrinsic groups, including 264 exact
extrema results, all 16 integer/mixed groups, and all 656,128 buffer `ldexp`
comparisons plus existing chain, poison, rounding and metadata controls.
All 24 software Metal groups pass with normal and deterministic Swift hashing.
Seven new legacy dispatches repeat the modern extrema fixture: both zero
orders, a signaling NaN on the left, a quiet NaN on the right, paired NaNs,
infinities and signed subnormals in both precisions. Twenty-eight exact output
words pass through bitcasts and checked GEPs. Input bytes change after encoding;
sentinels persist until commit. Pipeline/caller buffer handles are released
before commit; seven offset snapshots and two-runtime object drainage pass.

Canonical complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-legacy-extrema-validation-20261113-r1.tar.zst`

The maintained V harness built on a temporary 512 MiB RAM disk, including its
outer temporary directory. The 189 MiB bundle contains build receipts,
binaries, fixtures/results, native diagnostics, compiler snapshots, LLVM header,
selected identity hashes and source.tar pinned to the feature revision. Decode
with `zstd -dc --long=28 ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A fresh complete extraction replaced the original path while retaining the
original tree under another name. The unchanged maintained
`tests/packages/wine-workspace-archive.v` inventory checker matched every file
byte, size, type, permission and link target, including the root. Selected
identities match. All five restored suites pass, including all 24 software
Metal groups with normal hashing and all native legacy diagnostics. The complete
inventory matches after replay and the archive checksum passes. Replay fixtures
and logs are retained in the same-prefix `.replay.tar.zst`; its own inventory
matches a fresh extraction. Receipts and build/restore/check logs remain beside
the archives. The RAM disk was detached after verification; no earlier completed
evidence was removed. These checks do not replace historical launch auditors.

The standalone compiler snapshot was saved after checks; the harness captured
its compiler before generation. External library symlinks, SDKs, assembler and
dylibs remain unsealed prerequisites. Leak detection is disabled and retained
heap is not measured. The ordinary runner was not rebuilt. Compute remains a
bounded single-thread CPU interpreter requiring valid LLVM IR. Synthetic
fixtures do not establish Apple compiler-produced kernel compatibility. No GPU
rendering, presentation, Vinix guest, Fortnite frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `18596ab1b0005ffafe0a0149244125c8da50ff7732cf0958d008f72f2988402f` |
| `.inventory.json` | `de54ecf833d53fac2466a2495ffb536d8bde8b435e20ff01971b876afecd74c7` |
| `.replay.tar.zst` | `7cfbb3b912cdb1fe4a9353a25cd03444f08e465cc594d89e2c3616fa20272d52` |
| `.replay-inventory.json` | `a4124019892bc101cdee0b7bcd09bfb7f87329d7170db90508dc447eaed18b87` |
| `source.tar`, revision `03857c3bd` | `7b2b1e43d266c20d11ab137aca2424f1d3ca01e886d4ce90d23c241acf5c1ecb` |
