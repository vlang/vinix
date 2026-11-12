# Scalar classification checkpoint — 2026-11-12

`d53ee9fb0` adds `llvm.is.fpclass.f16/f32`: half/float input, constant i32
class mask and i1 result. Integer bit tests distinguish ten classes, including
signaling/quiet NaNs, signed zeros and subnormals, without host FP, libm or LLVM.
Admission checks the input overload, boolean result, signature/direct identity,
flags and every call's constant mask in 0..1023. Only classification admits
parameter two's exact `immarg` declaration attribute. Poison propagates and
selected undef errors. See [the contract and maintained checker](../../compat/ios/airbitcode/SCALAR-FPCLASS.md)
and [LLVM semantics](https://llvm.org/docs/LangRef.html#llvm-is-fpclass-intrinsic).

Qualified normal and ASan/UBSan runs each pass **2,400,256 bit-exact native LLVM
comparisons** over 2,048 functions. All 1,024 masks receive twenty class/boundary
inputs per precision. Eighteen masks additionally receive all half encodings
and 65,536 mixed-bit float inputs. High-bit noise checks argument masking.
Two poison, two undef, forty branch/PHI, eighteen metadata/budget/integer-API,
twenty-four malformed-mask and ten result-corruption controls pass. Twenty-four
environment controls retain exact predicates under upward/downward/toward-zero
rounding and leave all FP exception flags clear. Qualified sanitizer units pass
40,960 exact class/mask values and exact immarg/slot/encoding/duplicate/work
boundary guards. Native LLVM/JIT code is not sanitizer-instrumented; leak
detection is disabled and retained allocation was not measured.

The existing sanitizer intrinsic reference also passes **19,208,896 comparisons**
(17,718,326 exact and 1,490,570 arithmetic NaN-class cases) and its controls.
Intrinsic/mixed/FMA sanitizer units pass their existing cases, including 264
extrema values, 327,680 root inequalities, 1,397,052 narrow integer flag cases,
28 i64 limits and 58 FMA values. These regressions ran after the shared validator
refactor and before the final classification-only attribute-work charge; their
paths do not admit that attribute. Separate full arithmetic/conversion/FMA LLVM
oracles were not rerun. Generated C confirms a forty-entry declaration cache
and two attribute-group IDs on the stack; the existing three owned execution
arrays and cleanup remain. Qualified mixed scalar units link as a static
little-endian AArch64 Linux ELF; header checks pass, without guest execution.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-fpclass-validation-20261112-r1/`

It contains source, all fixtures/bitcode/comparisons, binaries, generated C,
identities, logs and reproduction notes. Qualification uses `reference-*-qualified`
and `unit-asan-qualified`. The initial numerical corpus passed but its harness
mistakenly expected seven branch/PHI instructions instead of six; that failure
and complete corpus are retained. Intermediate passing runs precede only the
final classification attribute-work charge and exact-bound unit check.
Selected V/LLVM hashes match the pre-build receipt; complete compiler/SDK/LLVM/
JIT/fenv/sanitizer dependency closures are not sealed. Existing usize warnings
remain. The unchanged complete typed inventory checker passes for the original
and fresh restore under `air-fpclass-restoration-20261112-r1/`, matching every
path, byte, size, type and permission. Full decoding/extraction exit zero.
Restored qualified sanitizer class units and all 2,400,256 comparisons pass again
with their controls; restored intrinsic/mixed/FMA units also pass. Post-replay
inventory and selected identity checks pass. Receipts remain beside the bundles.

No AIR shader, iOS app, GPU command or new Fortnite probe ran. The default Metal
device stub still returns nil; no new frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `1f2fac30ba2f991e17eaf89bb27b14f409864425c856c91ca1dbdc341e295984` |
| Complete `.tar.zst` beside bundle | `a1b9d25043a242809731e56d66c98a3be5dea8873142d13b0b530c4c62cbf3b6` |
| `source.tar`, revision `d53ee9fb0` | `dfed963fc3faac0ccd8ecb63d76c30f6484130f136069fcd6ad16976442398a8` |
