# Legacy scalar extrema checkpoint — 2026-11-12

`bc7e3048a` adds `llvm.minnum.f16/f32` and `llvm.maxnum.f16/f32`. The interpreter
consistently chooses LLVM's permitted `minimumnum`/`maximumnum` refinement:
prefer the numeric operand over either NaN class, choose the preferred quiet
NaN for two NaNs, and order -0 below +0. Exact integer bit selection uses no
host FP, LLVM, libm or new allocation. Strict declaration/signature/header/
attribute admission remains; poison propagates and selected undef errors.
See [the contract and oracle distinction](../../compat/ios/airbitcode/SCALAR-INTRINSICS.md)
and [LLVM's explicit refinement rule](https://llvm.org/docs/LangRef.html#llvm-minnum-intrinsic).

Final normal and ASan/UBSan runs each pass **19,208,896 comparisons** across
44 functions: **17,718,326 exact** and **1,490,570 NaN-class cases**, checking
Vinix's exact preferred NaN. New legacy calls compare against native LLVM
minimumNumber/maximumNumber to qualify the chosen refinement. Separately,
`legacy-native.tsv` records **2,560 actual native legacy results**: 208 permitted
signaling-NaN propagation choices and zero signed-zero violations in the edge
matrices. These observations never relax production comparisons.

Coverage includes every half encoding, float edges/mixed-bit/rounding neighbors,
12,589,056 extrema boundary pairs, 196,608 square-root boundaries and 2,097,152
scaling pairs. Forty-eight extrema poison/undef and 24 new flags/arity/budget/
integer-isolation/zero-sign corruption controls pass, alongside existing guards,
metadata/attribute/result corruptions and fourteen rounding controls. Two
five-instruction chains mix all four legacy/refined declarations without cache
identity collisions. Earlier passing corpora precede only these two chains;
final qualification uses `reference-normal-final` and `reference-asan-final`.
The existing half-copysign native integer oracle and FP diagnostic remain.

Sanitized intrinsic units pass 264 exact extrema results, 28 sign/rounding
patterns, 32 roots and 327,680 independent root/remainder inequalities plus
attribute guards. Mixed scalar units pass thirteen groups, 1,397,052 narrow
integer flag cases and 28 i64 limits; FMA units pass 58 values and six unfused
controls. Separate full arithmetic/conversion/FMA LLVM oracles were not rerun.
Native LLVM/JIT code is not sanitizer-instrumented, leak detection is disabled,
and retained allocation was not measured. Generated C confirms the expanded
38-entry declaration cache is fixed stack storage. The existing three owned
execution arrays and cleanup remain. Mixed scalar units link as a static
little-endian AArch64 Linux ELF and pass header inspection; no guest ran.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-minnum-validation-20261112-r1/`

It contains source, IR/bitcode, every comparison, native diagnostics, binaries,
generated C, logs, identities and reproduction notes. Selected V/LLVM hashes
match the pre-build receipt; full compiler/SDK/LLVM/JIT/fenv/sanitizer dependency
closures are not sealed. Existing usize FFI warnings remain. The unchanged
complete typed inventory checker passes for the original and fresh restore
under `air-minnum-restoration-20261112-r1/`, matching every path, file byte,
size, type and permission. Full archive decoding/extraction exit zero. Restored
sanitized intrinsic/mixed/FMA units and all 19,208,896 comparisons pass again,
including native diagnostics, controls and mixed-name chains. Post-replay
inventory and selected identity checks pass; receipts remain beside the bundles.

No AIR shader, app, GPU command or new Fortnite probe ran. The default Metal
device stub still returns nil; no new frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `2d3bb91faf69518feef81b5cf51574c78076d2fe0e01a25942d79c75f601e5b2` |
| Complete `.tar.zst` beside bundle | `05537eb74bd6d9418af9342293786b907c8ff5abd536c8401bfa5706db557f9e` |
| `source.tar`, revision `bc7e3048a` | `ce6e417598d889fd1c024b850ec58c76a7b959f8038a75136ecad0c5e9eaad3f` |
