# Overflow pair control-flow checkpoint — 2026-11-12

`911c9c37b` carries instruction-produced literal unpacked `{iN, i1}` overflow
pairs through select and PHIs across i1..i64. Incoming pair types must match;
select requires a scalar i1 condition. Preflight checks every block, including
unvisited blocks. Aggregate constants/arguments/returns, other layouts, freeze
and insertvalue remain unsupported. The integer-only API retains its no-call
profile. See [the bounded contract and maintained checkers](../../compat/ios/airbitcode/SCALAR-PAIR-FLOW.md)
and LLVM's [select](https://llvm.org/docs/LangRef.html#select-instruction) and
[PHI](https://llvm.org/docs/LangRef.html#phi-instruction) contracts.

Select reads only its chosen pair. A poison condition yields a tagged poison
pair; both extracted fields remain poison. Undef conditions still error.
PHIs read the executed predecessor and collect all incoming pair/scalar values
before assigning any result slot. Value bits, overflow and poison survive
parallel loop swaps. The new control-flow reader delegates to existing pair
or scalar readers. Generated C confirms the existing pending array, three
owned arrays and cleanup, 16-byte values and 1,768-entry fixed stack declaration
cache remain. No numeric helper, intrinsic ID/cache range or valid-path
allocation is added. Retained allocation was not measured.

Final normal and ASan/UBSan focus runs each pass **327,680 exact native LLVM
comparisons**, including **20,480 boundary results**, across 384 defined
functions. Every width checks both extracted fields through select, branch
diamonds and parallel pair/scalar loop PHIs. Each function receives sixteen
edge pairs and 240 mixed pairs, with both condition values or zero through five
loop iterations. High unused argument bits exercise integer/i1/i8 masking.
Loops swap two pair PHIs alongside a scalar counter, then merge zero/loop exits
through another pair PHI. Exact steps are five for select, seven for diamonds,
eight for empty loops, or seven plus six per nonempty loop iteration.

Interpreter controls pass for 896 budget/integer-API failures, 768 poison field
results, 896 defined results with poison or unavailable unchosen pairs, 128
undef condition rejections, 128 frozen-poison fields, four unsupported profiles,
nineteen metadata/type/ID corruptions and five output corruptions. Poison
swapping across loop backedges is included. No native poison result is consumed.
Pair units cover profile shapes/types, scalar conditions, instruction-result
IDs, runtime tags, availability, scalar/pair separation and 16-byte slots.

Sanitized regressions pass with all maintained controls:

| Suite | Comparisons | Result contract |
| --- | ---: | --- |
| Integer execution | 17,280 | Exact native results |
| Float execution | 649,216 | Includes 5,641 arithmetic NaN-class comparisons |
| Half execution | 2,587,648 | Includes 62,180 arithmetic NaN-class comparisons |
| Scalar freeze | 459,806 | Exact defined results plus choice-independent controls |
| Integer overflow | 1,955,832 pairs | 3,911,664 fields; 1,123,914 overflow flags |

Mixed execution, overflow and shared intrinsic units pass, including 524,280
independent narrow overflow pairs and twelve i64 boundaries. Other full
intrinsic/FMA/conversion reference suites were not rerun; numerical helpers
were unchanged. LLVM/native/JIT code is not sanitizer-instrumented; leak
detection is disabled. Existing usize FFI warnings remain. Mixed units link
as a static little-endian AArch64 Linux ELF, with no INTERP/DYNAMIC segment.
No guest execution was performed.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-pair-flow-validation-20261112-r1/`

The bundle contains pinned final source, fixtures, bitcode, every defined
comparison, binaries, generated C, identities, versions, logs and reproduction
notes. The earlier normal run before stronger controls remains diagnostic;
qualification uses `reference-normal-final` and `reference-asan`. Selected
V/LLVM hashes match the pre-build receipt; full compiler/SDK/LLVM/JIT/fenv/
sanitizer dependency closures are not sealed. The unchanged complete typed
inventory checker passes for the original and fresh restore at
`air-pair-flow-restoration-20261112-r1/`, including every path, byte, type, size
and permission. Whole-archive decoding/extraction exit zero; the disposable
decoded tar was removed afterward. Restored sanitizer binaries pass all
327,680 comparisons and every control again, plus pair/mixed/overflow/intrinsic
units. Post-replay full original/restored inventories, relative identities,
selected compiler hashes and archive checksum pass. Replay output and receipts
remain beside the sealed bundles.

No AIR shader, iOS application, GPU command or new Fortnite probe ran. The
default Metal device stub still returns nil; no new frame or launch gate
is verified.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `e987677a0f4aa1bf1e8eb59ace26be6e0b64f35059ddfc29aa157a0e8d983fa8` |
| Complete `.tar.zst` beside bundle | `1c1bc4b22110a2b7ed16ad5b87dc75fe60f9da52cd6033876ca85bd6a591f9f0` |
| `source.tar`, revision `911c9c37b` | `3119354c4d5bcc3c24b187b4bcec68db0870d8b0a8f053a63fccb7a2872a4ebe` |
