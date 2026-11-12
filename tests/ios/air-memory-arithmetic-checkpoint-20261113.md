# AIR buffer arithmetic — 2026-11-13

`8e7135c0c` extends the bounded memory executor with flag-free binary integer
operations and half/float fadd, fsub, fmul, fdiv and frem. One-block ordinary
void functions can now load two scalars, compute a result and store it. The
executor shares arithmetic with the scalar interpreter, including poison
propagation and undefined-division guards. Every instruction costs one step.
Instruction shapes, flags and buffer accesses are checked before execution.
The existing unsupported-instruction regression now uses `add nuw`, which
remains rejected before an earlier store writes. See
[MEMORY-EXECUTION.md](../../compat/ios/airbitcode/MEMORY-EXECUTION.md).

Normal and ASan/UBSan runs of `tests/ios/air-memory-arithmetic.v` pass 107,776
native LLVM comparisons: 128 samples for each of 842 functions covering all
13 binary integer opcodes at i1..i64 and five operations at half/float.
107,709 results match bits; 67 compare matching NaN classes without requiring
payload/sign equality. Unused high bits in native narrow-integer storage are
masked for comparison; the interpreter must zero them. Sentinel bytes and
five-step execution counts are checked. A four-step budget rejects each body.
Undefined integer inputs are excluded from native execution. Five additional
interpreter-only functions reject zero division, signed division overflow,
overshift poison, a poison operand and selected undef without storing a result.

The maintained buffer checker also passes 16,896 serialized copies and its
permission, bounds, alignment, endian, flags, poison and API-separation guards
under ASan/UBSan. All 16 integer/mixed scalar unit groups pass, including
1,397,052 exhaustive i1..i8 flag comparisons. The production interpreter and
checkers are instrumented; LLVM's JIT-generated native reference is not.
Leak detection is disabled. Retained heap was not measured.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/air-memory-arithmetic-validation-20261113-r1/`

The sibling `.tar.zst` was decoded and fully extracted to fresh `-restored`.
Saved source, compiler snapshot and executable identities match. Restored
sanitizer arithmetic, copy and unit executables all pass again using fresh
sibling output directories. Restore receipts remain beside the bundle, and
the archive checksum passes afterward. `normal-final.log` contains the final
normal run; the earlier `normal.log` predates the added rejection fixtures.
The compiler snapshot was saved after checks; the complete compiler/library/
SDK/LLVM dependency closure is not sealed. This is not a full typed-inventory
audit or a cross-build.

This remains interpreter groundwork. The memory profile still rejects flags,
branches, GEP, alloca, casts, atomics, volatile accesses and calls. Valid LLVM
IR and matching immutable parsed indexes are preconditions. Dynamic errors
can leave earlier stores visible. No Metal runner integration, AIR kernel ABI,
pipeline, dispatch, GPU command, Fortnite frame or new launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `0f6ec1c7239c0f9601b33855349ab99d9d5084e8cd208c0df99f273e1d630653` |
| `source.tar`, revision `8e7135c0c` | `ff31e920222d2a84aad6b68057b7d5bf0cae2d15295564e1dd89d0dac86f0548` |
