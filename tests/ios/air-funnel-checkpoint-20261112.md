# Scalar funnel-shift checkpoint — 2026-11-12

`db9702d02` adds `llvm.fshl.i1..i64` and `llvm.fshr.i1..i64`, including rotations
when both data operands match. Three homogeneous integer operands supply the
high/low halves and shift. The amount is masked before reduction modulo width;
zero chooses the high half for left and low half for right. A dedicated zero
branch avoids host shifts by 64. The unsigned implementation uses no wider
integer, host builtin, LLVM, FP or new allocation. Poison in any operand
propagates and selected undef errors. Strict direct-call/name/width/signature/
attribute/flag admission remains. See [the contract and maintained checker](../../compat/ios/airbitcode/SCALAR-FUNNEL.md)
and [LLVM semantics](https://llvm.org/docs/LangRef.html#llvm-fshl-intrinsic).

Normal and ASan/UBSan runs each pass **2,230,560 bit-exact native LLVM comparisons**
across 256 primitive/rotation functions, including **1,114,112 boundary triples**.
The data-edge matrix covers shifts 0..2N-1, all-one/high-bit/mixed-bit amounts.
All i1..i5 triples are exhausted; wider cases receive 4,096 mixed-bit triples.
High incoming bits exercise masking of all operands, including odd-width
amounts before modulo. Sanitized units pass **558,224 independent bit-selection
oracle comparisons**, rotation round trips, zero-shift selection and strict
name/width/arity/evaluator guards.

Controls pass for 384 poison results, 384 undef rejections, 256 budget/integer-
API rejections, fourteen metadata corruptions, six argument-type mismatches,
six name/width mismatches and ten result corruptions. Another 512 complementary
concatenation/shift chains restore the first operand while exercising both
declarations and exact four-instruction results. Primitive CALL/return takes two.

Sanitized regressions pass 1,980,544 FMA/optional-fusion comparisons (1,842,062
exact and 138,482 NaN-class checking Vinix's preferred NaN), with 474,752 native
optional-choice checks; 1,329,400 zero-count value/tag comparisons; 743,134 exact
bit-operation comparisons; and 2,400,256 exact FP-class predicates. Existing
controls and mixed/intrinsic/FMA/count/bit/FP-class unit suites pass. Full legacy
19,208,896 math and separate arithmetic/conversion/integer-execution LLVM suites
were not rerun; validation targets ternary dispatch and the current bit families.
LLVM/JIT/native code is not sanitizer-instrumented, leak detection is disabled
and retained allocation was not measured.

Generated C confirms fixed stack storage for the expanded 488-entry declaration
cache and two attribute-group IDs. Seven disjoint 64-width integer ranges follow
forty floating-overload slots; the existing three owned execution arrays and
cleanup remain. Mixed scalar units link as a static little-endian AArch64 Linux
ELF and pass header checks; no guest execution ran.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-funnel-validation-20261112-r1/`

It contains source, all fixtures/bitcode/comparisons and native-choice diagnostics,
binaries, generated C, identities, logs and reproduction notes. Selected V/LLVM
hashes match the pre-build receipt; complete compiler/SDK/LLVM/JIT/fenv/sanitizer
dependency closures are not sealed. Existing usize warnings remain. The unchanged
complete typed inventory checker passes for the original and fresh restore under
`air-funnel-restoration-20261112-r1/`, matching every path, byte, size, type and
permission. Full archive decoding/extraction exit zero. Restored sanitizer funnel
units and all 2,230,560 comparisons pass again with their controls; restored
mixed/intrinsic/FMA/count/bit/FP-class units also pass. Post-replay inventory and
selected identity checks pass; receipts remain beside the bundles.

No AIR shader, iOS app, GPU command or new Fortnite probe ran. The default Metal
device stub still returns nil; no new frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `06d0448fd635fc18fef07573aad120e108db4baeb581bd02827aa609fa3d8a3a` |
| Complete `.tar.zst` beside bundle | `a7c061da09379ccab3cfd30930f75cb44553b273cba5c3de7007d9465f51a9a3` |
| `source.tar`, revision `db9702d02` | `ae4ce1e270f799557e23403aca7f5fe2a0e1d6b6b48a762fa25ebfa32152ab22` |
