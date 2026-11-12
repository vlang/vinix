# AIR scalar buffer execution — 2026-11-13

`2b4506d7b` adds `run_memory_function` and IRMemoryBinding for defined ordinary
void functions containing one block of scalar loads/stores and ret void.
Pointer arguments map directly to borrowed byte buffers and offsets, with
declared virtual alignment and write permissions. No host pointers are used.
The profile supports i1..i64, half and float, little-endian bytes, at most 64
bindings of at most 64 MiB each, and address spaces 0/1 plus readonly space 2.
Accesses and instruction shapes are checked before execution. Constant stores
and loaded SSA values are supported. Scratch arrays are freed on every exit;
caller buffer data is never freed. See
[MEMORY-EXECUTION.md](../../compat/ios/airbitcode/MEMORY-EXECUTION.md).

Normal and ASan/UBSan checks pass 16,896 serialized LLVM-bitcode copies across
all 64 integer widths plus half/float bit patterns. Independent byte
expectations check masking and sentinel padding. Additional checks cover
constant stores, readonly/bounds/budget failures, poison and selected undef,
volatile/unsupported instructions, aligned aliases, device/constant address
spaces, misalignment, missing bindings, endian guards and scalar-void API
separation. Unsupported instructions after a store reject during preflight
without writing. Existing integer/mixed sanitizer units pass all 16 groups.
This is not a native LLVM JIT comparison.

The API is deliberately narrow: no arithmetic, branches, GEP, alloca, atomics,
volatile access, pointer casts, kernel ABI binding or Metal dispatch. Explicit
access alignment is required. Buffer contents are defined raw bytes, without
uninitialized/poison shadow tracking. Dynamic value failures may leave earlier
stores visible; execution is not transactional. Valid IR and matching immutable
indexes remain preconditions. Callers must synchronize shared buffers.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/air-memory-execution-validation-20261113-r1/`

The sibling archive was decoded/extracted to fresh `-restored`. Saved source,
compiler snapshot and executable identities match. Restored sanitizer units
pass all 16 groups and the restored checker passes all 16,896 cases in fresh
sibling `-restore-cases`. The archive checksum passes afterward; receipts
remain beside the bundle. The compiler snapshot was saved after checks; the
complete compiler/library/SDK/assembler dependency closure is not sealed.
This is not a full typed-inventory audit. Leak detection is disabled; retained
heap was not measured. No cross-build, AIR kernel, Metal command, Fortnite
frame or new launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `418fb206fb68416c34a45dcb5823008876103dc76a5ac7342476a8a805913ddc` |
| `source.tar`, revision `2b4506d7b` | `5c3b0eef535ce04dc396030d19e1b62278b9a61189ecccb2e9cddf1036732280` |
