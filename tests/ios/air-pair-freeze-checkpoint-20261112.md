# Overflow pair freeze checkpoint — 2026-11-12

`dd615be31` adds unflagged freeze for literal unpacked `{iN, i1}` pairs
across i1..i64 in the mixed scalar API. Each defined field keeps its bits;
each poison field independently chooses zero. A direct undef pair chooses
two zero fields. Both poison tags clear while the aggregate tag survives.
The existing result slot stores each dynamic choice, so repeated uses agree.
This follows LLVM's [element-wise freeze contract](https://llvm.org/docs/LangRef.html#freeze-instruction).
See the [bounded contract and maintained tests](../../compat/ios/airbitcode/SCALAR-PAIR-FREEZE.md).

Preflight checks matching types, one operand, zero opcode, no targets/indices,
supported layout and constant policy in every block. Direct undef is admitted
only by freeze; ordinary pair extraction/insertion/select/PHIs retain their
previous source policy. Earlier undef scalar insertion, invalid division or
unavailable SSA values still error. Aggregate arguments/returns, other
constant records, packed/named/nested layouts, vectors and other field types
remain unsupported. The integer-only API retains its scalar profile.

Generated C shows immutable pool lookup and stack value construction, with no
valid-path allocation. The 16-byte value layout, three owned arrays, cleanup
and 1,768-entry declaration cache remain unchanged. No numerical helper,
intrinsic range or owned storage changes. Retained allocation was not measured.
Every visited freeze consumes one instruction step.

Normal and ASan/UBSan focus runs each pass **524,288 exact native LLVM
defined/property comparisons**, including **32,768 edge results**, across
1,152 functions. Each width covers both fields, defined construction,
overflow calls, zero constants, partial poison, select, branch PHIs and
zero-to-five-iteration loops. Each function receives sixteen edge triples
and 240 mixed triples with unused high argument bits. Arbitrary native
choices are never compared with the local zero policy. Repeated extraction/
XOR and loop properties instead hold for every permitted choice; defined
neighbors and accumulation are checked independently against input bits.
Exact budgets include direct constant freeze/extract/return (3), partial or
overflow freeze (4), construction/select (5), branch PHIs (6/7) and loops
(6 + field ordinal + 10 per iteration).

Interpreter controls pass for 2,432 budget/integer-API failures, 640 zero
choices, 256 preceding-error rejections, seven unsupported profiles, sixteen
metadata corruptions across live/dead blocks and five output corruptions.
Units pass 2,048 width/pattern/poison states, defined-neighbor preservation,
independent zero choices, idempotence, 16-byte layout, scoped constants,
freeze-only undef, shape/type/constant-metadata guards and runtime availability.

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
| Zero/poison pair constants | 524,288 | Exact results plus constant-policy controls |

Pair-constant, insertion, pair-flow, mixed and overflow units pass. The older
overflow fixture's freeze rejection now uses an unsupported nonzero aggregate
record, retaining its seven profile guards. Ordinary overflow-result freeze
is positively covered by the new checker. Other full flag/intrinsic/FMA/
conversion reference suites were not rerun; numerical helpers were unchanged.
LLVM/native/JIT code is not sanitizer-instrumented; leak detection is disabled.
Existing usize FFI warnings remain. Mixed units link as a static little-endian
AArch64 Linux ELF with no INTERP/DYNAMIC segment. No guest ran.

Complete evidence is retained outside Git:

`/Users/alex/Library/Caches/vinix-ios/air-pair-freeze-validation-20261112-r1/`

It contains pinned source, fixtures, bitcode, every comparison, binaries,
generated C, identities, versions, logs and reproduction notes. Selected
V/LLVM identities were recorded at a checkpoint after normal builds and
rechecked after all builds; full compiler/SDK/LLVM/JIT/fenv/sanitizer dependency
closures are not sealed. Original normal and sanitized outputs remain intact.

The unchanged complete typed inventory checker passes for the original and
fresh restore at `air-pair-freeze-restoration-20261112-r1/`, covering every
path, byte, type, size and permission. Whole-archive decoding/extraction
succeeded; the disposable decoded tar was removed afterward. Restored
sanitizer binaries pass all 524,288 comparisons and every control again,
plus pair-freeze, constant, insertion, pair-flow, mixed and overflow units.
Post-replay full original/restored inventories, relative identities, selected
compiler hashes and archive checksum pass. Replay output and receipts remain
beside the sealed bundles.

No AIR shader, iOS application, GPU command or new Fortnite probe ran. The
default Metal device stub still returns nil; no new frame or launch gate
is verified.

| Artifact | SHA-256 |
| --- | --- |
| Inventory JSON beside bundle | `e7231fe61fa5a33920fa8ad88cae13d53cf43cde5fabf71fba35de71cb1d683b` |
| Complete `.tar.zst` beside bundle | `28c9b1eb051f62449cedc1c669109b486dec5dc3c0814af79f9041d96dd8ee0d` |
| `source.tar`, revision `dd615be31` | `103e47e1da7168a520334b1681ec6786cfe9bed2050c8eb0c47015a36e4d3284` |
