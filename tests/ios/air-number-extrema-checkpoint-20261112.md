# Number-preferring extrema checkpoint — 2026-11-12

`0f2b5138b` adds scalar half/float32 `llvm.minimumnum` and `llvm.maximumnum`.
Exactly one quiet or signaling NaN selects the other operand's exact numeric
bits; two NaNs choose the existing preferred positive quiet NaN. Numeric
ordering places negative zero below positive zero. Evaluation uses integer
bits without host FP, LLVM, libm or new allocation. Strict direct-call identity,
signature, header, attributes and work limits remain. Poison propagates;
selected undef errors. `minnum`/`maxnum`, other widths/vectors, fast-math and AIR
aliases remain unsupported. Valid IR and immutable matching indexes are required.

Normal and ASan/UBSan runs each pass **14,619,264 comparisons** over forty
functions: **13,161,614 exact** and **1,457,650 math NaN-class cases**, checking
Vinix's exact preferred NaN when the native result is NaN. All half encodings
and existing float edge/mixed/midpoint samples remain. Boundary sweeps now cover
four extrema operations: **8,392,704 pairs**, with every half encoding against
sixteen peers in both orders and full 32-by-32 float edge matrices. All new
extrema comparisons use native LLVM floating-point wrappers. The existing
[half copysign integer oracle](air-scalar-intrinsics-checkpoint-20261112.md)
still contributes 65,536 comparisons; the other 14,553,728 use native FP.

Thirty-two extrema poison/undef controls and all existing unsupported fixtures,
metadata/attribute/result corruptions, exponent-type guards, lazy select,
budget/integer isolation and fourteen rounding controls pass. Units pass
**176 exact extrema values** (88 new), existing sign/rounding/attribute guards,
32 sqrt patterns and 327,680 independent integer root checks. Sanitized mixed
scalar units pass thirteen groups, including 1,397,052 narrow flag cases and
28 i64 limits. The sanitized FMA regression passes **1,505,792 comparisons**.
Separate half/float arithmetic, conversion, half precision, half/integer and
standalone integer LLVM suites were not rerun; their implementations did not
change. Native references run only in the default environment. LLVM/JIT/native
code is not sanitizer-instrumented and leak detection is disabled.

The declaration cache grows to thirty-two fixed stack entries, confirmed in
generated mixed-scalar AArch64 C. Existing three owned execution arrays and
cleanup are unchanged; retained allocation was not measured. Intrinsic units
cross-compile/link as a static little-endian AArch64 Linux ELF and pass header
inspection; no guest execution ran. No AIR shader, application, Metal command,
GPU work or new Fortnite probe ran. The default Metal device remains nil; no
new frame or launch gate is verified.

The complete source/IR/bitcode/comparison/binary/C/log/reproduction bundle is:

`/Users/alex/Library/Caches/vinix-ios/air-number-extrema-validation-20261112-r1/`

Selected V/LLVM compiler hashes match their pre-build receipt. Full compiler,
SDK, LLVM/JIT/fenv/sanitizer dependency closures are not sealed. Existing usize
C FFI deprecation warnings remain. The unchanged complete typed inventory
checker passes for the original and fresh restored tree under
`air-number-extrema-restoration-20261112-r1/`, matching every recorded path,
byte, size, type and permission. Decoder/extractor exit zero; receipts live
beside the bundles. Restored sanitized units and all 14,619,264 reference
comparisons pass again with their guards and controls. This qualifies scalar
execution and evidence integrity only.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `077bcfea90b1d0d684d002df63a145d0c8baf8defaf721893b9ec47a32cd4b29` |
| Complete `.tar.zst` beside bundle | `730033ef82432e81e551b79051aa757a077da35ddc4a95c86ef8bf4308987612` |
| `source.tar`, revision `0f2b5138b` | `bf4cdc6a188f218979a48d9f4086de68440501eaac75d2a8816472a2b54a1af1` |
