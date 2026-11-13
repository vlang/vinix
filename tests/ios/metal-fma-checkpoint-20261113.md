# Software Metal fused multiply-add — 2026-11-13

`6d13b8e97` admits direct LLVM `fma` in bounded AIR buffer kernels and opt-in
software Metal compute. Three matching half/float operands and result reuse
scalar validation and exact fixed-integer-limb product-plus-addend evaluation.
One final rounding uses nearest with ties to even, independently of host
rounding mode. Defined zero/infinity/NaN cases use scalar FMA rules and the
preferred quiet NaN choice. All operands are evaluated; poison propagates and
undef rejects even with a zero product. Calls cost one step. The buffer
profile admits 32 intrinsic families; optional-fusion `fmuladd`, constrained
operations, general/indirect/tail calls, call-site attributes and fast-math
calls remain unsupported.

Normal and ASan/UBSan checks each pass 339,344 native primitive comparisons,
including 11,664 boundary triples, and 11,920 cached native chains. Every half
encoding is tested in `x*1-1` and `x*(1+ulp)-x` patterns. Float coverage includes
the same pattern counts plus 65,536 mixed triples. Each precision also has an
18-by-18-by-18 class/limit matrix. The 10,622 primitive arithmetic NaN cases
compare by class while requiring the interpreter's preferred quiet result;
the other 328,722 results compare exact raw bits, including zero signs.

Six independent exact cases distinguish fused and separate multiply/add in
both interpreter and native execution: cancellation to negative epsilon-squared,
overflow avoidance, and a subnormal tie. Twenty-four interpreter checks repeat
those results under four host rounding modes; the incoming mode is restored.
The checker verifies six/seven-step execution, offsets, sentinels, insufficient
primitive budgets, twelve poison/undef guards covering every operand, four
freeze/lazy selections and nine metadata rejections after a store. Guard
functions never execute natively. MCJIT uses the detected host target
(`apple-m5`), optimization level 2 and FastISel off.

Sanitized regressions pass the scalar FMA unit group (58 exact cases and six
unfused distinctions), all 16 integer/mixed groups, and all 1,613,824 buffer
classification comparisons plus their existing immediate/poison/environment
controls. JIT-generated reference code is not sanitizer-instrumented; the
interpreter/checkers are.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
Five deferred dispatches check cancellation, overflow avoidance, a subnormal
tie, negative zero, and invalid infinity multiplication in both precisions.
The first three distinguish fused arithmetic from two separate roundings.
Ten exact output words are stored through bitcasts and checked GEPs. Inputs
change after encoding; sentinels persist until commit. Pipeline/caller buffer
handles are released before commit, five snapshots use different input/output
strides, and two-runtime resource drainage passes.

Canonical complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-fma-validation-20261113-r1.tar.zst`

The maintained V harness used a temporary 512 MiB RAM disk. Its first attempt
failed because the TLS archiver's temporary file used the full system disk.
The failed tree and driver receipt remain in the complete bundle as
`failed-software` and `failed-software-driver.log`. A fresh build with the
outer `TMPDIR` also on RAM succeeds, including both hashing modes. The
maintained compiler-preamble corrections are unchanged; no generated program
functions were edited. Disk pressure also temporarily prevented documentation
writes; the successful retry was included in the feature commit.

The 240 MiB bundle contains both build attempts, standalone tests/results,
compiler snapshots, header, source.tar pinned to the feature revision and an
identity manifest. A level-19 archive with a 256 MiB window was saved to disk.
Decode with `zstd -dc --long=28 ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

The complete archive was restored to a fresh RAM directory, then moved to the
original path while the original tree remained under another name. The
unchanged maintained `tests/packages/wine-workspace-archive.v` inventory
checker verified every file byte, size, type, permission and link target,
including the root. Selected identities match. All five restored suites pass
again, including all 24 software Metal groups with normal hashing. The
complete inventory matches after replay and the archive checksum passes.

Replay fixtures/logs are retained in the same-prefix `.replay.tar.zst`; its
own complete inventory matches a fresh extraction. Inventory receipts and
build/restore/check logs remain beside the archives. The RAM disk was detached
only after verification. Initial standalone evidence remains in the same-prefix
directory. No earlier completed evidence or other sessions' files were removed.
These receipts do not replace historical launch auditors.

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
| Complete `.tar.zst` | `b08ea969a52c0b43d078e33b502314060b5d147a9587f760ac10d962e43b5095` |
| `.inventory.json` | `f42f9ce239c95cb257fdb52f5334b3850872e594d94e1162acb21aece59dcdc1` |
| `.replay.tar.zst` | `dc18d94e6ac25637f23361ce1bcab829842832dfbeb0be440eb7e9f8a25d29c2` |
| `.replay-inventory.json` | `a56658be848362feadca674e7b636cc47eb74ea6f6ce231ef665ad808ef64855` |
| `source.tar`, revision `6d13b8e97` | `63c47e6fd9211ddc68d160710c9aa41ac2bd79ebd69724832c85206dddd79feb` |
