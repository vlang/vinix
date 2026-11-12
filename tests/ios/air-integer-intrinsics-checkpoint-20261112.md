# Scalar integer bit intrinsics checkpoint — 2026-11-12

`c9f10109d` adds `llvm.ctpop.i1..i64`, `llvm.bitreverse.i1..i64` and
`llvm.bswap.i16/i32/i48/i64` to the mixed scalar interpreter. Unsigned loops
use at most 64 bit iterations or eight bytes, with no host builtins, LLVM, FP
or new allocation. Exact name/width/signature/direct-call checks retain the
existing attribute/flag policy. Poison propagates and selected undef errors.
The integer-only entry point keeps its no-call profile. See
[the contract and maintained checker](../../compat/ios/airbitcode/SCALAR-INTEGER-INTRINSICS.md)
and [LLVM bit operations](https://llvm.org/docs/LangRef.html#bit-manipulation-intrinsics).

Normal and ASan/UBSan runs each pass **743,134 exact native LLVM comparisons**
over 132 primitives and 258 chains using all declarations together. Coverage
exhausts every i1..i16 input and supplies 4,096 mixed-bit wide values per
overload, plus edge patterns and every single-set/single-clear bit. Incoming
high bits check masking. Chains take exactly 323 instructions; independent
zero/all-one totals are 0/2080. Controls pass for 132 poison results, 132 undef
rejections, 264 budget/integer-API rejections, 21 metadata corruptions, nine
name/width mismatches and fifteen result corruptions. Sanitized unit tests pass
**733,180 standard-library bit-operation comparisons**, reversal involutions
and strict name/width/arity guards, including i48 and i64 limits.

Sanitized regressions pass 2,400,256 exact floating-classification comparisons,
17,280 exact integer-execution comparisons and 19,208,896 math comparisons
(17,718,326 exact and 1,490,570 arithmetic NaN-class cases checking Vinix's exact
preferred NaNs), with their controls and 2,560 native legacy-extrema diagnostics.
Intrinsic/FP-class/FMA/mixed-scalar units also pass their existing cases, including
264 extrema values, 327,680 root inequalities, 40,960 class/mask cases, 1,397,052
narrow integer flag cases, 28 i64 limits and 58 FMA values. Separate full
arithmetic/conversion/FMA LLVM oracles were not rerun. LLVM/JIT/native code is
not sanitizer-instrumented, leak detection is disabled and retained allocation
was not measured.

Generated C confirms the expanded 232-entry declaration cache and two
attribute-group IDs use fixed stack storage. Three disjoint 64-width integer
ranges follow forty floating-overload slots; only four byte-swap slots admit
calls. The existing three owned execution arrays and cleanup remain. Mixed
scalar units link as a static little-endian AArch64 Linux ELF and pass header
checks; no guest execution ran.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-integer-intrinsics-validation-20261112-r1/`

It contains source, every fixture/bitcode/comparison, binaries, generated C,
identities, logs and reproduction notes. Selected V/LLVM hashes match the
pre-build receipt; full compiler/SDK/LLVM/JIT/fenv/sanitizer dependency closures
are not sealed. Existing usize FFI warnings remain. The unchanged complete
typed inventory checker passes for the original and fresh restore under
`air-integer-intrinsics-restoration-20261112-r1/`, matching every path, byte,
size, type and permission. Full decoding/extraction exit zero. Restored sanitizer
bit units and all 743,134 comparisons pass again with their controls; restored
intrinsic/FP-class/FMA/mixed units also pass. Post-replay inventory and selected
identity checks pass. Receipts remain beside the bundles.

No AIR shader, iOS app, GPU command or new Fortnite probe ran. The default Metal
device stub still returns nil; no new frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `7f84db13f1cce8a1436fd7520be1d8c1de2860f46ae1a79aabc076a1a5528ee6` |
| Complete `.tar.zst` beside bundle | `23fbcdf96998f1b904276c535dd323e693fd2272163e3d4f7142dfa812ba9d75` |
| `source.tar`, revision `c9f10109d` | `9de3376a25565cb5264213c8407140bb1b04615e307893e2df4ba9afd7bd6465` |
