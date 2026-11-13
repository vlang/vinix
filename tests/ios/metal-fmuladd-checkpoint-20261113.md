# Software Metal optional-fusion multiply-add — 2026-11-13

`240cd0506` admits direct LLVM `fmuladd` in bounded AIR buffer kernels and
opt-in software Metal compute. Matching half/float operands/results reuse
scalar validation and the permitted fused choice through the existing FMA
evaluator. One nearest/ties-to-even round follows the exact product-plus-addend,
independently of host rounding mode. All three operands are evaluated; poison
propagates and undef rejects even with a zero product. Calls cost one step.
The buffer profile admits 39 intrinsic families. FMA and fmuladd retain distinct
cache identities; another backend may choose separate rounding for fmuladd.

Normal and ASan/UBSan runs of `tests/ios/air-memory-fma.v` each pass 678,688
primitive fused-oracle comparisons across both names and precisions, including
23,328 boundary triples. Every half encoding is tested in two cancellation/
scaling patterns; float inputs also include mixed triples. The 21,244 primitive
NaN-class cases require native NaN and the exact interpreter preferred quiet
NaN; the other 657,444 compare exact raw bits, including signed zeros.

All 47,680 repeated/mixed seven-step chains compare against native FMA chains.
Optional calls always qualify the chosen fused refinement against native FMA.
Separately, `native-optional.tsv` records 11,920 actual native fmuladd outcomes:
116 match only the native fused result, none match only the separate result,
and 11,804 match both. Diagnostic NaNs compare by class. These observations
never relax the production fused-oracle comparison.

Three exact cases in each precision distinguish fused and separate rounding:
cancellation, overflow avoidance and a subnormal tie. Both names pass these
12 family/case checks and 48 interpreter checks under four host rounding modes;
the incoming mode is restored. Six-step primitive budgets, unaligned offsets,
sentinels and insufficient primitive budgets pass. Nine initial-call and 36
later cached-call metadata corruptions plus 12 operand-type corruptions reject
before preceding stores. Restored seven-step cached baselines, 24 poison/undef
guards and eight freeze/lazy choices pass. Guard functions never execute
natively. MCJIT uses the detected host target (`apple-m5`), optimization level 2
and FastISel off. JIT-generated reference code is not sanitizer-instrumented.

Sanitized regressions pass 58 exact scalar FMA patterns and six unfused controls,
all 16 integer/mixed groups, and all 325,972 buffer carry-less products plus
325,972 cached distributive chains and existing poison/type/metadata controls.
All 24 software Metal groups pass with normal and deterministic Swift hashing.
Five new optional-fusion dispatches repeat the FMA fixture in both precisions:
cancellation, overflow avoidance, subnormal tie, negative zero and invalid
infinity multiplication. Ten exact output words pass through bitcasts and GEPs.
Inputs change after encoding; sentinels persist until commit. Pipeline/caller
buffer handles are released before commit; five offset snapshots and
two-runtime object drainage pass.

Canonical complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-fmuladd-validation-20261113-r1.tar.zst`

The maintained V harness built on a temporary 512 MiB RAM disk, including its
outer temporary directory. The 190 MiB bundle contains build receipts,
binaries, fixtures/results, native diagnostics, compiler snapshots, LLVM header,
selected identity hashes and source.tar pinned to the feature revision. Decode
with `zstd -dc --long=28 ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A fresh complete extraction replaced the original path while retaining the
original tree under another name. The unchanged maintained
`tests/packages/wine-workspace-archive.v` inventory checker matched every file
byte, size, type, permission and link target, including the root. Selected
identities match. All five restored suites pass, including all 24 software
Metal groups with normal hashing. The complete inventory matches after replay
and the archive checksum passes. Replay fixtures/logs are retained in the
same-prefix `.replay.tar.zst`; its own inventory matches a fresh extraction.
The first replay extraction started before its archive existed and extracted
no files; that failure receipt remains as `.replay-restore-incomplete.log`.
The successful retry uses a fresh directory and unchanged inventory checker.
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
| Complete `.tar.zst` | `b5b543cef677f062277bf590065ba491b8c20d7a80b6d538a1476b36977e73bf` |
| `.inventory.json` | `7dd851d20abe48b0de79b3d539d289bb5ceebef212390da7ddbe743614f6a143` |
| `.replay.tar.zst` | `447bf168b7b2c374babe677b86b773c015568fe7d88ea8d92ed2b6a61fbd09f4` |
| `.replay-inventory.json` | `7e1a98736bb94d0b99edd689d04b5e5453d8efa9c04e2e86092de94bcb973846` |
| `source.tar`, revision `240cd0506` | `4f386315b33e7c47cbfd9e75effbeb21d7f94babc7f39428ba6ff5e9cd4be646` |
