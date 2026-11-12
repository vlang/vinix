# Scalar integer overflow checkpoint — 2026-11-12

`904896529` adds the six signed/unsigned add/subtract/multiply
`llvm.*.with.overflow.iN` families across i1..i64. Each produces a literal
unpacked `{iN, i1}` with the wrapped value and overflow flag. The mixed API
accepts `extractvalue` of either field; extracted scalars can feed ordinary
arithmetic, freeze, branches and PHIs. Overflow leaves both fields defined;
input poison propagates through both fields and undef operands still error.
See [the bounded contract and maintained checkers](../../compat/ios/airbitcode/SCALAR-OVERFLOW.md)
and [LLVM semantics](https://llvm.org/docs/LangRef.html#arithmetic-with-overflow-intrinsics).

Preflight validates canonical name/width, direct declaration identity, complete
signature/layout, CALL header/attributes and extraction source/type/index.
All blocks are checked, including unvisited ones. General aggregate arguments,
returns, constants, select/PHIs, freeze and insertvalue remain unsupported.
The integer-only API retains its no-call profile. Runtime pair tags guard
scalar reads and require a known instruction-result slot for extraction.

Numerical evaluation reuses the existing unsigned bit-pattern ALU and NUW/NSW
overflow checks, retaining a separate wrapped value. No valid i64 data bit is
reserved for a flag. The internal value adds two booleans within its existing
16-byte layout, checked by units. The fixed stack declaration cache grows to
1,768 entries: forty FP slots and twenty-seven disjoint 64-width integer ranges.
Generated C confirms scalar copies, fixed storage and the existing three owned
arrays and cleanup. Production adds no valid-path allocation, host signed
arithmetic or LLVM dependency. Retained allocation was not measured.

Final normal and ASan/UBSan focus runs each pass **1,955,832 exact native LLVM
value/overflow pairs**, or **3,911,664 separately extracted fields**, across
384 intrinsic overloads. **1,123,914** cases set overflow; **55,296** are boundary
pairs. All i1..i8 input pairs are exhausted. Wider widths receive 4,096 mixed
pairs plus a twelve-by-twelve matrix of zeros, all-one/sign limits and neighbors,
alternating and byte patterns. Incoming unused high bits exercise masking.
No native poison result is consumed. CALL/extract/return takes three steps.

Controls pass for 1,536 input-poison field results, 1,536 undef rejections,
1,536 budget/integer-API rejections, 768 frozen-poison fields, seven aggregate
profile rejections, sixteen CALL/extraction metadata corruptions, four layouts,
four type mismatches, three name mismatches and six output corruptions,
including a lost overflow flag. Another **3,072 native two-call branch/PHI
checks** reuse declarations and require seven or nine exact steps according
to the overflow branch. Another 768 controls reject a corrupted second CALL
after the first cached its declaration. Independent widened-arithmetic units
pass **524,280** i1..i8 pairs and twelve i64 boundary cases, plus strict
name/width/arity/evaluator/layout guards.

Sanitized regressions pass with all maintained controls:

| Suite | Comparisons | Result contract |
| --- | ---: | --- |
| Integer execution | 17,280 | Exact native results |
| Integer flags | 10,240 | 4,845 defined values, 5,395 poison tags |
| Float execution | 649,216 | Includes 5,641 arithmetic NaN-class comparisons |
| Floating classification | 2,400,256 | Exact results for both precisions |
| Carry-less multiplication | 325,972 | Exact native results |
| Scalar freeze | 459,806 | Exact defined results plus choice-independent controls |

Mixed execution, shared intrinsic, zero-count and integer-bit units also pass.
Other full intrinsic/FMA/half/conversion reference suites were not rerun;
their numerical helpers were unchanged. LLVM/native/JIT code is not sanitizer-
instrumented; leak detection is disabled. Existing usize FFI warnings remain.
Mixed units link as a static little-endian AArch64 Linux ELF with no
INTERP/DYNAMIC segment. No guest ran.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-overflow-validation-20261112-r1/`

The bundle contains pinned final source, fixtures, bitcode, every pair
comparison, binaries, generated C, identities, versions, logs and reproduction
notes. Early successful numerical runs before strengthened controls are retained
as diagnostics; qualification uses `reference-normal-final` and `reference-asan`.
Selected V/LLVM hashes match the pre-build receipt; full compiler/SDK/LLVM/JIT/
fenv/sanitizer dependency closures are not sealed. The unchanged complete typed
inventory checker passes for the original and fresh restore at
`air-overflow-restoration-20261112-r1/`, including every path, byte, type, size
and permission. Whole-archive decoding/extraction exit zero; the disposable
decoded tar was removed afterward. Restored sanitizer binaries pass all
1,955,832 pairs and controls again, plus overflow/mixed/intrinsic/count/bit units.
Post-replay full original/restored inventories, relative identities, selected
compiler hashes and archive checksum pass. Replay output and receipts remain
beside the sealed bundles.

No AIR shader, iOS application, GPU command or new Fortnite probe ran. The
default Metal device stub still returns nil; no new frame or launch gate
is verified.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `4ed5997c90edf094ef3d22ce566928e29bebb7903a105c4bc421eb0d2b6b19bf` |
| Complete `.tar.zst` beside bundle | `18ba6108c958383f0ecbc6844624ded0138f19844b3115d97e43ae352010810f` |
| `source.tar`, revision `904896529` | `d9b2e6333ba830f4b0313cfd7960f3b3c6177b46fd097bbc05068d2837e7aac1` |
