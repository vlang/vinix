# Software Metal integer bit intrinsics — 2026-11-13

`be73624d6` admits direct LLVM `ctpop`, `bitreverse`, `bswap`, `ctlz` and
`cttz` calls in bounded AIR buffer kernels and opt-in software Metal compute.
Counts/reversal support i1..i64; byte swap supports i16/i32/i48/i64. Each call
costs one step. Scalar and buffer execution share the existing intrinsic
evaluator, extracted without changing its arithmetic. See
[MEMORY-EXECUTION.md](../../compat/ios/airbitcode/MEMORY-EXECUTION.md).

Preflight reuses the scalar declaration identity, name, signature, calling
convention and attribute checks. Only these five families are admitted;
general calls, other intrinsics, indirect/tail calls, call-site attributes and
fast-math calls remain unsupported. Declaration attributes are checked once
per profile with a cumulative work limit. Each call's signature and literal
defined i1 zero-poison flag are checked independently. Execution never invokes
a declaration or host function pointer.

Poison input propagates; undef rejects. For zero-count calls, zero input
returns the width with a false flag and poison with a true flag. A poison
store rejects; freeze may make its existing fixed-zero choice. Buffer memory
shadow tracking, rollback and general shader execution are not added.

Normal and ASan/UBSan checks each pass 99,328 exact native LLVM comparisons:
388 load/call/store functions, 256 inputs each, including both zero-count flag
variants. Inputs cover each single set bit, their complements, mixed patterns
and defined zero cases. True-flag zero inputs are excluded from native calls.
Only unused native narrow-integer padding is masked; interpreter padding must
be zero. Sentinels, exact four-step execution and insufficient budgets without
writes are checked. The native reference uses explicit MCJIT optimization
level 2 with FastISel disabled.

Another 906 controls cover poison/undef inputs, true-flag zero poison, rejected
ordinary calls and rejected non-bit intrinsics. There are 128 successful frozen
zero-poison results and nine rejected call-metadata mutations after a store.
Two mixed-flag controls reuse an admitted declaration, combine false-flag
width results with frozen true-flag poison, and reject a nonconstant second
flag before writing. Their first test run expected a different diagnostic;
the maintained check now expects the constant-pool rejection actually returned.
Earlier logs remain in the bundle.

Sanitized regressions pass all 16 integer/mixed unit groups, 743,134 scalar
integer-intrinsic comparisons, 1,329,400 zero-count value/tag comparisons and
327,680 overflow-pair flow comparisons, including existing controls. The full
floating-intrinsic suite passes 19,208,896 comparisons, with 1,490,570 arithmetic
NaN-class matches and its rounding, declaration, metadata and corruption
controls. Its 2,560 legacy native extrema diagnostics retain 208 permitted
signaling-NaN choices and zero signed-zero backend violations. Existing
reference/refinement rules are unchanged. LLVM JIT-generated reference code
is not sanitizer-instrumented; the interpreter and checkers are.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
New deferred kernels combine all five operations on `0x01234567`, producing
`0x80c4a2e6` after reversal/byte swap. Population count plus leading/trailing
counts of `0x100` yields 43. A second kernel freezes true-flag zero-count
poison, yielding 12. Offset bindings, live inputs changed after encoding,
pipeline lifetimes, two output stores and command completion are exercised.
The ordinary runner was not rebuilt.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/air-memory-bits-validation-20261113-r1/`

The complete sibling archive was decoded and extracted to fresh `-restored`.
Saved source/compiler/header/executable identities match. All seven restored
sanitizer suites pass again with fresh external fixtures, including the full
floating suite and all software Metal groups with normal hashing. The archive
checksum passes afterward. Restore receipts remain beside the bundle; original
evidence is retained. The compiler snapshot was saved after checks. The software
harness retains its documented compiler-preamble corrections. Toolchain library
symlinks, SDKs, assembler and dylibs remain external prerequisites; complete
dependency closures are not sealed. This is not a full typed-inventory audit.
Leak detection is disabled; runtime object drainage is checked, retained heap
is not measured.

Compute remains a bounded single-thread CPU interpreter with valid LLVM IR as
a precondition. Synthetic LLVM/AIR fixtures do not establish compatibility
with Apple compiler-produced kernels. No GPU execution, presentation, Vinix
guest, Fortnite frame or launch gate is verified by this checkpoint.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `4d36e54313d0e73fcf779d1d23d39c04fb36a6f5a1d83191e2f03af10619607f` |
| `source.tar`, revision `be73624d6` | `8da5a915cba7365608bdf4e1b3ad2d787b56f57ad307f93ade3e93d17b228bab` |
