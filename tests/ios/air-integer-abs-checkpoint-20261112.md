# Scalar integer absolute-value checkpoint — 2026-11-12

`98246a7cf` adds `llvm.abs.iN` at every i1..i64 width, with a constant i1
minimum-poison flag. The minimum signed value retains its bits when the flag
is false and produces poison when true. Other negative values use unsigned
modular negation, avoiding host signed overflow at i1 and INT64_MIN. No host
builtin, LLVM, FP or new allocation participates in valid numerical evaluation.
Input poison propagates; selected undef errors. Strict direct-call/name/width/
signature/attribute/flag checks remain, including constant validation on cached
declarations and in unvisited blocks. The integer-only API retains its no-call
profile. See [the contract and maintained checkers](../../compat/ios/airbitcode/SCALAR-INTEGER-ABS.md)
and [LLVM semantics](https://llvm.org/docs/LangRef.html#llvm-abs-intrinsic).

Normal and ASan/UBSan runs each pass **656,892 exact native LLVM value/tag
comparisons** over 128 primitive functions: **656,805 defined values and 87
poison results**. Every i1..i16 bit pattern is exhausted under both flags;
wider widths receive 4,096 mixed-bit inputs and twelve edge values per function.
Incoming high bits test truncation before the minimum comparison. The native
value wrapper substitutes zero before an invalid abs call. A separate native
function returns the poison tag, preserving all 64 data bits. Poison payload
bits are ignored. Sanitized units pass **655,356** independent signed-magnitude
comparisons, idempotence, minimum/zero limits and strict evaluator guards.

Controls pass for 64 input-poison results, 64 undef rejections, 128 budget/
integer-API rejections, 128 mixed-flag results, 64 cached nonconstant-flag
rejections, seven metadata corruptions, twelve flag corruptions, six result
corruptions and one malformed flag in a dead block. Primitive CALL/return takes
two instructions; defined mixed-flag CALL/CALL/add/return takes four.

Sanitized regressions pass 1,329,400 zero-count value/tag comparisons,
2,400,256 exact floating classifications, 1,303,888 exact integer extrema and
19,208,896 math comparisons (17,718,326 exact and 1,490,570 arithmetic NaN-class
cases checking Vinix's preferred NaNs), plus 2,560 legacy native-extrema
diagnostics and their controls. Mixed/intrinsic/count/FP-class/extrema/bit/
funnel/FMA unit suites pass. Separate full arithmetic/conversion/FMA/funnel/
bit/integer-execution LLVM suites were not rerun. LLVM/JIT/native code is not
sanitizer-instrumented; leak detection is disabled. Retained allocation was
not measured.

Generated C confirms unsigned modular negation, fixed stack storage for the
808-entry declaration cache and two attribute-group IDs. Twelve disjoint
64-width integer ranges follow forty floating-overload slots. The three owned
execution arrays and cleanup remain. Mixed scalar units link as a static
little-endian AArch64 Linux ELF and pass header checks; no guest ran.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-integer-abs-validation-20261112-r1/`

It includes pinned source, every fixture/bitcode/comparison, binaries, generated
C, identities, logs and reproduction notes. The initial source export failed
outside the checkout; explicit repository paths corrected it before sealing.
Selected V/LLVM hashes match the pre-build receipt. Full compiler/SDK/LLVM/JIT/
fenv/sanitizer dependency closures are not sealed. Existing usize warnings
remain. The unchanged complete typed inventory checker passes for the original
bundle and fresh restore under `air-integer-abs-restoration-20261112-r1/`, matching
every path, byte, size, type and permission. Full decoding/extraction exit zero.
Restored sanitizer binaries pass all 656,892 abs comparisons and controls again,
plus abs/mixed/intrinsic/count/FP-class/extrema/bit/funnel/FMA units. Post-replay
full inventories, relative identities, selected compiler hashes and the archive
checksum pass. Receipts and replay outputs remain beside the sealed bundles.

No AIR shader, iOS app, GPU command or new Fortnite probe ran. The default Metal
device stub still returns nil; no new frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `1ba9957563baee4f2c63726e2be080057d039fb5f429a3a2d5fad4e2d37168ee` |
| Complete `.tar.zst` beside bundle | `e51d64d27a2cc1ed16629e20842710b141730c51a92438b7789fa8baec175d7e` |
| `source.tar`, revision `98246a7cf` | `1e8d58503dd678d6e44899d31a21536950d464ba0b8c2f85384da4e30e4664ad` |
