# Software Metal integer absolute value — 2026-11-13

`5a2aa34b8` admits direct LLVM `abs` calls in bounded AIR buffer kernels and
opt-in software Metal compute. Scalar i1..i64 input/result types must match;
the second operand must be a literal defined i1 minimum-poison flag. A false
flag preserves the signed minimum's raw bits, while a true flag makes that
input poison. Other defined inputs yield their absolute-value bits. Calls
cost one step and reuse scalar validation, immediate checks and evaluation.
The declaration cache now covers twelve admitted integer families. See
[MEMORY-EXECUTION.md](../../compat/ios/airbitcode/MEMORY-EXECUTION.md).

Poison input propagates, undef rejects and a poison store rejects. Freeze can
make its existing fixed-zero choice for a poisoned minimum. General calls,
indirect/tail calls, call-site attributes, fast-math calls and other intrinsic
families remain unsupported. Execution never invokes a host declaration.
No memory shadow tracking or rollback is added.

Normal and ASan/UBSan checks each pass 32,768 exact defined native LLVM
comparisons across 128 buffer functions, 256 samples each. Both flag values
are checked at every width. Inputs include single bits, complements, signed
minima where defined and mixed patterns. True-flag minimum inputs are replaced
with zero before native execution; minimum poison is checked separately.
Native input padding is zero, and only unused native destination padding is
masked. Interpreter padding must be zero. Sentinels, exact four-step execution
and insufficient budgets without writes are checked. The native checker uses
MCJIT optimization level 2 with FastISel disabled.

Another 322 controls cover poison/undef inputs, true-flag minimum poison and
rejected non-intrinsic and floating-intrinsic calls. There are 64 successful frozen minimum-poison
results and nine call-metadata rejections after a store. A mixed-flag case
reuses the declaration, preserving the false-flag minimum and freezing the
true-flag poison. Replacing its second call's flag with an SSA result rejects
before writing, proving that an attribute-cache hit does not skip immediate
validation. These poison/control functions never execute natively.

Sanitized regressions pass all 16 integer/mixed unit groups, 656,892 scalar
absolute-value value/tag comparisons (87 poison results), 99,328 buffer
bit-intrinsic comparisons and 65,536 buffer integer-extrema comparisons,
including their existing controls. The scalar abs reference substitutes safe
values for invalid inputs and checks poison tags separately. LLVM JIT-generated
reference code is not sanitizer-instrumented; the interpreter and checkers are.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
New deferred kernels use both minimum-poison flags on i32 signed minimum and
-5. After freeze, the false-flag kernel stores `0x80000000, 5`; the true-flag
kernel stores `0, 5`. Pipeline creation, offset bindings, pipeline release
before commit, live inputs changed after encoding, GEP-derived stores and
command completion are exercised. The ordinary runner was not rebuilt.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/air-memory-abs-validation-20261113-r1/`

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
| `.tar.zst` beside bundle | `a92c6361148a66f8c97da33c67575972e5c6bd2f59f33886ed509f895aefaa5d` |
| `source.tar`, revision `5a2aa34b8` | `77ac86072aff3e84233463098c5294a423d3dff074fd9a223be77baa76edeb61` |
