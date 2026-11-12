# Bounded scalar intrinsic execution checkpoint — 2026-11-12

`e8d7e3d48` adds direct scalar LLVM `fabs`, `copysign`, `floor`, `ceil`, `trunc`,
`round`, `roundeven`, `rint` and `nearbyint` calls for half and float32.
Fortnite retains its historical **4/8 observed launch gates** and
[GPU requirements alert](controller-discovery-checkpoint-20261104.md), with
no verified frame, menu, login or playable match. The gate count does not
measure engineering completion.

Admission checks exact names, homogeneous scalar signatures, arity/return type,
direct declaration identity through the constant pool, linkage, convention,
address space, header flags and attributes. The interpreter never reads a
callee as a runtime pointer or invokes host code. Call-site attributes and
unsupported declaration attributes reject; the latter admit only whitelisted
function properties and `memory(none)` versions 0/1/2. Attribute scans share
a million record/attribute validation units. An eighteen-entry fixed stack
cache checks each admitted declaration once per run. Generated C confirms
that cache is a stack array; the existing three owned execution arrays and
their cleanup remain unchanged. Each intrinsic CALL costs one instruction.
Integer-only behavior and the existing execution budget are preserved.

Evaluation uses integer sign/exponent/fraction bits and the default LLVM FP
environment, with no host FP instruction, libm or LLVM production dependency.
`fabs`/`copysign` preserve NaN payload/quiet bits exactly. Rounding chooses the
preferred quiet NaN, preserves signed zeros/infinities, and propagates poison;
selected undef errors. General/indirect/defined/tail/bundled calls, other
overloads, dynamic/constrained FP environments and AIR-named aliases remain
unsupported. Valid LLVM IR and matching immutable indexes are preconditions.
See [SCALAR-INTRINSICS.md](../../compat/ios/airbitcode/SCALAR-INTRINSICS.md).

Normal and ASan/UBSan units pass 28 exact value patterns and name/width/
attribute/version/memory/strictfp/string/return/parameter/missing/budget guards.
The thirteen existing mixed unit groups pass, including 1,397,052 narrow
integer flag comparisons and 28 i64 limits.

Both qualified normal and sanitized reference runs pass **2,163,040
comparisons** across 22 primitive/chain/loop functions. Every half encoding
runs through every half case. Float cases receive 32 edges, 65,536 mixed-bit
inputs and 65,536 signed integer-midpoint/neighbor inputs across exponents
0..22. **2,140,055 results compare bit for bit**; **22,985 rounding/arithmetic
NaNs** compare native class and Vinix's exact preferred representation. Nine
rejecting fixtures, three poison results, lazy select, budget/integer isolation,
eight call-metadata corruptions, two actual declaration-attribute corruptions,
five result corruptions and six distinguishing host-rounding controls pass.
Native reference calls use only the default environment.

The host LLVM half `copysign` quiets signaling NaNs: input `0x7c01` with negative
sign returns `0xfe01`, while its
[bit-preserving contract](https://llvm.org/docs/LangRef.html#llvm-copysign-intrinsic)
requires `0xfc01`. The initial fixture/bitcode, partial comparisons with the
FAIL row, and a reproducible native diagnostic are retained. This one primitive
uses a defined native LLVM integer bit-operation oracle for all 65,536 inputs;
the remaining 2,097,504 comparisons use native floating-point wrappers. Payload
checks remain exact and production semantics were not changed. The lowering
mechanism of the native discrepancy was not qualified.

Sanitized regressions pass **2,587,648 half arithmetic comparisons**,
**649,216 float comparisons**, **1,064,960 numeric conversion comparisons**
and **17,280 integer comparisons**, with their controls. LLVM/JIT/native code
is not sanitizer-instrumented; leak detection is disabled and retained memory
was not measured. The unchanged half precision and half/integer exhaustive
oracles were not rerun.

Mixed scalar and intrinsic unit programs both cross-compile and link as static
little-endian AArch64 Linux ELFs and pass header inspection. Neither ran in
a guest. No AIR corpus qualification, AIR shader, iOS application, Metal command,
GPU work or new Fortnite probe ran. The
[default Metal device](../../compat/ios/runner/metal_device.c.v) still returns
nil. Vectors, memory, AIR-specific intrinsic semantics, resources, pipelines,
submission and presentation remain unfinished.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-scalar-intrinsics-validation-20261112-r1/`

The bundle contains committed source, original/generated IR/bitcode, every
comparison, diagnostic/intermediate corpora, assembler/JIT/fenv identities,
binaries, target C, logs and reproduction notes. Builds use V `0.5.2 596e18d`;
LLVM C bindings emit `usize` deprecation warnings. Unit/AArch64 build diagnostics
are empty. Selected compiler/header identities match the pre-build receipt
and pass recheck. Full compiler/SDK/LLVM/JIT/fenv/sanitizer dependency closures
are not sealed.

The unchanged complete typed inventory checker passes for the original and
a fresh full restore under `air-scalar-intrinsics-restoration-20261112-r1/`.
Every recorded path, byte, size, type and permission matches. Restored sanitized
units and all 2,163,040 reference comparisons pass again, including guards and
controls. The half `copysign` native diagnostic reproduces. Sibling logs preserve
the receipts. This qualifies the supported scalar intrinsic profile and evidence
integrity only.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-scalar-intrinsics-validation-20261112-r1.inventory.json` | `be1f56dfdb44bef8f3002d3940332303ab79d9d86a401342e55544bdacc35612` |
| `air-scalar-intrinsics-validation-20261112-r1.tar.zst` | `5c9f95e00f50645500e2b782f37b9fbdcf854ece4913fa8c9f68d41660044fe4` |
| `source.tar`, revision `e8d7e3d48` | `6c912de70cd763faf0a928febf69c658f2b7b23622e105e575a168d8c77300b2` |
| `scalar-aarch64` | `4b4b063b816e89cd5c3a9065fc15007e2affa8b1e3c489316e6048402a96b955` |
| `intrinsics-aarch64` | `31465ae65a1e6427868a8d93346260ce765d0181a75dcc472843abf1f33e5fd7` |
