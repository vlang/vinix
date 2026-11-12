# Scalar carry-less multiplication checkpoint — 2026-11-12

`3e30ba021` adds `llvm.clmul.iN` at every i1..i64 width, taking two iN inputs
and returning iN. Inputs are polynomial bit coefficients; additions become XOR
and only the low N product bits remain. Overflow discards bits without creating
poison. Input poison propagates; selected undef errors. Strict direct-call/name/
width/signature/header/attribute checks and the integer-only API's no-call profile
remain. See [the contract and maintained checkers](../../compat/ios/airbitcode/SCALAR-CLMUL.md)
and [LLVM semantics](https://llvm.org/docs/LangRef.html#llvm-clmul-intrinsic).

Production masks both inputs and accumulates selected shifted terms with XOR,
masking each term to N bits. It takes at most 64 iterations, using only one-bit
unsigned shifts. No host signed arithmetic, builtin, LLVM, FP or new allocation
participates in valid numerical evaluation. Unary evaluators reject this binary
operation.

Normal and ASan/UBSan runs each pass **325,972 bit-exact native LLVM
comparisons** across 64 primitive functions, including **9,216 boundary pairs**.
Every i1..i8 pair is exhausted; wider widths receive 4,096 mixed pairs and a
twelve-by-twelve edge matrix. Zero/one/all-one/high-bit/neighboring, alternating
and byte patterns are covered, with incoming high-bit noise on both arguments.
Sanitized units pass another **325,972** comparisons against independent
polynomial convolution. The reference computes each output coefficient's parity
from all input-bit pairs on its diagonal, without shifted-term accumulation.
Commutativity, XOR distributivity, polynomial squaring, zero/identity/high-bit
truncation and strict name/width/arity/evaluator guards pass.

Controls pass for 128 input-poison results, 128 undef rejections, 128 budget/
integer-API rejections, seven metadata corruptions, two type mismatches, three
name/width mismatches and five result corruptions. Another 512 ten-instruction
chains OR the commutativity and XOR-distributivity residuals, requiring both
to be zero. Each uses four calls to one declaration. Another 128 controls
reject altered flags/attributes on the second call after the first cached its
declaration. Primitive CALL/return takes two instructions.

Sanitized regressions pass 656,892 abs value/tag comparisons (87 poison),
743,134 exact bit-operation results, 2,400,256 exact floating classifications,
2,230,560 exact funnel results and 651,944 exact extraction/deposition results,
with all maintained controls. Mixed/intrinsic/count/FP-class/extrema/bit/funnel/
FMA/abs/saturating/saturating-shift/permutation units pass. Separate full math/
arithmetic/conversion/FMA/extrema/zero-count/saturating-add-subtract/saturating-
shift/integer-execution LLVM suites were not rerun: existing numerical helpers
were unchanged; shared generic calls, integer bit operations, declaration caching
and poison handling received focused checks. LLVM/JIT/native code is not sanitizer-
instrumented; leak detection is disabled. Retained allocation was not measured.

Generated C confirms unsigned XOR/shift evaluation, fixed stack storage for the
1384-entry declaration cache and two attribute-group IDs. Twenty-one disjoint
64-width integer ranges follow forty floating-overload slots. The three existing
owned execution arrays and cleanup remain. Mixed scalar units link as a static
little-endian AArch64 Linux ELF and pass header checks; no guest ran.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-clmul-validation-20261112-r1/`

The bundle includes pinned source, every fixture/bitcode/comparison, binaries,
generated C, identities, logs and reproduction notes. Selected V/LLVM hashes
match the pre-build receipt; full compiler/SDK/LLVM/JIT/fenv/sanitizer dependency
closures are not sealed. Existing usize warnings remain. The unchanged complete
typed inventory checker passes for the original bundle and fresh restore under
`air-clmul-restoration-20261112-r1/`, matching every path, byte, size, type and
permission. Full decoding/extraction exit zero; the disposable decoded tar was
removed afterward. Restored sanitizer binaries pass all 325,972 LLVM comparisons
and controls again, plus clmul/mixed/intrinsic/count/FP-class/extrema/bit/funnel/
FMA/abs/saturating/saturating-shift/permutation units. Post-replay full inventories,
relative identities, selected compiler hashes and the archive checksum pass.
Receipts and replay outputs remain beside the sealed bundles.

No AIR shader, iOS app, GPU command or new Fortnite probe ran. The default Metal
device stub still returns nil; no new frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `59a1c81b7151dcf3761d7123f0b23a0a7c092a31b460b41061ae15c1609f9c67` |
| Complete `.tar.zst` beside bundle | `eac80708154ac3ea4ebdcc3782c3bd346e04cc46c4cc48834aa9b9eeb0aa1412` |
| `source.tar`, revision `3e30ba021` | `6e8860910101dee78c2249e25ebbd9b639e6da38385f3264d7f6766d9d1fedf4` |
