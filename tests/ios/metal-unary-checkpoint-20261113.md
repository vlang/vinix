# Software Metal negation and freeze — 2026-11-13

`201474ab5` adds scalar half/float `fneg` and i1..i64/half/float `freeze` to
bounded AIR buffer execution and opt-in software Metal compute. The scalar
and memory interpreters share unary validation and negation execution;
freeze reuses the existing scalar reader and result slots. Both operations
cost one step and require matching scalar operand/result types and zero flags.
Pointer, vector, aggregate, double and bfloat operations remain outside this
memory profile. See
[MEMORY-EXECUTION.md](../../compat/ios/airbitcode/MEMORY-EXECUTION.md).

Negation flips only the sign bit, preserving NaN payload/quiet bits and all
other raw bits, including signed zeros and subnormals. Poison propagates;
undef rejects. Freeze preserves defined bits and chooses a fixed zero for
poison/undef. Every use of its SSA result sees that same choice. Freeze does
not prevent an earlier instruction from rejecting undef or another dynamic
error. This does not add uninitialized-buffer shadow tracking.

Normal and ASan/UBSan runs pass 147,456 exact native LLVM and independent
raw-bit comparisons across 68 load/unary/store functions. Coverage includes
all 65,536 half encodings for both operations, 4,096 float inputs for each,
and 128 inputs for each integer width. Signaling/quiet NaNs match exact bits;
there are no NaN-class exemptions. Only unused native narrow-integer padding
is masked; interpreter padding must be zero. Destination sentinels, exact
four-step execution and budget rejection without writes are checked.

Another 132 interpreter cases freeze poison/undef constants at every supported
type and store each frozen SSA result to two distinct locations. Both stores
match the fixed-zero policy. Nine further controls cover computed overshift
poison, negated poison followed by freeze, rejected poison stores, undef
evaluation before freeze, fast-math flags and unsupported double/vector/
pointer/aggregate instructions. Unsupported instructions after an earlier
store reject during preflight before writing. Native choices for poison/undef
are not used as an exact-value reference.

The native reference uses Homebrew LLVM 23.1.5 MCJIT with explicit optimization
level 2 and FastISel disabled. The interpreter's portable layout supplies only
byte GEPs in these fixtures. The native module clears that layout and uses its
host target layout, as in the existing GEP checker. An initial run retaining
the portable layout was rejected by LLVM; its log remains in the bundle.
LLVM JIT-generated code is not sanitizer-instrumented; the interpreter and
checkers are.

Sanitized regressions pass all 16 integer/mixed unit groups, 210,112 native
memory cast comparisons (four precision-conversion NaN-class matches), 86,016
memory comparison/select cases and 327,680 overflow-pair flow comparisons,
including their existing controls. All 24 software Metal groups pass with
normal and deterministic Swift hashing. New deferred kernels negate raw
signaling-NaN bits `0x7f812345` to `0xff812345` and freeze a poisoned infinity
to integer conversion to zero, through pipeline creation, offset bindings and
command completion. Buffer contents are changed after encoding and observed
at commit. The ordinary runner was not rebuilt.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/air-memory-unary-validation-20261113-r1/`

The complete sibling archive was decoded and extracted to fresh `-restored`.
Saved source/compiler/header/executable identities match. All six restored
sanitizer suites pass again with fresh external generated fixtures, including
all software Metal groups with normal hashing. The archive checksum passes
afterward. Restore receipts remain beside the bundle; original evidence is
retained. The compiler snapshot was saved after checks. The software harness
retains its documented compiler-preamble corrections; toolchain library
symlinks, SDKs, assembler and dylibs remain external prerequisites. Complete
dependency closures are not sealed. This is not a full typed-inventory audit.
Leak detection is disabled; runtime object drainage is checked, retained heap
is not measured.

Compute remains a bounded single-thread CPU interpreter with valid LLVM IR as
a precondition. Synthetic LLVM/AIR fixtures do not establish compatibility
with Apple compiler-produced kernels. No GPU execution, presentation, Vinix
guest, Fortnite frame or launch gate is verified by this checkpoint.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `782dbf462d61a98531e63b1f3e21da07df9f3060804659e16285648187cbefd4` |
| `source.tar`, revision `201474ab5` | `8f13682b8813fbe05099528dcfe8d8fe18e362e71ed6f5585db799612cbf9cce` |
