# Overflow pair field insertion checkpoint — 2026-11-12

`ec81ab47a` adds `insertvalue` for existing instruction-produced literal
unpacked `{iN, i1}` pairs across i1..i64. One literal index replaces either the
arithmetic field or flag with a scalar of that exact type. Preflight checks
shape, index, types and source origin in every block. Aggregate constants,
arguments, returns, freeze, nested paths and other layouts remain unsupported.
The integer-only API retains its no-call profile. See
[the bounded contract and maintained checkers](../../compat/ios/airbitcode/SCALAR-PAIR-INSERT.md)
and [LLVM semantics](https://llvm.org/docs/LangRef.html#insertvalue-instruction).

Each field now has independent poison state. Replacing a field replaces its
poison state, preserving its neighbor. One defined replacement repairs one
field of an entirely poisoned pair; two defined replacements repair both.
Overflow calls with poison inputs and selects with poison conditions mark
both fields poison. Select and simultaneous PHIs copy both states; extraction
reports the chosen field's state. Undef replacements still error even when a
later extraction would not observe them. Public scalar result types retain
their existing meaning.

The additional flag-poison boolean fits within the existing 16-byte runtime
value, checked by units. Generated C shows a u64 plus four booleans and scalar
stack copies/masks for insertion. Existing owned arrays, cleanup and the
1,768-entry fixed declaration cache remain. No valid-path allocation, numeric
intrinsic/cache range or ownership change is added. Retained allocation was
not measured.

Normal and ASan/UBSan focus runs each pass **786,432 exact native LLVM
comparisons**, including **12,288 boundary results**, across 768 functions.
Every width covers both fields and their untouched neighbor, overwriting
poison, repairing one field, and repairing both fields. Each function receives
sixteen edge triples and 1,008 mixed triples with unused high argument bits.
Only defined extracted fields cross the native ABI. CALL/insert/extract/return
takes four steps; two insertions take five.

Interpreter controls pass for 1,664 budget/integer-API failures, 768 poison
field results, 640 unaffected fields, 256 undef replacement rejections,
128 frozen-poison fields, twelve metadata/type/index/origin corruptions and
six output corruptions, including a lost flag-field poison tag. Partial data-
and flag-poison states are selected and swapped through parallel pair/scalar
loop PHIs, with zero through five iterations and exact step counts. Long-loop
budgets also reject. Units cover 2,048 width/pattern/poison states, both overwrite
orders, reinsertion identities, field independence, masking, repair, layout
and shape/type/origin/index/value guards.

Sanitized regressions pass with all maintained controls:

| Suite | Comparisons | Result contract |
| --- | ---: | --- |
| Integer execution | 17,280 | Exact native results |
| Float execution | 649,216 | Includes 5,641 arithmetic NaN-class comparisons |
| Half execution | 2,587,648 | Includes 62,180 arithmetic NaN-class comparisons |
| Scalar freeze | 459,806 | Exact defined results plus choice-independent controls |
| Integer overflow | 1,955,832 pairs | 3,911,664 fields; 1,123,914 overflow flags |
| Pair select/PHI flow | 327,680 | Exact results plus whole-pair poison controls |

Pair-flow, mixed execution, overflow and shared intrinsic units pass. The
older overflow fixture's insertion rejection now uses an unsupported constant
pair source, preserving its seven profile guards. Instruction-source
insertion is positively covered by the new checker. The
pair-flow unit's whole-poison fixture now marks and verifies both field tags.
Other full flag/intrinsic/FMA/conversion reference suites were not rerun;
numerical helpers were unchanged. LLVM/native/JIT code is not sanitizer-
instrumented; leak detection is disabled. Existing usize FFI warnings remain.
Mixed units link as a static little-endian AArch64 Linux ELF with no
INTERP/DYNAMIC segment. No guest ran.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-pair-insert-validation-20261112-r1/`

It contains pinned source, fixtures, bitcode, every defined comparison,
binaries, generated C, identities, versions, logs and reproduction notes.
Selected V/LLVM hashes match the pre-build receipt; full compiler/SDK/LLVM/JIT/
fenv/sanitizer dependency closures are not sealed. The unchanged complete typed
inventory checker passes for the original and fresh restore at
`air-pair-insert-restoration-20261112-r1/`, including every path, byte, type,
size and permission. Whole-archive decoding/extraction exit zero; the disposable
decoded tar was removed afterward. Restored sanitizer binaries pass all
786,432 comparisons and every control again, plus insertion/pair-flow/mixed/
overflow/intrinsic units. Post-replay full original/restored inventories,
relative identities, selected compiler hashes and archive checksum pass.
Replay output and receipts remain beside the sealed bundles.

No AIR shader, iOS application, GPU command or new Fortnite probe ran. The
default Metal device stub still returns nil; no new frame or launch gate
is verified.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `ade65bf6e48ed143fa157c35b7a166a4481e8232ca50b970a2f39c50f81e5ead` |
| Complete `.tar.zst` beside bundle | `272b0be2348564f8a539ca64aac6df707a6e95ebb59671a3f23c2e4a2bb50e52` |
| `source.tar`, revision `ec81ab47a` | `ab8c6915ba44a1d78d83a2f40efda36aaf6f6ac8bbf449720376ef1c3a347320` |
