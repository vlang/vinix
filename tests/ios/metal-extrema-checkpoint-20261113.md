# Software Metal integer min/max — 2026-11-13

`ce68f184a` admits direct LLVM `smin`, `smax`, `umin` and `umax` calls in
bounded AIR buffer kernels and opt-in software Metal compute. Two scalar
i1..i64 operands must match the result type. Signed variants use
two's-complement ordering; unsigned variants compare masked words. The chosen
input's bits are preserved. Each call costs one step. Existing scalar
evaluation and direct-call/signature/attribute checks are reused; the
declaration cache now covers all eleven admitted integer families. See
[MEMORY-EXECUTION.md](../../compat/ios/airbitcode/MEMORY-EXECUTION.md).

Both operands are evaluated. Poison propagates and undef rejects. Poison
stores reject; freeze can choose zero and an unchosen select can discard a
computed poison result. General calls, indirect/tail calls, call-site
attributes, fast-math calls and other intrinsic families remain unsupported.
Execution never invokes a host declaration. No memory shadow tracking or
rollback is added.

Normal and ASan/UBSan checks each pass 65,536 exact defined native LLVM
comparisons across 256 buffer functions, 256 samples each. The 20,736 boundary
pairs cover the complete 9-by-9 edge matrix per function, including zero, one,
signed minima/maxima, unsigned maxima and adjacent values. Remaining inputs
include equal operands and mixed patterns. This includes i1 true as signed -1
and i64 signed minimum. Results match raw bits and must equal one of the
input words. Native inputs have zero padding; only unused native destination
padding is masked. Interpreter padding must be zero. Sentinels, exact
five-step execution and budget rejection without writes are checked.

Another 1,024 interpreter controls cover poison/undef in either operand for
each width/family. There are 512 successful freeze/lazy selections and nine
call-metadata rejections after a store. Poison controls never execute natively.
The native checker uses MCJIT optimization level 2 with FastISel disabled.

Sanitized regressions pass all 16 integer/mixed unit groups, 1,303,888 scalar
integer-extrema comparisons (36,864 boundary pairs), 99,328 buffer bit-intrinsic
comparisons and 32,768 buffer funnel comparisons, with their existing controls.
LLVM JIT-generated reference code is not sanitizer-instrumented; the interpreter
and checkers are.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
The new deferred kernel computes all four extrema from raw i32 words
`0xfffffffb` and `3`. Its signed min/max outputs are `0xfffffffb` and `3`;
unsigned min/max produce `3` and `0xfffffffb`. Pipeline creation, offset
bindings, pipeline release before commit, live inputs changed after encoding,
four GEP-derived stores, combined extents and command completion are exercised.
The ordinary runner was not rebuilt.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/air-memory-extrema-validation-20261113-r1/`

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
| `.tar.zst` beside bundle | `8422a0243b816a61cc7e3e2a1360f8b38e11b5fb54a9db8fce49681ac42e064b` |
| `source.tar`, revision `ce68f184a` | `51bc51da576deb4823e0a7eb881214902b2dd109aef309595351308c549adb23` |
