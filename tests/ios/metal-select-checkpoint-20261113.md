# Software Metal comparison and selection — 2026-11-13

`a257d046e` adds scalar comparisons and select to AIR memory execution and
the opt-in software Metal compute profile. All ten integer predicates at
i1..i64 and all sixteen half/float predicates produce scalar i1 results.
Select requires a scalar i1 condition and matching scalar value/result types.
Preflight validates arities, types, result slots and predicates. Flags, pointer
comparisons, vector values and aggregate selects remain outside the memory
profile. Each comparison/select costs one step. See
[MEMORY-EXECUTION.md](../../compat/ios/airbitcode/MEMORY-EXECUTION.md).

The memory and existing scalar interpreters share comparison/select helpers.
Select reads only its chosen value after reading the condition. Unselected
poison/undef constants are ignored; selected undef errors, and poison in a
condition or chosen value propagates to a rejected poison store. Constant
true/false floating predicates retain the existing semantics. Selection does
not skip earlier instructions. Existing scalar overflow-pair selection remains
supported by its separate profile.

Normal and ASan/UBSan runs pass 86,016 native LLVM cases across 672 functions,
128 samples each. Every case checks both the predicate and selected value,
seven-step execution, insufficient budgets and destination padding. Coverage
includes signed/unsigned limits, equal values, signed zeros, subnormals,
infinities and NaNs. Chosen floating bits match exactly; only unused native
narrow-integer padding bits are masked, and the interpreter must zero them.
Eleven interpreter controls cover three accepted lazy/constant-predicate cases
and eight poison/undef/flag rejections. Flagged instructions after a store
reject during preflight without writing.

Sanitized regressions pass all 16 integer/mixed unit groups, 327,680 native
overflow-pair flow comparisons, 107,776 buffer arithmetic cases and 59,520
indexed buffer copies, including their maintained controls. The arithmetic
reference retains its 67 matching NaN-class cases without payload/sign equality.
All 24 software Metal groups pass with normal and deterministic Swift hashing.
New synthetic signed-integer and ordered-float max kernels exercise comparisons
and select through pipeline creation, deferred execution and pipeline/buffer
rebindings. Their outputs are 3 for (-5, 3) and 2.25 for (1.5, 2.25).
The ordinary runner was not rebuilt. LLVM's JIT-generated native reference is
not sanitizer-instrumented; the interpreter/checkers are.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/air-memory-select-validation-20261113-r1/`

The sibling archive was decoded and fully extracted to fresh `-restored`.
Saved source/compiler/header/executable identities match. Restored sanitizer
executables pass all six suites again with fresh external generated fixtures;
the archive checksum passes afterward. Restore receipts remain beside the
bundle. The current compiler snapshot was saved after checks. The software
harness retains its documented compiler-preamble corrections; toolchain
library symlinks, SDKs, assembler and dylibs remain external prerequisites.
Complete dependency closures are not sealed. This is not a full typed-inventory
audit. Leak detection is disabled; runtime object drainage is checked, retained
heap is not measured.

Compute remains a bounded single-thread CPU interpreter with valid LLVM IR as
a precondition. These synthetic LLVM/AIR fixtures do not establish compatibility
with Apple compiler-produced kernels. No new threading, branches, GPU command,
Vinix guest, presentation, Fortnite frame or launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `64892c2a9a4f3ed3bd694c18f8e0130732eabf4d06f69c8092632b26d7ea885e` |
| `source.tar`, revision `a257d046e` | `e55dbae872fb833a28e7622cc350290a95aac836404f8b754bdd4ebb1a98f79b` |
