# Scalar saturating left-shift checkpoint — 2026-11-12

`b3dbb8d8c` adds `llvm.sshl.sat.iN` and `llvm.ushl.sat.iN` at every i1..i64
width. Both operands are iN; the shift amount is truncated to that width and
interpreted unsigned. Amounts at least as large as the width produce poison,
even for input zero. Defined results clamp to the signed bounds or unsigned
maximum. Shift zero preserves every input bit, including i1 and INT64_MIN.
Input poison propagates; selected undef errors. Strict direct-call/name/width/
signature/header/attribute checks and the integer-only API's no-call profile
remain. See [the contract and maintained checkers](../../compat/ios/airbitcode/SCALAR-SATURATING-SHIFT.md)
and [LLVM semantics](https://llvm.org/docs/LangRef.html#saturation-arithmetic-intrinsics).

Production rejects overshifts before every host shift. It uses unsigned shifted
limits and magnitudes to detect saturation, then reconstructs negative bits by
unsigned negation. No host signed arithmetic, builtin, LLVM, FP or new allocation
participates in valid numerical evaluation. Untagged/unary evaluators reject
these binary operations.

Normal and ASan/UBSan runs each pass **651,944 exact native LLVM value/tag
comparisons** across 128 primitive functions: **445,194 defined values and
206,750 poison tags**, including **18,432 value/amount boundary pairs**. Every
i1..i8 pair is exhausted; wider widths receive 4,096 mixed values with amounts
cycling through 0..N+1 and a twelve-by-twelve edge matrix. Signed bounds and
neighbors, unsigned maximum/zero, byte patterns, boundary amounts and incoming
high-bit noise are covered. Native value wrappers substitute a zero amount
before an invalid shift; separate unsigned-comparison wrappers supply the tags.
All 64 data bits remain available; poison payload bits are ignored. Sanitized
units pass another **651,944** comparisons against independent checked doubling,
plus zero identity/zero overshift and strict name/width/arity/evaluator guards.

Controls pass for 256 input-poison results, 256 undef rejections, 256 budget/
integer-API rejections, fourteen metadata corruptions, four type mismatches,
six name/width mismatches and fourteen result/tag corruptions. Another 512
mixed-family cache chains reconstruct the inputs' XOR in four instructions.
Another 128 chains propagate an overshift of zero through the opposite family
in three instructions. Primitive CALL/return takes two instructions.

Sanitized regressions pass 656,892 abs value/tag comparisons (87 poison),
1,329,400 zero-count value/tag comparisons (174 poison), 2,400,256 exact floating
classifications, 2,230,560 exact funnel results and 1,303,888 exact saturating
add/subtract results, with all maintained controls. Mixed/intrinsic/count/
FP-class/extrema/bit/funnel/FMA/abs/saturating units pass. Separate full math,
arithmetic/conversion/FMA/extrema/bit/integer-execution LLVM suites were not
rerun: existing numerical helpers were unchanged; shared call/poison/dynamic-
shift paths received focused checks. LLVM/JIT/native code is not sanitizer-
instrumented; leak detection is disabled. Retained allocation was not measured.

Generated C confirms guarded unsigned shifts/magnitude arithmetic, fixed stack
storage for the 1192-entry declaration cache and two attribute-group IDs.
Eighteen disjoint 64-width integer ranges follow forty floating-overload slots.
The existing three owned execution arrays and cleanup remain. Mixed scalar
units link as a static little-endian AArch64 Linux ELF and pass header checks;
no guest ran.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-saturating-shift-validation-20261112-r1/`

The bundle includes pinned source, every fixture/bitcode/comparison, binaries,
generated C, identities, logs and reproduction notes. Selected V/LLVM hashes
match the pre-build receipt; full compiler/SDK/LLVM/JIT/fenv/sanitizer dependency
closures are not sealed. Existing usize warnings remain. The unchanged complete
typed inventory checker passes for the original bundle and fresh restore under
`air-saturating-shift-restoration-20261112-r1/`, matching every path, byte, size,
type and permission. Full decoding/extraction exit zero; the disposable decoded
tar was removed afterward. Restored sanitizer binaries pass all 651,944 LLVM
comparisons and controls again, plus shift/mixed/intrinsic/count/FP-class/extrema/
bit/funnel/FMA/abs/saturating units. Post-replay full inventories, relative
identities, selected compiler hashes and the archive checksum pass. Receipts
and replay outputs remain beside the sealed bundles.

No AIR shader, iOS app, GPU command or new Fortnite probe ran. The default Metal
device stub still returns nil; no new frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `ec7a53bb7b4dd8a057b644da67662ee340307d99e9d5dd4ec2836a2705ef3027` |
| Complete `.tar.zst` beside bundle | `8419db6bf90e6de3f33be6288eb5429ec6ecfb3ffadc963d7f52aa416b4df640` |
| `source.tar`, revision `b3dbb8d8c` | `8dc9081c0a3b46d6a4c91afc2363dd5ea95e8d443a21bef88c1d2e240c716276` |
