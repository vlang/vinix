# Scalar saturating arithmetic checkpoint — 2026-11-12

`fe66b8f52` adds mixed scalar execution of
`llvm.sadd.sat/uadd.sat/ssub.sat/usub.sat.iN` at every i1..i64 width. Signed
results clamp to the signed bounds; unsigned add clamps to the maximum and
unsigned subtract to zero. Saturation itself produces a defined value.
Input poison propagates; selected undef errors. Strict direct-call/name/width/
signature/header/attribute checks remain, as does the integer-only API's
no-call profile. See [the contract and maintained checkers](../../compat/ios/airbitcode/SCALAR-SATURATING.md)
and [LLVM semantics](https://llvm.org/docs/LangRef.html#saturation-arithmetic-intrinsics).

Production masks both inputs and uses unsigned arithmetic throughout. Unsigned
operations check margins before computing results. Signed operations use masked
modular arithmetic and input/result sign bits to detect overflow and choose a
limit, including at i1 and INT64_MIN. No host builtin, LLVM, FP or new allocation
participates in valid numerical evaluation. Unary integer evaluators reject
these binary families.

Normal and ASan/UBSan runs each pass **1,303,888 bit-exact native LLVM
comparisons** across 256 primitive functions, including **36,864 boundary
pairs**. Every i1..i8 pair is exhausted; wider widths receive 4,096 mixed-bit
pairs plus a twelve-by-twelve edge matrix. Signed minima/maxima and neighbors,
unsigned maxima/zero, alternating and byte patterns are covered, with incoming
high-bit noise on both arguments. Sanitized units pass another **1,303,888**
comparisons against an independent margin/carry reference, addition commutativity,
zero identities and strict name/width/arity/evaluator guards. Signed reference
arithmetic checks margins before computing any potentially overflowing result;
unsigned-add reference arithmetic uses two 32-bit limbs and an explicit carry.

Controls pass for 512 input-poison results, 512 undef rejections, 512 budget/
integer-API rejections, twenty-eight metadata corruptions, eight argument-type
mismatches, twelve name/width mismatches and twenty result corruptions. Another
512 mixed-family cache chains use all four declarations with zero identities
and reconstruct the inputs' XOR in six instructions. Primitive CALL/return
takes two instructions.

Sanitized regressions pass 656,892 abs value/tag comparisons (87 poison),
743,134 exact bit-operation results, 2,230,560 exact funnel results, 1,303,888
exact integer extrema and 19,208,896 math comparisons (17,718,326 exact and
1,490,570 arithmetic NaN-class cases checking Vinix's preferred NaNs), plus
2,560 native legacy-extrema diagnostics and all maintained controls. Mixed/
intrinsic/count/FP-class/extrema/bit/funnel/FMA/abs units pass. Separate full
arithmetic/conversion/FMA/FP-class/zero-count/integer-execution LLVM suites
were not rerun. LLVM/JIT/native code is not sanitizer-instrumented; leak
detection is disabled.

Generated C confirms unsigned numerical arithmetic, fixed stack storage for
the 1064-entry declaration cache and two attribute-group IDs. Sixteen disjoint
64-width integer ranges follow forty floating-overload slots. The existing
three owned execution arrays and cleanup remain. Mixed scalar units link as a
static little-endian AArch64 Linux ELF and pass header checks; no guest ran.
Retained allocation was not measured.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-saturating-validation-20261112-r1/`

It contains pinned source, every fixture/bitcode/comparison, binaries, generated
C, identities, logs and reproduction notes. Selected V/LLVM hashes match the
pre-build receipt; full compiler/SDK/LLVM/JIT/fenv/sanitizer dependency closures
are not sealed. Existing usize warnings remain. The unchanged complete typed
inventory checker passes for the original bundle and fresh restore under
`air-saturating-restoration-20261112-r1/`, matching every path, byte, size, type
and permission. Full decoding/extraction exit zero; the disposable decoded tar
was removed afterward. Restored sanitizer binaries pass all 1,303,888 LLVM
comparisons and controls again, plus saturating/mixed/intrinsic/count/FP-class/
extrema/bit/funnel/FMA/abs units. Post-replay full inventories, relative identities,
selected compiler hashes and the archive checksum pass. Receipts and replay
outputs remain beside the sealed bundles.

No AIR shader, iOS app, GPU command or new Fortnite probe ran. The default Metal
device stub still returns nil; no new frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `5b6539552cd4281da2575b32d872c320683b2818347b74ffb4103cb2ed4aa1bb` |
| Complete `.tar.zst` beside bundle | `cdbf27425bce09208cddbafbf019ae3489b19b10e4391b18d001354ba335574d` |
| `source.tar`, revision `fe66b8f52` | `294e8013a13128578554f0189122de73ecec55e43d60e4e53741e34b45d9ade7` |
