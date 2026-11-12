# Scalar square-root checkpoint — 2026-11-12

`9a58f28c8` adds scalar `llvm.sqrt.f16/f32` execution, rounded to nearest/ties
to even. Signed zeros and positive infinity retain their bits; negative nonzero
inputs and NaNs choose the existing preferred positive quiet NaN. An integer
restoring root/remainder calculation takes exactly 27 steps on at-most-54-bit
radicands. Three extra root bits and remainder sticky information feed one
final rounding in the existing packers. Positive subnormal inputs normalize
exactly; all nonzero finite roots are normal. Production invokes no host FP,
libm, LLVM or native function. See [the intrinsic contract](../../compat/ios/airbitcode/SCALAR-INTRINSICS.md).

The existing strict name/signature/arity/header/declaration-identity/attribute
admission remains. Its million-unit attribute-validation bound and one-step
CALL accounting are unchanged. Generated AArch64 C confirms the declaration
cache is a twenty-four-entry fixed stack array. No owned execution array or
cleanup changed. Other precisions, vectors, constrained/flagged/general calls
and AIR aliases remain unsupported. Valid LLVM IR and matching immutable
indexes are preconditions; this is not a full verifier.

Final normal and ASan/UBSan units pass **32 exact square-root results** and
**327,680 integer root/remainder checks** against independent multiplication
inequalities, including exact squares and neighbors near the 54-bit limit.
All prior 28 intrinsic/88 extrema exact results and attribute/name/width guards
pass. Sanitized mixed-scalar units pass thirteen groups, including 1,397,052
narrow integer flag comparisons and 28 i64 limits.

Qualified normal and sanitized LLVM references each pass **7,735,840
comparisons** over 34 primitive/chain/loop functions: **6,350,194 exact results**
and **1,385,646 arithmetic NaN-class cases**. Every half case receives all
65,536 encodings; every float case receives 32 edges, 65,536 mixed-bit inputs
and 65,536 integer-midpoint/neighbor inputs. The existing extrema boundary
sweeps contribute 4,196,352 comparisons. Square root adds 196,608 neighbors
of squared exact float-root midpoints, generated independently using u64
products/shifts across normal exponents. New fabs/sqrt chains check three-step
accounting; repeated-root loops exercise PHIs in both precisions.

Nine rejecting fixtures, three original poison results, sixteen extrema and
four square-root poison/undef controls, lazy select, budget/integer isolation,
eight call-metadata/two declaration-attribute/five result corruptions and ten
host-rounding controls pass. The four square-root rounding controls choose
sqrt(2) under upward rounding and sqrt(5) under downward rounding, distinguishing
nearest mode in both precisions. Retired unknown-sqrt guards now reject sin,
including in dead blocks. Native calls run only in LLVM's default environment.

The previous [native half `copysign` discrepancy](air-scalar-intrinsics-checkpoint-20261112.md)
reproduces. Its 65,536 comparisons retain the native LLVM integer bit-operation
oracle; the other **7,670,304 comparisons use native floating-point wrappers**,
including every new square-root case. Native NaNs compare class and Vinix's
exact preferred quiet representation. The initial failing copysign corpus
remains in the earlier complete archived bundle; no payload check was weakened.

Sanitized regressions pass **2,587,648 half arithmetic** and **649,216 float**
comparisons with their controls. Unchanged numeric-conversion, half-precision,
half/integer and standalone integer LLVM suites were not rerun. LLVM/JIT/native
code is not sanitizer-instrumented, leak detection is disabled, and retained
memory was not measured.

Both mixed-scalar and intrinsic units cross-compile/link as static little-endian
AArch64 Linux ELFs; header inspections pass. Neither ran in a guest. No AIR
shader, application, Metal command, GPU work or new Fortnite probe ran. The
[default Metal device](../../compat/ios/runner/metal_device.c.v) still returns
nil. No new launch gate, frame, menu, login or match is verified.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-scalar-sqrt-validation-20261112-r1/`

The bundle retains source, fixtures/IR/bitcode, every comparison, native
diagnostic, binaries, target C, logs, identities and reproduction notes.
Qualification uses `unit-normal-final`, `reference-normal-qualified` and the
sanitized builds; retained intermediate normal builds precede the two added
sqrt(5) unit values and the distinguishing downward-mode inputs. Builds use
V `0.5.2 596e18d` and LLVM `23.1.5`, retaining the existing `usize` C FFI warnings.
Selected compiler/header/library identities match the pre-build receipt.
Full compiler/SDK/LLVM/JIT/fenv/sanitizer dependency closures are not sealed.

The unchanged complete typed inventory checker passes for the original and
a fresh restore under `air-scalar-sqrt-restoration-20261112-r1/`, matching every
path, byte, size, type and permission. Restored sanitized units and all
7,735,840 reference comparisons pass again, including guards and controls.
The half `copysign` native diagnostic reproduces. Receipts are siblings outside
the bundle. This qualifies the supported scalar profile and evidence integrity
only.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-scalar-sqrt-validation-20261112-r1.inventory.json` | `25b6d80447e07c651f33305b34d9c176eda2055692053ceca9b694cb5b0a7a7e` |
| `air-scalar-sqrt-validation-20261112-r1.tar.zst` | `ed0e9e90136a2c8824279e34420d3aa62961540eaaba7d08ca7a426f750eef67` |
| `source.tar`, revision `9a58f28c8` | `a9b62c99950709457be9a43b338da51f74f6137a0acf2f085b8c48f2c0a5fcae` |
| `scalar-aarch64` | `cf521f2e2645c48d82788256153c017b34a7fd5a0b02b8dd96a89befcec382cb` |
| `intrinsics-aarch64` | `237e87ea5adc44750815b1e3328f483c971783f46bf05b97b9ea0e0e18d76c8a` |
