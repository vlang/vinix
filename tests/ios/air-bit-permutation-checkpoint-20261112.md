# Scalar bit extraction/deposition checkpoint — 2026-11-12

`21cd074d2` adds `llvm.pext.iN` and `llvm.pdep.iN` at every i1..i64 width.
Both take an iN value and an iN mask. Extraction packs selected bits into low
result positions; deposition scatters low bits into selected positions, in
low-to-high mask order. Remaining bits are zero. Empty/full masks give zero/
input. Poison in either operand propagates; selected undef errors. Strict
direct-call/name/width/signature/header/attribute checks and the integer-only
API's no-call profile remain. See [the contract and maintained checkers](../../compat/ios/airbitcode/SCALAR-BIT-PERMUTATION.md)
and [LLVM extraction](https://llvm.org/docs/LangRef.html#llvm-pext-intrinsic)/
[deposition semantics](https://llvm.org/docs/LangRef.html#llvm-pdep-intrinsic).

Production masks both inputs, repeatedly isolates/removes the lowest mask bit
and pairs it with the next packed bit. It takes at most 64 iterations and uses
only one-bit unsigned shifts. Unsigned isolation/subtraction handles bit 63;
no shift by 64 occurs. No host signed arithmetic, builtin, LLVM, FP or new
allocation participates in valid numerical evaluation. Unary evaluators reject
these binary operations.

Normal and ASan/UBSan runs each pass **651,944 bit-exact native LLVM
comparisons** across 128 primitive functions, including **18,432 boundary
pairs**. Every i1..i8 value/mask pair is exhausted; wider widths receive 4,096
mixed pairs and a twelve-by-twelve edge matrix. Empty/full masks, high bits and
neighbors, alternating and byte patterns, and incoming high-bit noise are
covered. Sanitized units pass another **651,944** independent position/rank
comparisons, both inverse identities, empty/full masks and strict name/width/
arity/evaluator guards. The reference scans all width positions and obtains
packed rank from standard-library population count of lower mask positions.
The population-count reference is a test dependency only.

Controls pass for 256 input-poison results, 256 undef rejections, 256 budget/
integer-API rejections, fourteen metadata corruptions, four type mismatches,
six name/width mismatches and ten result corruptions. Another 1,024 mixed-family
cache chains check both inverse orders in three instructions. Every width
receives empty/full, single low/high-bit and patterned masks. Primitive
CALL/return takes two instructions.

Sanitized regressions pass 656,892 abs value/tag comparisons (87 poison),
743,134 exact bit-operation results, 2,400,256 exact floating classifications,
2,230,560 exact funnel results and 651,944 saturating-shift value/tag comparisons
(206,750 poison), with all maintained controls. Mixed/intrinsic/count/FP-class/
extrema/bit/funnel/FMA/abs/saturating/saturating-shift units pass. Separate full
math/arithmetic/conversion/FMA/extrema/zero-count/saturating-add-subtract/integer-
execution LLVM suites were not rerun: existing numerical helpers were unchanged;
shared generic calls, masks, declaration caching and poison handling received
focused checks. LLVM/JIT/native code is not sanitizer-instrumented; leak detection
is disabled. Retained allocation was not measured.

Generated C confirms unsigned mask iteration, fixed stack storage for the
1320-entry declaration cache and two attribute-group IDs. Twenty disjoint
64-width integer ranges follow forty floating-overload slots. The three existing
owned execution arrays and cleanup remain. Mixed scalar units link as a static
little-endian AArch64 Linux ELF and pass header checks; no guest ran.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-bit-permutation-validation-20261112-r1/`

The bundle includes pinned source, every fixture/bitcode/comparison, binaries,
generated C, identities, logs and reproduction notes. Selected V/LLVM hashes
match the pre-build receipt; full compiler/SDK/LLVM/JIT/fenv/sanitizer dependency
closures are not sealed. Existing usize warnings remain. The unchanged complete
typed inventory checker passes for the original bundle and fresh restore under
`air-bit-permutation-restoration-20261112-r1/`, matching every path, byte, size,
type and permission. Full decoding/extraction exit zero; the disposable decoded
tar was removed afterward. Restored sanitizer binaries pass all 651,944 LLVM
comparisons and controls again, plus permutation/mixed/intrinsic/count/FP-class/
extrema/bit/funnel/FMA/abs/saturating/saturating-shift units. Post-replay full
inventories, relative identities, selected compiler hashes and the archive
checksum pass. Receipts and replay outputs remain beside the sealed bundles.

No AIR shader, iOS app, GPU command or new Fortnite probe ran. The default Metal
device stub still returns nil; no new frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `5ee7e76bfbcfa0f3a1a6ea127d7f7982f344f3a968c337b52763dfe6dea44b96` |
| Complete `.tar.zst` beside bundle | `ca9225d1fa505aec2901bde95e3207401ed962db73395edd6c655f15ee729dc2` |
| `source.tar`, revision `21cd074d2` | `0d2bda40f288a74982b575798ef17f884ff6d1899d35e8b1300505c1b39cdbb8` |
