# Software Metal saturating shifts — 2026-11-13

`d6176e2fb` admits direct LLVM `sshl.sat` and `ushl.sat` calls in bounded AIR
buffer kernels and opt-in software Metal compute. Scalar i1..i64 values,
amounts and results must match. Valid amounts below the width shift left and
clamp to signed/unsigned bounds. Unsigned width-masked amounts at or above the
width produce poison, even for zero input. Amounts do not reduce modulo the
width. Calls cost one step and reuse scalar validation/evaluation; the
declaration cache now covers eighteen admitted integer families. See
[MEMORY-EXECUTION.md](../../compat/ios/airbitcode/MEMORY-EXECUTION.md).

Poison operands propagate and undef rejects. A poison store rejects, while
freeze or an unchosen select can consume/discard a computed overshift result.
General calls, indirect/tail calls, call-site attributes, fast-math calls and
other intrinsic families remain unsupported. Execution never invokes a host
declaration. No memory shadow tracking or rollback is added.

Normal and ASan/UBSan checks each pass 32,768 exact defined native LLVM
comparisons across 128 buffer functions, 256 samples each. The 10,368 boundary
pairs cover nine value edges against nine valid amount edges per function,
including signed/unsigned limits, zero, width-minus-one and mixed patterns.
Native amounts are always below the width. Native input padding is zero;
only unused native destination padding is masked. Interpreter padding must
be zero. Sentinels, exact five-step execution and budget rejection without
writes are checked. The native checker uses MCJIT optimization level 2 with
FastISel disabled.

Another 1,024 interpreter controls cover poison/undef in either operand and
constant overshifts at the width/maximum amount with zero and nonzero values.
There are 256 loaded-overshift checks with zero input, 256 successful
freeze/lazy selections and nine call-metadata rejections after a store.
Overshift/control functions never execute natively in this checker.

Sanitized regressions pass 651,944 scalar value/tag comparisons (206,750 poison
results) and 651,944 independent checked-doubling comparisons, including
exhaustive i1..i8 pairs and 18,432 value/amount edge pairs. The scalar native
reference substitutes zero for invalid amounts and checks poison tags
separately. All 16 integer/mixed unit groups and 65,536 buffer saturating
add/sub comparisons also pass, including existing controls. LLVM JIT-generated
reference code is not sanitizer-instrumented; the interpreter and checkers are.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
Four deferred dispatches check positive signed saturation, negative signed/
unsigned saturation, freezing a zero-input overshift, and zero shift preserving
signed minimum. Inputs change after encoding; destination sentinels remain
intact until commit. A separate unfrozen zero-input overshift sets command
status 5 with an NSError, preserving the previous output words. Pipeline
creation, offset snapshots, pipeline release before commit, GEP-derived stores,
completion and two drained runtimes are exercised. The ordinary runner was
not rebuilt.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/air-memory-saturating-shift-validation-20261113-r1/`

The initial fresh extraction failed with ENOSPC. Only its partial restore and
derived decoded tar were removed; the original directory and archive remain.
A direct zstd-to-tar stream then restored the complete archive to fresh
`-restored`, avoiding the extra decoded copy. Saved source/compiler/header/
executable identities match. Four restored sanitizer suites passed, while
the host failed with ENOSPC and the scalar replay exited without a final PASS
receipt during disk pressure. Fresh `scalar-r2` and `software-r2` retries pass
after space became available. All six suites are therefore verified, including
all software Metal groups with normal hashing. Failed replay files/logs and
retry receipts remain beside the bundle. The archive checksum passes afterward.
No completed evidence or other sessions' files were removed.

The compiler snapshot was saved after checks. The software harness retains
its documented compiler-preamble corrections. Toolchain library symlinks,
SDKs, assembler and dylibs remain external prerequisites; dependency closures
are not sealed. This is not a full typed-inventory audit. Leak detection is
disabled; runtime object drainage is checked, retained heap is not measured.

Compute remains a bounded single-thread CPU interpreter with valid LLVM IR as
a precondition. Synthetic LLVM/AIR fixtures do not establish compatibility
with Apple compiler-produced kernels. No GPU execution, presentation, Vinix
guest, Fortnite frame or launch gate is verified by this checkpoint.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `5330d1b089e6deb35b4d521f18fa4ff93d342ee9f40223d5b7c1b61b95fc6fc5` |
| `source.tar`, revision `d6176e2fb` | `89e6fa93f2a5067bb1775467e70a697d43c4275708ee635bace8580017b78e94` |
