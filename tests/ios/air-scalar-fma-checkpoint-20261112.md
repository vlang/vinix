# Scalar fused multiply-add checkpoint — 2026-11-12

`9086dc055` adds direct scalar `llvm.fma.f16/f32` calls with three homogeneous
operands. The product and addend remain exact through cancellation, with one
nearest/ties-to-even rounding afterward. Two nine-u64 stack arrays retain the
sum on a `2^-298` grid, covering binary32 products through bit 553 and addends
through bit 425. Half fits the same representation. Limb passes take at most
nine iterations and highest-word normalization at most 63 shifts. Production
uses integer operations without host FP, libm, LLVM or native invocation.
See [the FMA contract](../../compat/ios/airbitcode/SCALAR-FMA.md).

The existing strict direct identity/signature/header/attribute admission and
million-unit attribute-validation bound remain. The ternary signature is
checked before runtime reads; poison in any operand propagates and selected
undef errors. Each CALL costs one instruction. Generated AArch64 C confirms
the limb arrays and twenty-six-entry declaration cache are fixed stack storage.
No owned execution array or cleanup changed. Other precisions/vectors,
flagged/constrained/general calls, AIR aliases and `fmuladd` remain unsupported.
Valid LLVM IR and matching immutable indexes are preconditions.

Final normal and ASan/UBSan units pass **58 exact results** and six explicit
controls distinguishing fused from separate arithmetic. Cases include signed
zeros, NaNs/infinities, cancellation, overflow rescue, underflow ties and tiny
perturbations on both sides of a product midpoint. Arity/name/width guards pass.

Qualified normal and sanitized LLVM runs each pass **1,505,792 comparisons**
across eight primitive/swapped/chain/four-iteration-loop functions:
**1,394,878 exact results** and **110,914 NaN-class cases**, with Vinix's exact
preferred quiet representation checked for native NaNs. Every function receives
all 20-by-20-by-20 boundary triples. Half sweeps put every encoding in all three
operand positions with mixed-bit peers; float cases receive 131,072 mixed-bit
triples. Arguments carry high bits to check masking. All FMA references use
native floating-point wrappers in LLVM's default environment.

An additional 131,072 cancellation triples use the negative of a separately
rounded native product as addend; **130,784 distinguish fusion** from separate
native multiply/add. Six poison, six undef, six metadata (including malformed
third-operand types), five result-corruption and four distinguishing rounding
controls pass, alongside budget/integer-only isolation. Primitive/swapped paths
take two instructions, chains three and the four-iteration PHI loops twenty-six.

Sanitized regressions pass **7,735,840 existing intrinsic comparisons**,
**2,587,648 half arithmetic** and **649,216 float** comparisons and all controls.
Legacy intrinsic units pass their exact values, attributes and 327,680 integer
root checks; mixed-scalar units pass thirteen groups, including 1,397,052 narrow
flag cases and 28 i64 limits. The legacy intrinsic reference retains its
[documented half `copysign` integer oracle](air-scalar-intrinsics-checkpoint-20261112.md).
Unchanged conversion, half-precision, half/integer and standalone integer LLVM
suites were not rerun. LLVM/JIT/native code is not sanitizer-instrumented,
leak detection is disabled, and retained memory was not measured.

Mixed-scalar and FMA units both cross-compile/link as static little-endian
AArch64 Linux ELFs; header inspections pass. Neither ran in a guest. No AIR
shader, application, Metal command, GPU work or new Fortnite probe ran. The
[default Metal device](../../compat/ios/runner/metal_device.c.v) remains nil.
No new frame or launch gate is verified.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-scalar-fma-validation-20261112-r1/`

The bundle contains source, fixtures/IR/bitcode, all comparison rows, binaries,
target C, identities, logs and reproduction notes. Qualification uses
`unit-normal-final`, `reference-normal-qualified` and `reference-asan-qualified`.
Retained intermediate units precede four midpoint-perturbation values; initial
reference runs precede two third-operand type controls. Builds use V
`0.5.2 596e18d` and LLVM `23.1.5`, retaining existing `usize` C FFI warnings.
Selected compiler/header/library identities match the pre-build receipt.
Full compiler/SDK/LLVM/JIT/fenv/sanitizer dependency closures are not sealed.

The unchanged complete typed inventory checker passes for the original and
fresh restored trees. The initial r1 extraction pipeline exited 141 (SIGPIPE)
despite matching every recorded entry. A full compressed-stream test passes;
complete file decoding and extraction to `air-scalar-fma-restoration-20261112-r2/`
both exit zero. Its full inventory matches every path, byte, size, type and
permission. Restored sanitized FMA, mixed-scalar and intrinsic units pass, and
all 1,505,792 FMA comparisons pass again with their controls. The initial status
and clean r2 receipts remain beside the bundles. These checks qualify scalar
execution and evidence integrity only.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-scalar-fma-validation-20261112-r1.inventory.json` | `604b48cb75a99f804ff3ed2bd7d698366d3804ba3e6dd65dc27343ba23dbce85` |
| `air-scalar-fma-validation-20261112-r1.tar.zst` | `27f150324c2c6eff6f7a3806a38173b44c4b0630dd24935f19f3a7422d6b4967` |
| `source.tar`, revision `9086dc055` | `cf01eee58e2d75922ebbdd163ed55e8f4136398e22b9af010a69282c1f3e60d7` |
| `scalar-aarch64` | `2143a67701a6b21a3830a2902c92d84044534a05e71d092e67fe9a2d245f7e2b` |
| `fma-aarch64` | `034438a137a8b9023055149e6e970b6fd9e33ceaa1fbda84f53b528e16ee478c` |
