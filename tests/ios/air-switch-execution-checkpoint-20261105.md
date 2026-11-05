# Scalar switch execution checkpoint — 2026-11-05

`9f31609b111c6adeacdb7fc2c021a9ee3f8f2f2a` adds bounded scalar integer switch
execution. Fortnite remains at **4/8 observed launch gates**, last seen at the
[GPU requirements alert](controller-discovery-checkpoint-20261104.md). No game
frame, menu, login or playable match is verified. The gate count is not an
engineering completion percentage.

The interpreter compares i1..i64 case bit patterns in decoded order, stopping
on a match or taking the default after the full scan. Shared destinations retain
the actual predecessor for PHIs. Empty tables still evaluate their condition;
poison/undef conditions reject. The existing decoder checks case literals,
uniqueness, scoped IDs and destinations. Wider integers and legacy range
encoding remain outside execution. Valid LLVM IR and matching immutable indexes
remain preconditions; this is not a general LLVM verifier.

Every visited instruction and tested switch case consumes one budget step.
`IRIntegerRun.steps` now reports that combined count, so large scans and repeated
dispatch use the same caller-supplied budget. Empty tables add no comparison
steps. No new execution arrays or host LLVM dependencies are introduced. See
[INTEGER.md](../../compat/ios/airbitcode/INTEGER.md).

Normal and ASan/UBSan unit runs pass eight groups: the existing arithmetic,
flags, select, branches and scoped-value checks plus switch case/default ordering,
zero/high-bit values, shared destinations, empty-table condition evaluation,
precise comparison/return budgets and matched/default self-loops. Existing
1,397,052 exhaustive narrow flag comparisons and 28 directed i64 limits pass.
The unchanged switch decoder suite also passes its wide/legacy/deferred checks,
18 directed corruptions, cumulative work limit and 93 mutations.

Both normal and sanitized reference runs pass **17,280 actual native LLVM MCJIT
comparisons across 134 functions**. The 1,664 new comparisons cover sparse
switches at i1/i2/i7/i8/i16/i31/i32/i63/i64, shared PHI edges, empty tables,
switch-controlled loops with simultaneous PHIs and all 256 keys in a dense i8
table. High incoming bits test truncation. Dense cases check exact step counts
and reject a budget one step short of completion. All 12 guarded errors, two
poison results and four corrupted-result controls pass. Guard/poison cases run
only in V. The reference tool LLVM-verifies and natively calls only its own
generated portable fixture; it cannot execute arbitrary AIR/application input.

LLVM and generated native reference code are not sanitizer-instrumented. Leak
detection is disabled; leaks were not measured. The unit program cross-compiles
and links as a static little-endian AArch64 Linux ELF and passes header
inspection. It has not run in a guest. No native AIR corpus scan, AIR shader,
iOS app, GPU workload or new Fortnite probe ran. The default Metal device stays
nil; memory, floating point/vectors, intrinsics, resources, pipelines, command
submission and presentation remain unfinished.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-switch-execution-validation-20261105-r1/`

The bundle contains committed source, original generated fixtures/bitcode,
assembler status, JIT identity, every comparison/step count, binaries, generated
target C, logs, identities and reproduction notes. All recorded host builds
completed without diagnostics. Compiler, SDK, LLVM dependency, JIT and sanitizer
runtime closures are not sealed. Installed identities pass recheck.

The unchanged complete inventory checker passes. A full fresh restore under
`air-switch-execution-restoration-20261105-r1/` matches every recorded path,
byte, size, type and permission. Restored unit and sanitized native-reference
runs pass again, including all 17,280 comparisons and guard/control cases.
Sibling logs retain the receipts. Archive and inventory hashes pass recheck.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-switch-execution-validation-20261105-r1.inventory.json` | `a854739c2a98cb1fb27eb2cbbcb3c85be50b7b488540238a1073266a2e4883ac` |
| `air-switch-execution-validation-20261105-r1.tar.zst` | `5cb2b572924af84013ca661cf9b2eb4e50395343f9aee788256c1265cdc00c57` |
| `source.tar`, revision `9f31609b1` | `59fa2ca98ad3bd6d33397aefb0ef772d60d66b4cc78eb69c332ba97e982cb7a8` |
| `unit-aarch64` | `f4ed6b4adcb90de3fe713c1c32f7be9227fd586fd7c4ab4a981e25091b30cd50` |

This qualifies scalar switch execution only. The prior game capture and
historical auditor rejection remain unchanged; no new launch gate is claimed.
