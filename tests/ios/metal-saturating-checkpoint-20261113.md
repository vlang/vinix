# Software Metal saturating add/sub — 2026-11-13

`58b2446d1` admits direct LLVM `sadd.sat`, `uadd.sat`, `ssub.sat` and
`usub.sat` calls in bounded AIR buffer kernels and opt-in software Metal
compute. Two scalar i1..i64 operands must match the result type. Signed
operations clamp to signed bounds; unsigned operations clamp to zero/unsigned
maximum. Defined arithmetic overflow saturates. Each call costs one step and
reuses scalar validation/evaluation; the declaration cache now covers sixteen
admitted integer families. See
[MEMORY-EXECUTION.md](../../compat/ios/airbitcode/MEMORY-EXECUTION.md).

Poison operands still propagate, undef rejects and a poison store rejects.
Freeze can choose zero and an unchosen select can discard computed poison.
General calls, indirect/tail calls, call-site attributes, fast-math calls and
other intrinsic families remain unsupported, including saturating shifts.
Execution never invokes a host declaration. No memory shadow tracking or
rollback is added.

Normal and ASan/UBSan checks each pass 65,536 exact defined native LLVM
comparisons across 256 buffer functions, 256 samples each. The 20,736 boundary
pairs cover a complete 9-by-9 edge matrix per function, including signed
minima/maxima, unsigned maxima, zero, one and adjacent values. Remaining
inputs include equal operands and mixed patterns. Native input padding is
zero; only unused native destination padding is masked. Interpreter padding
must be zero. Sentinels, exact five-step execution and budget rejection without
writes are checked. The native checker uses MCJIT optimization level 2 with
FastISel disabled.

Another 1,024 interpreter controls cover poison/undef in either operand for
each width/family. There are 512 successful freeze/lazy selections and nine
call-metadata rejections after a store. Poison/control functions never execute
natively.

Sanitized regressions pass 1,303,888 native scalar saturating comparisons
(36,864 boundary pairs) and 1,303,888 independent margin/carry comparisons,
including exhaustive i1..i8 pairs, commutative addition and zero identities.
All 16 integer/mixed unit groups and 32,768 buffer abs comparisons also pass,
with their existing controls. LLVM JIT-generated reference code is not
sanitizer-instrumented; the interpreter and checkers are.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
The new kernel computes all four operations across four deferred dispatches,
using separate offset snapshots and a 64-byte destination. Cases exercise
signed maximum plus one, signed minimum minus one, unsigned maximum plus one
and unsigned zero minus one. All sixteen result words are checked. Inputs
change after encoding; output sentinels remain intact until commit. Caller
pipeline/output-buffer references are released before commit, and the recorded
work still succeeds. Combined extents, GEP-derived stores, command completion
and two drained runtimes are exercised. The ordinary runner was not rebuilt.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/air-memory-saturating-validation-20261113-r1/`

The complete sibling archive was decoded and extracted to fresh `-restored`.
Saved source/compiler/header/executable identities match. All six restored
sanitizer suites pass again with fresh external fixtures, including all
software Metal groups with normal hashing. The archive checksum passes
afterward. Restore receipts remain beside the bundle; original evidence is
retained. The compiler snapshot was saved after checks. The software harness
retains its documented compiler-preamble corrections. Toolchain library
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
| `.tar.zst` beside bundle | `46e395b3e57ebf3fc621c7ab769e56e4b3c051c56fad3635f50906b0d5670eee` |
| `source.tar`, revision `58b2446d1` | `2e971b5726687d9b4e6025dd2ad0c0258fd8e023760c94401d3a30d55661bfda` |
