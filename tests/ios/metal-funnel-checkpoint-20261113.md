# Software Metal funnel shifts — 2026-11-13

`f1386f750` admits direct LLVM `fshl` and `fshr` calls in bounded AIR buffer
kernels and opt-in software Metal compute. Three scalar i1..i64 operands must
match the result type. Amounts are reduced modulo the width; equal inputs
produce rotations. A zero amount selects the first half for fshl and the second
for fshr. The existing scalar evaluator and direct-call/signature/attribute
checks are reused. The declaration cache now covers all seven admitted integer
families. Calls cost one step. See
[MEMORY-EXECUTION.md](../../compat/ios/airbitcode/MEMORY-EXECUTION.md).

All three arguments are evaluated. Poison propagates even in the otherwise
unused half at zero amount; undef rejects. A poison store rejects, while
freeze and an unchosen select can consume/discard a computed poison result.
General calls, indirect/tail calls, call-site attributes, fast-math calls and
other intrinsic families remain unsupported. No host declaration is invoked.

Normal and ASan/UBSan runs each pass 32,768 exact defined native LLVM
comparisons across 128 buffer functions, including 4,096 equal-input rotations.
Inputs cover zero, width-minus-one, width, larger amounts, maximum unsigned
amounts and mixed bit patterns at all widths, including non-power-of-two widths.
Each successful load/load/load/call/store/return costs six steps. Output
sentinels and zero narrow padding match; insufficient budgets reject without
writes. The native reference uses MCJIT optimization level 2 with FastISel off.

Another 768 interpreter controls cover poison/undef in each of the three
positions at every width and direction. There are 256 successful freeze/lazy
selections, nine call-metadata rejections after a store and 112 interpreter-only
padding-choice checks. None of these poison/padding-choice controls execute
natively in the maintained checker.

The first reference run mistakenly used nonzero padding on narrow native
loads and disagreed at i3. Those inputs are LLVM poison, so that comparison
was not a defined native oracle. Its log remains in the bundle. The maintained
checker uses zero-padded native inputs and tests the buffer executor's existing
masked choice separately. The GEP regression fixture had the same input issue;
it now zeros the loaded value's padding before native comparison. This tightens
reference definedness without changing production load behavior. Historical
reports are not requalified. See
[LLVM load semantics](https://llvm.org/docs/LangRef.html#load-instruction).

Sanitized regressions pass all 16 integer/mixed unit groups, 99,328 buffer bit
intrinsic comparisons, 2,230,560 scalar funnel/rotation comparisons (1,114,112
boundary triples) and 59,520 corrected native GEP copies, with their existing
controls. LLVM JIT-generated reference code is not sanitizer-instrumented;
the interpreter and checkers are.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
The new deferred kernel loads two words and a buffer-supplied amount through
a GEP, executes both directions, and stores two words. With inputs
`0x01234567`, `0x89abcdef` and amount 36, it produces `0x12345678` and
`0x789abcde`. Pipeline creation, offset bindings, release before commit, live
input updates after encoding, derived extents and command completion are
exercised. The ordinary runner was not rebuilt.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/air-memory-funnel-validation-20261113-r1/`

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
| `.tar.zst` beside bundle | `e24ac8b6bc6008d5f5aedc27ecf0fa0ddc29d13082f58082061a511baf93f88c` |
| `source.tar`, revision `f1386f750` | `334f4c7acf19abe82d9e9e05c11b810ff53f38e613dc82fed388665a98751b4b` |
