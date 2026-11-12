# Software Metal integer arithmetic flags — 2026-11-13

`a395b3956` admits integer `nuw`/`nsw` on add/sub/mul/shl and `exact` on
udiv/sdiv/lshr/ashr in bounded AIR buffer kernels and opt-in software Metal
compute. Preflight uses the existing scalar flag mask for each integer opcode;
the existing evaluator supplies values and poison. Unknown/wrong-family bits
and floating fast-math flags still reject. Flags add no execution steps.
See [MEMORY-EXECUTION.md](../../compat/ios/airbitcode/MEMORY-EXECUTION.md).

Violated wrap/exact promises and overshifts produce poison. A poison store
rejects, select may discard poison and freeze can make its defined choice.
Division by zero, signed division overflow and poison division operands retain
their existing dynamic errors. Earlier stores can remain visible after a
dynamic error. This change does not add rollback or memory shadow tracking.

Normal and ASan/UBSan runs each pass 131,072 comparisons across every width
i1..i64: 53,979 defined values and 77,093 rejected poison stores. Each width
checks 2,048 load/compute/store functions covering all sixteen opcode/flag
combinations, 128 input pairs each. Inputs include signed/unsigned boundaries,
zero, one, shift-width edges and mixed bit patterns. Defined outputs match
exact bytes with zero narrow padding; rejected poison stores leave sentinels
intact. Successful execution costs five steps. Insufficient budgets reject
before writing, for defined and poison cases alike.

The reference adapts the existing scalar flag checker's defined widened
`{value, poison-tag}` oracle, folded by LLVM instcombine. Unflagged i128
operations hold the intermediate results. Shift amounts are reduced modulo
the tested width, preserving valid shifts at non-power-of-two widths while
tagging overshifts independently. Divisors stay valid. Neither native poison
nor a poisoned constant-folding result is used as a value/tag reference.
Per-width input, oracle, folded module and comparison rows remain in the
bundle. Another 384 controls reject corrupted values, lost/spurious rejection
tags, unknown flags and wrong-family flags; the latter must report preflight
flag rejection rather than a dynamic poison-store error.

Sanitized regressions pass all 16 integer/mixed unit groups (including
1,397,052 exhaustive small-width flag checks), 16,896 scalar buffer copies,
107,776 memory arithmetic comparisons (67 NaN-class matches) and 147,456
exact unary comparisons, with their existing controls. The copy checker's
unsupported instruction is now floating fast-math after a store, retaining
preflight/no-write coverage now that integer flags are supported. Its other
guards remain. LLVM-generated JIT reference code in arithmetic/unary suites
is not sanitizer-instrumented; the interpreter and checkers are.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
New deferred flagged kernels produce 300 for 100 + 200 and freeze unsigned
overflow from `0xffffffff + 1` to zero. The same overflow without freeze sets
command status 5 with an NSError and preserves the prior destination value.
Inputs are changed after encoding and observed at commit. Pipeline rejection
for unsupported flags now uses floating fast-math. The ordinary runner was not
rebuilt; these are synthetic LLVM/AIR kernels, not Apple compiler output.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/air-memory-flags-validation-20261113-r1/`

The complete sibling archive was decoded and extracted to fresh `-restored`.
Saved source/compiler/header/executable identities match. All six restored
sanitizer suites pass with fresh external generated fixtures, including all
software Metal groups with normal hashing. The archive checksum passes
afterward. Restore receipts remain beside the bundle; original evidence is
retained. The compiler snapshot was saved after checks. The software harness
retains its documented compiler-preamble corrections. Toolchain library
symlinks, SDKs, LLVM assembler/libraries and other dylibs remain external
prerequisites; dependency closures are not sealed. This is not a full
typed-inventory audit. Leak detection is disabled; runtime object drainage is
checked, retained heap is not measured.

Compute remains a bounded single-thread CPU interpreter with valid LLVM IR as
a precondition. No GPU execution, presentation, Vinix guest, Fortnite frame or
launch gate is verified by this checkpoint.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `a60afec5be1d4f8668204cd375a64d68fd1eca52af4ca824abab283dd1b13ba1` |
| `source.tar`, revision `a395b3956` | `849af9f300e94443bb6e50eaa0857ad878251b9fbfced2e656387f13d63e0d92` |
