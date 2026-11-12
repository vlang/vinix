# Zero and poison pair constants checkpoint — 2026-11-12

`eeb7104d4` adds zero and poison constants for literal unpacked `{iN, i1}`
pairs across i1..i64. Extraction, insertion, select and PHIs share scoped,
exactly typed source validation. Zero initializes both fields; poison marks
both fields poison. Field insertion can repair either field independently,
enabling construction from a poison seed. All blocks, including unchosen
sources, are preflighted. Other parsed constant records, including undef and
aggregate field lists, remain unsupported. LLVM may canonicalize an all-zero
field list into a supported zero record. Aggregate arguments, returns,
freeze and other layouts remain unsupported; the integer-only API retains
its scalar profile. See the
[bounded contract and maintained tests](../../compat/ios/airbitcode/SCALAR-PAIR-CONSTANTS.md).

Constant lookup reads immutable pool metadata and returns the existing
16-byte tagged value. Generated C shows stack value construction with no
aggregate-record walk or valid-path allocation. The three owned execution
arrays, cleanup and 1,768-entry fixed declaration cache remain unchanged.
No numerical helper or intrinsic/cache range changes. Retained allocation
was not measured. Constant reads consume no instruction steps.

Normal and ASan/UBSan focus runs each pass **524,288 exact native LLVM
comparisons**, including **32,768 edge results**, across 1,024 functions.
Every width covers both fields, direct zero extraction, construction from
zero/poison, partial repair, constant select, branch PHIs, repair after a
poison PHI and zero-seeded loop accumulation. Each function receives sixteen
edge triples and 240 mixed triples, including unused high argument bits.
Loops cover zero through five iterations. Only defined extracted fields
cross the native ABI. Exact step counts cover direct extraction (2),
construction/select (4), partial repair (3), branch PHIs (5/6), repaired PHIs
(7/8) and loops (5 + 8 per iteration).

Interpreter controls pass for 2,176 budget/integer-API failures, 512 poison
results, 256 defined zero results with unchosen poison, 128 frozen-poison
fields, 1,024 unsupported constant-kind uses, six extraction-metadata
corruptions, four constant-metadata corruptions and five output corruptions.
Final normal and sanitized units cover module zero/local poison, runtime
reads, all consumers, 16-byte layout, scope/type/argument/range guards, six
unsupported kinds and corrupt metadata. Qualified binaries are
`reference-normal`, `reference-asan`, `unit-final-normal` and `unit-final-asan`;
earlier diagnostic outputs are identified in `reproduction.md`.

Sanitized regressions pass with all maintained controls:

| Suite | Comparisons | Result contract |
| --- | ---: | --- |
| Integer execution | 17,280 | Exact native results |
| Float execution | 649,216 | Includes 5,641 arithmetic NaN-class comparisons |
| Half execution | 2,587,648 | Includes 62,180 arithmetic NaN-class comparisons |
| Scalar freeze | 459,806 | Exact defined results plus choice-independent controls |
| Integer overflow | 1,955,832 pairs | 3,911,664 fields; 1,123,914 overflow flags |
| Pair select/PHI flow | 327,680 | Exact results plus poison controls |
| Pair insertion | 786,432 | Exact results plus independent field-poison controls |

Insertion, pair-flow, mixed execution and overflow units pass. Existing
overflow/flow negative fixtures now use unsupported undef or nonzero
aggregate-record constants, retaining seven and four profile guards. The
insertion source-ID corruption remains a declaration mismatch. Other full
flag/intrinsic/FMA/conversion reference suites were not rerun; numerical
helpers were unchanged. LLVM/native/JIT code is not sanitizer-instrumented;
leak detection is disabled. Existing usize FFI warnings remain. Mixed units
link as a static little-endian AArch64 Linux ELF with no INTERP/DYNAMIC
segment. No guest execution is claimed.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-pair-constants-validation-20261112-r1/`

It contains pinned source, fixtures, bitcode, every defined comparison,
binaries, generated C, identities, versions, logs and reproduction notes.
Selected V/LLVM hashes match the pre-build receipt; full compiler/SDK/LLVM/
JIT/fenv/sanitizer dependency closures are not sealed. The unchanged complete
typed inventory checker passes for the original and fresh restore at
`air-pair-constants-restoration-20261112-r1/`, including every path, byte,
type, size and permission. Whole-archive decoding/extraction succeeded; the
disposable decoded tar was removed afterward. Restored sanitizer binaries
pass all 524,288 comparisons and every control again, plus final constant,
insertion, pair-flow, mixed and overflow units. Post-replay full original/
restored inventories, relative identities, selected compiler hashes and
archive checksum pass. Replay output and receipts remain beside the bundles.

No AIR shader, iOS application, GPU command or new Fortnite probe ran. The
default Metal device stub still returns nil; no new frame or launch gate
is verified.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `9dd27595a2517ee38ea83cadc331c1676aa0c05b6a306d6344c642b589469763` |
| Complete `.tar.zst` beside bundle | `38639dfa11cf2ade6203732a3275419df8f8a5f313bf8fb6fb8181eecc8755d2` |
| `source.tar`, revision `eeb7104d4` | `3dd815aa7ce1a53954d1a8db4c801b1f040dad11ed85d666396c97323e3e5f45` |
