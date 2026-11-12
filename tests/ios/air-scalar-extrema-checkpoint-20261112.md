# Scalar minimum/maximum checkpoint — 2026-11-12

`cd230b1f2` adds direct scalar `llvm.minimum.f16/f32` and
`llvm.maximum.f16/f32` execution. Both propagate NaNs to the existing preferred
positive quiet representation, select exact numeric input bits, and order
negative zero below positive zero in either argument order. Production uses
integer bits without host FP instructions, libm, LLVM or native invocation.
See [the supported intrinsic contract](../../compat/ios/airbitcode/SCALAR-INTRINSICS.md).

The existing strict direct-declaration identity, homogeneous signature,
arity, header, convention, address-space and attribute checks remain. The
shared million-unit attribute-validation bound is unchanged. A twenty-two-entry
fixed stack array caches declarations; generated AArch64 C confirms that
storage. No owned execution array or cleanup changed. Each CALL costs one
instruction. General/flagged calls, AIR aliases and other minimum/maximum
families remain unsupported. Valid LLVM IR and matching immutable indexes
remain preconditions; this is not a full verifier.

Normal and ASan/UBSan intrinsic units pass 88 new exact extrema results,
alongside the existing 28 exact patterns and attribute/name/width guards.
Sanitized mixed-scalar units pass thirteen groups, including 1,397,052
narrow integer flag comparisons and 28 i64 limits.

Normal and sanitized LLVM references each pass **6,949,312 comparisons**
across 28 primitive/chain/loop functions: **5,764,708 exact results** and
**1,184,604 arithmetic NaN-class cases**. Every half case receives all
65,536 encodings; every float case receives 32 edges, 65,536 mixed-bit inputs
and 65,536 midpoint/neighbor inputs across exponents 0..22. Extrema additionally
exhaust every half encoding against sixteen boundary peers in both orders
(4,194,304 comparisons), and a 32-by-32 float edge matrix (2,048 comparisons).
The extrema chain checks both new operations and exact three-step accounting.

Nine rejecting fixtures, three original poison results, sixteen extrema
poison/undef controls, lazy select, budget/integer-only isolation, eight
call-metadata corruptions, two declaration-attribute corruptions, five result
corruptions and six host-rounding controls pass. Native NaN results compare
their class and Vinix's exact preferred representation. Native calls run
only in LLVM's default environment.

The prior [half `copysign` native discrepancy](air-scalar-intrinsics-checkpoint-20261112.md)
reproduces: `0x7c01` with a negative sign returns `0xfe01` rather than the
bit-preserving `0xfc01`. That primitive retains its 65,536 native LLVM integer
bit-operation reference comparisons. The other 6,883,776 comparisons use native
floating-point wrappers, including every new extrema comparison. Its initial
failing corpus remains in the previous checkpoint's complete archived bundle;
no payload check or production behavior was weakened.

Sanitized regressions pass **2,587,648 half arithmetic** and **649,216 float**
comparisons and their controls. Unchanged numeric-conversion, half-precision,
half/integer and standalone integer LLVM suites were not rerun. LLVM/JIT/native
code is not sanitizer-instrumented, leak detection is disabled, and retained
memory was not measured.

Both mixed-scalar and intrinsic unit programs cross-compile/link as static
little-endian AArch64 Linux ELFs; header inspections pass. Neither ran in a
guest. No AIR shader, application, Metal command, GPU submission or new Fortnite
probe ran. The [default Metal device](../../compat/ios/runner/metal_device.c.v)
still returns nil. No new launch gate, frame, menu, login or match is verified.

The complete evidence bundle is outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-scalar-extrema-validation-20261112-r1/`

It retains source, fixtures/IR/bitcode, every comparison, native diagnostic,
binaries, generated target C, logs, identities and reproduction notes. Builds
use V `0.5.2 596e18d` and LLVM `23.1.5`; the reference C bindings retain their
`usize` deprecation warnings. Selected compiler identities match their
pre-build receipt. Full compiler/SDK/LLVM/JIT/fenv/sanitizer dependency closures
are not sealed.

The unchanged complete typed inventory checker passes for the original bundle
and a fresh restore under `air-scalar-extrema-restoration-20261112-r1/`, matching
every path, byte, size, type and permission. Restored sanitized units and all
6,949,312 reference comparisons pass again, including guards and controls.
The native half `copysign` diagnostic reproduces. Replay receipts are stored
beside the restored bundle. These checks qualify scalar execution and evidence
integrity only.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-scalar-extrema-validation-20261112-r1.inventory.json` | `6256fa242ffb10cfdf8f9db0665b71903b5b03c3d422869f334154fa1a656d6e` |
| `air-scalar-extrema-validation-20261112-r1.tar.zst` | `341523eb0804b781571476b8d4a4e626cf88565fd84ddb54f5d3deef4a9c90e0` |
| `source.tar`, revision `cd230b1f2` | `ccf5e3da7c443ec3a4ec83af76ded986ea7d273a7a4e1e27548ad1ecc23da309` |
| `scalar-aarch64` | `0774135a59683326b46d77ede3498b35fea5913b3ebd1754104dafdccb55f0d4` |
| `intrinsics-aarch64` | `5037b83a131e4d5f1731102ce31ca0d25cec4a2b023b4ca872314029ee625d96` |
