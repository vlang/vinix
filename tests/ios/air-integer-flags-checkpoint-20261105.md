# Integer execution flags checkpoint — 2026-11-05

`81838ffb969c66df985e6ba96cf36c105ace8c88` adds `nuw`/`nsw` execution for
integer add/sub/mul/shl and `exact` for udiv/sdiv/lshr/ashr. Fortnite remains at
**4/8 observed launch gates**, last seen at the
[GPU requirements alert](controller-discovery-checkpoint-20261104.md). No game
frame, menu, login or playable match is verified. The gate count is not an
engineering completion percentage.

Supported overflow, inexact and overshift results retain poison. Multiplication
checks unsigned magnitudes against signed/unsigned limits; shifts check discarded
bits or reverse reconstruction. Production evaluation uses unsigned u64 patterns
without host signed overflow, new execution arrays or an LLVM dependency.
Unknown/wrong-family bits, disjoint/samesign, cast flags and function attributes
remain unsupported. Existing division guards, poison propagation, lazy select,
simultaneous PHIs and instruction budgets remain active. Valid IR and matching
immutable indexes remain preconditions; this is not a full LLVM verifier.
See [INTEGER.md](../../compat/ios/airbitcode/INTEGER.md).

Normal and ASan/UBSan unit runs pass six groups, including **1,397,052 exhaustive
i1..i8 comparisons** against widened arithmetic, 28 directed i64 limits,
unknown/wrong-family flag masks, decoded flagged results/poison and budgets.
The sanitized native execution regression passes all 15,616 MCJIT comparisons,
nine guarded errors, two poison results and four corruption controls. Its
unsupported-flag fixture now uses OR-disjoint in place of supported add-NSW;
the prior source and original evidence remain archived.

The new maintained V reference tool executes original flagged instructions in
Vinix and generates a separate LLVM reference using unflagged i128 arithmetic,
range checks, safe masked shifts and nonzero divisors. That reference returns
defined result bits and an explicit poison tag. LLVM verifies and folds it with
instcombine; exact values/tags/widths/step counts must match. No unresolved
reference result is accepted. Both normal and sanitized runs pass:

| Width | Comparisons | Defined values | Poison tags |
| --- | ---: | ---: | ---: |
| i1 | 2,048 | 1,536 | 512 |
| i8 | 2,048 | 812 | 1,236 |
| i16 | 2,048 | 832 | 1,216 |
| i32 | 2,048 | 845 | 1,203 |
| i64 | 2,048 | 820 | 1,228 |
| Total | **10,240** | **4,845** | **5,395** |

Each width rejects four corrupted results (20 total). Division inputs exclude
immediate zero/overflow UB. The new reference tool makes no native/JIT function
calls. LLVM itself and the baseline regression's generated machine code are not
sanitizer-instrumented. Leak detection is disabled; leaks were not measured.

The unit program cross-compiles and links as a static little-endian AArch64
Linux ELF and passes header inspection. It has not run in a guest. No AIR corpus
scan, AIR shader, iOS app, GPU workload or new Fortnite probe ran. The default
Metal device remains nil; memory, floating point/vectors, intrinsics, resources,
pipelines, command submission and presentation remain unfinished.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-integer-flags-validation-20261105-r1/`

Qualification uses `unit-*-final`, `flags-*-r2`, `execution-asan-final` and
`unit-aarch64-final`. Original/oracle source and bitcode, folded IR, all rows,
assembly statuses, binaries, logs, source archive, identities and reproduction
notes are retained. The initial oversized fixture's work-limit rejection and
direct-fold comparison failure remain preserved. Per-width modules satisfy the
unchanged parser limits. A direct optimized flagged return cannot establish an
exact poison oracle because LLVM may
[replace poison with an ordinary value](https://llvm.org/docs/LangRef.html#poison-values);
the final reference represents the tag as defined data. Initial compiler notice
and failed results are distinct from the passing r2 runs.

The unchanged complete inventory checker passes. A full fresh restore under
`air-integer-flags-restoration-20261105-r1/` matches every recorded path, byte,
size, type and permission. Restored unit and sanitized reference tests pass
again, including all 10,240 comparisons and 20 controls. Sibling logs preserve
those receipts. Installed identities and archive/inventory hashes pass recheck.
Compiler, SDK, LLVM dependency, JIT and sanitizer runtime closures are not sealed.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-integer-flags-validation-20261105-r1.inventory.json` | `ea95b2350e78d4eec987f328ee24416169be5ccd2ae54733ea619303c3c09e53` |
| `air-integer-flags-validation-20261105-r1.tar.zst` | `53bc2425647c11f94c773716646c2ae9757f1064d0bfc5f8ca8e60be1215598f` |
| `source.tar`, revision `81838ffb9` | `ca392279fc531b88204123eb02ecc12ea087ee58b8d16e7f0c36ce5a5a590c1a` |
| `unit-aarch64-final` | `976bd3d44030016fe01e4ff7094e56ace88b4f5dd8b8a63deff11c87cf138325` |

This qualifies the supported scalar integer flags only. The prior game capture
and historical auditor rejection are unchanged; no new launch gate is claimed.
