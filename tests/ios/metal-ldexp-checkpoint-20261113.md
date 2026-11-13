# Software Metal signed exponent scaling — 2026-11-13

`00ffeb24d` admits direct LLVM `ldexp.f16.i32` and `ldexp.f32.i32`
in bounded AIR buffer kernels and opt-in software Metal compute. A half/float
value and signed i32 exponent reuse scalar validation and integer unpack/pack
evaluation. Scaling rounds to nearest with ties to even, independently of
host rounding mode. Overflow becomes signed infinity; underflow rounds through
subnormals to signed zero. Zeros/infinities preserve their bits at INT_MIN/MAX;
NaNs use the preferred quiet choice. Both operands are evaluated, so a zero
value does not hide exponent poison/undef. Calls cost one step. The buffer
profile now admits 33 intrinsic families.

Normal and ASan/UBSan checks each pass 656,128 native primitive comparisons,
including 768 value/exponent boundary pairs. Every half encoding and 65,536
sampled float encodings are tested under five signed scales. The boundary
matrix includes signed zeros, subnormals, finite limits, infinities, NaNs and
INT_MIN/MAX exponents. The 11,633 native arithmetic NaN cases compare by class
while requiring the interpreter's preferred quiet result; the remaining
644,495 primitive results compare exact raw bits, including zero signs.

Another 1,024 native zero-scale chains check cached calls. Twenty-four exact
subnormal tie/sign checks cover four host rounding modes; the incoming mode
is restored. The checker verifies five/six-step execution, unaligned offsets,
sentinels, insufficient primitive budgets, eight poison/undef guards, four
freeze/lazy choices, eighteen metadata rejections and four wrong exponent-type
rejections after a cached call and preceding store. Rejected profiles leave
sentinels intact. Guard functions never execute natively. MCJIT uses the
detected host target (`apple-m5`), optimization level 2 and FastISel off.

Sanitized regressions pass 48 exact scalar scaling cases and name/arity guards,
all 16 integer/mixed groups, and 339,344 buffer FMA comparisons with 11,920
cached chains and their existing fused/unfused, rounding, metadata and poison
controls. JIT-generated reference code is not sanitizer-instrumented; the
interpreter/checkers are.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
Seven deferred scaling dispatches check both precisions: ordinary scaling,
subnormal ties, negative zero, overflow, extreme exponents and signaling NaNs.
Fourteen exact output words are stored through bitcasts and checked GEPs.
Inputs change after encoding; sentinels persist until commit. Pipeline/caller
buffer handles are released before commit, snapshots use different input/output
offsets, and two-runtime resource drainage passes.

Canonical complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-ldexp-validation-20261113-r1.tar.zst`

The maintained V harness built on a temporary 512 MiB RAM disk, with its outer
temporary directory also on RAM to avoid system disk pressure. The 188 MiB
bundle contains build receipts, standalone tests/results, compiler snapshots,
LLVM header, source.tar pinned to the feature revision and selected identity
hashes. No generated program functions were edited. Decode the complete archive
with `zstd -dc --long=28 ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

The archive was restored to a fresh RAM directory, then moved to the original
path while the original tree remained under another name. The unchanged
maintained `tests/packages/wine-workspace-archive.v` inventory checker verified
every file byte, size, type, permission and link target, including the root.
Selected identities match. All five restored suites pass again, including all
24 software Metal groups with normal hashing. The complete inventory matches
after replay and the archive checksum passes.

Replay fixtures/logs are retained in the same-prefix `.replay.tar.zst`; its own
complete inventory matches a fresh extraction. Inventory receipts and
build/restore/check logs remain beside the archives. The RAM disk was detached
after verification. Initial standalone evidence remains in the same-prefix
directory. No earlier completed evidence or other sessions' files were removed.
These receipts do not replace historical launch auditors.

The standalone compiler snapshot was saved after checks; the harness captured
its compiler before generation. External library symlinks, SDKs, assembler and
dylibs remain unsealed prerequisites. Leak detection is disabled; object
drainage is checked, retained heap is not measured. The ordinary runner was not
rebuilt. Compute remains a bounded single-thread CPU interpreter requiring
valid LLVM IR. Synthetic fixtures do not establish Apple compiler-produced
kernel compatibility. No GPU rendering, presentation, Vinix guest, Fortnite
frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `655599ae0e9786992a6dd49a912f820ddd0b7ab25adb1a0cb018f65e81458ff6` |
| `.inventory.json` | `240180f2aca67c06386ab09eae27aa58796adf4fc8adc35148015312a376cea9` |
| `.replay.tar.zst` | `9fb5a3e98834cff17605b76607db8dcc9b38e5b044c298e57b0931e7c37483ec` |
| `.replay-inventory.json` | `422acf4e9cf57d329946e7d5c8aba66e2353e8c28bae2677c84f69bfac0387ad` |
| `source.tar`, revision `00ffeb24d` | `5cd68f8d3a256a6cc0e859eed9aeca32bf322d3713dec9b3b2a5314dc7d0a1d8` |
