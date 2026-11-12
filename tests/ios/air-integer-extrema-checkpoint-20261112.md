# Scalar integer extrema checkpoint — 2026-11-12

`79c5fd7aa` adds `llvm.smin/smax/umin/umax` at every i1..i64 width. Exact masked
input bits are selected under signed or unsigned ordering. Signed comparisons
flip the sign bit and compare unsigned keys, avoiding host signed conversion,
subtraction or overflow, including at i1 and INT64_MIN. No host builtin, LLVM,
FP or new allocation participates in numerical evaluation. Strict direct-call/
name/width/signature/attribute/flag checks remain; poison propagates and selected
undef errors. The integer-only API keeps its no-call profile. See
[the contract and maintained checker](../../compat/ios/airbitcode/SCALAR-INTEGER-EXTREMA.md)
and [LLVM semantics](https://llvm.org/docs/LangRef.html#llvm-smax-intrinsic).

Normal and ASan/UBSan runs each pass **1,303,888 bit-exact native LLVM comparisons**
over 256 primitive functions, including **36,864 boundary pairs**. All i1..i8
pairs are exhausted; wider cases receive 4,096 mixed-bit pairs and a twelve-by-
twelve edge matrix. Signed minima/maxima, unsigned maxima/zero, neighbors,
alternating and byte patterns are included, with incoming high-bit noise.
Sanitized units pass **1,267,024 independent value comparisons**, symmetry,
idempotence, explicit i1/i64 limits and strict name/width/arity/evaluator guards.
The independent signed reference reconstructs negative magnitudes safely in i64.

Controls pass for 512 poison results, 512 undef rejections, 512 budget/integer-
API rejections, twenty-eight metadata corruptions, eight argument-type mismatches,
twelve name/width mismatches and twenty result corruptions. Another 512 mixed-
family chains use all four declarations and reconstruct the inputs' XOR in
exactly six instructions. Primitive CALL/return takes two instructions.

Sanitized regressions pass 19,208,896 math comparisons (17,718,326 exact and
1,490,570 arithmetic NaN-class cases checking Vinix's preferred NaNs), 2,560
native legacy-extrema diagnostics, 2,230,560 exact funnel results, 1,329,400
zero-count value/tag comparisons and 743,134 exact bit-operation results, with
their controls. Mixed/intrinsic/FMA/count/bit/funnel/FP-class unit suites pass.
Separate full arithmetic/conversion/FMA/FP-class/integer-execution LLVM suites
were not rerun. LLVM/JIT/native code is not sanitizer-instrumented, leak detection
is disabled and retained allocation was not measured.

Generated C confirms fixed stack storage for the 744-entry declaration cache
and two attribute-group IDs, and unsigned key comparisons. Eleven disjoint
64-width integer ranges follow forty floating-overload slots. The existing
three owned execution arrays and cleanup remain. Mixed scalar units link as a
static little-endian AArch64 Linux ELF and pass header checks; no guest ran.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-integer-extrema-validation-20261112-r1/`

It contains source, every fixture/bitcode/comparison, binaries, generated C,
identities, logs and reproduction notes. Initial checker build logs retain a
V variable-shadowing typo fixed before reference execution. Selected V/LLVM
hashes match the pre-build receipt; full compiler/SDK/LLVM/JIT/fenv/sanitizer
dependency closures are not sealed. Existing usize warnings remain. The unchanged
complete typed inventory checker passes for the original and fresh restore under
`air-integer-extrema-restoration-20261112-r1/`, matching every path, byte, size,
type and permission. Full decoding/extraction exit zero. Restored sanitizer
integer-extrema units and all 1,303,888 comparisons pass again with their controls;
restored mixed/intrinsic/FMA/count/bit/funnel/FP-class units also pass. Post-replay
inventory and selected identity checks pass; receipts remain beside the bundles.

No AIR shader, iOS app, GPU command or new Fortnite probe ran. The default Metal
device stub still returns nil; no new frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `eeaab940f60e44f1e29a8075b25cac3d21cb171a67179e4aae33537be4f7027c` |
| Complete `.tar.zst` beside bundle | `1bc37d6c533e2ad166f7d7eef35580cf6451363ee20d0cc2f03b980d0abd82d2` |
| `source.tar`, revision `79c5fd7aa` | `2f91eabb2ea5ab33fd1ac3139f05a0478d5f599fe1c75761c0909fc57e856c9c` |
