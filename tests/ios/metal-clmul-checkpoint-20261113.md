# Software Metal carry-less multiplication — 2026-11-13

`3e1d6e57a` admits direct LLVM `clmul` in bounded AIR buffer kernels and opt-in
software Metal compute. Matching scalar i1..i64 operands/results reuse scalar
validation and polynomial multiplication over GF(2), retaining the low
result-width coefficients. Both operands are evaluated: poison propagates even
with zero input and undef rejects. Calls cost one step. The buffer profile now
admits 38 intrinsic families. The declaration cache grows from 1,320 to 1,384
slots; generated C confirms fixed local storage, including every clmul width.

Normal and ASan/UBSan runs of `tests/ios/air-memory-clmul.v` each pass 325,972
primitive comparisons against both native LLVM and independent polynomial
convolution. Coverage exhausts every i1..i8 input pair, samples 4,096 pairs at
each i9..i64 width, and adds 9,216 boundary pairs. Another 325,972 eight-step
cached chains verify `clmul(x,y) XOR clmul(x,y XOR 1) == x` against native LLVM
and the exact identity. Five-step primitive budgets, insufficient primitive
and chain budgets, unaligned offsets, sentinels and zero interpreter padding
pass. Native values compare exactly within the result width; unspecified high
bits in native narrow-store padding are masked.

All 576 later cached-call metadata corruptions and 128 operand-type corruptions
reject before preceding stores; restored six-step baselines pass. All 256
poison/undef guards with zero counterparts and 128 freeze/lazy choices pass.
Guard functions never execute natively. MCJIT uses the default host triple
(`arm64-apple-darwin27.2.0`), optimization level 2 and FastISel off. JIT-generated
reference code is not sanitizer-instrumented.

Sanitized regressions pass 325,972 scalar polynomial-convolution comparisons
with commutativity/distributivity/square/zero/identity/truncation controls, all
16 integer/mixed groups, and 32,768 native `pext`/`pdep` comparisons plus 32,768
native/identity chains and existing poison/metadata/budget controls.
All 24 software Metal groups pass with normal and deterministic Swift hashing.
Seven new i32/i64 dispatches check products, high-bit truncation and cached
distributive identities through 28 exact u64 words. Inputs change after encoding;
sentinels persist until commit. Pipeline/caller buffer handles are released
before commit; seven offset snapshots and two-runtime object drainage pass.

Canonical complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-clmul-validation-20261113-r1.tar.zst`

The maintained V harness built on a temporary 512 MiB RAM disk, including its
outer temporary directory. The 189 MiB bundle contains build receipts,
binaries, fixtures/results, generated C, compiler snapshots, LLVM header,
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
| Complete `.tar.zst` | `d28d05feb056fd312b651176c59163590832c7fac77467fa5f5fb5b89f021039` |
| `.inventory.json` | `c903fb8620aa829f36ac13a62e3b8faa8748162f60196d20302ffd94758cfd78` |
| `.replay.tar.zst` | `9a62844cbdbd93cdb7b9e6317745e2e40159fe80617b05ca3b7ba36da339ac7b` |
| `.replay-inventory.json` | `4be42b671c0f9197ea08f52614a4ccc21b585fa189871b4fac54c7b9ef25e0c6` |
| `source.tar`, revision `3e1d6e57a` | `5b7f4998337a453627e503e05460e4d17ef58ef118d03e36a27bdebf0cab477c` |
