# Software Metal vector integer extrema — 2026-11-16

`2381b9e17c00aed5facb0794fa91d3b58c9da297` adds ordinary direct vector `llvm.smin`, `llvm.smax`, `llvm.umin`
and `llvm.umax` calls for fixed 1..16-lane integer vectors at widths i1..i64.
Both arguments and the result must have identical types. Signed operations
compare two's-complement values, including i1's -1 and 0; unsigned operations
compare bit patterns. The selected operand's exact masked bits are returned,
following the [LLVM integer-extrema contract](https://llvm.org/docs/LangRef.html#llvm-smin-intrinsic).

The mixed scalar, integer-only, void and memory APIs admit these vector calls.
Floating producers retain their mixed-only policy. Canonical names, exact shapes/
signatures, declaration identity, ordinary flags/calling convention and both
sources are checked. Harmless function attributes remain allowed; return and
parameter attributes, including `immarg`, reject. Cold unsupported blocks reject
before writes. Vector arguments/returns/PHIs/loads/stores, scalable/oversized
vectors, i65/wider lanes and AIR aliases remain outside the profile.

Poison propagates per lane from either source. Any undef source lane fails even
for discarded results. Source freezes choose zero for indeterminate lanes;
result freezes choose zero for poison. Results are independent snapshots. The
existing scalar evaluator compares unsigned keys, flipping the sign bit for
signed operations. It uses no signed casts or overflowing signed arithmetic.
No normal-path allocation or host builtin is added.

Four separate 1,024-entry width/count ranges occupy slots 6848..7871, 7872..8895,
8896..9919 and 9920..10943, in signed-min/signed-max/unsigned-min/unsigned-max order.
The shared declaration cache now has 10,944 stack entries. Attributes are cached
per declaration/identity; each call checks both sources. A call costs one step,
three lane counts of profiling work and one construction slot. Existing
4,096-result and 1,000,000-work limits remain unchanged.

ASan/UBSan macOS ARM64 qualification passes:

- Units check **4,087,168 independent value comparisons**, using safe signed
  reconstruction and direct unsigned comparisons. Every i1..i8 pair and 4,096
  wider patterns per operation, all shapes, signed/unsigned boundaries, high-bit
  noise, symmetry, idempotence and snapshots are covered. Another **835,584
  poison/undef/freeze checks** cover both operands. The cache test covers all
  10,944 identities. Older units replace admitted vector-smin name guards with
  unsupported vector-abs names while retaining positive coverage.
- `bundle/reference-r2` checks **102,400 decoded shapes** across four operations,
  five source forms and five construction paths. It checks **282,368 exact native
  results**, 160,768 fixed freeze choices, **391,168 poison-store refusals**,
  **240,896 strict-undef refusals**, 2,150,400 scalar/integer API cases,
  2,826,240 malformed metadata/source refusals and 307,200 short-budget refusals.
  Exact steps, unaligned bindings, derived extents and every output byte agree.
- Bulk modules add **1,267,072 exact native lane comparisons**, exhausting all
  i1..i8 pairs and checking 4,096 wider pairs per operation. Matrix plus bulk
  totals **1,549,440 exact native comparisons**. VM noisy padding and native
  canonical padding agree with the independent oracle. Native comparisons use
  defined extracted results; indeterminate extracted results are not compared.
  Native padding behavior is not qualified.
- **4,420 controls** check all four declarations in one function at every width,
  both poison/undef sources through four APIs, discarded results, repaired
  positive attribute baselines, forbidden return/parameter immarg groups and
  four cold i65 blocks. Attribute-refusal memory fixtures have valid, full-sized
  output bindings, so bounds errors cannot stand in for attribute rejection.
  Sixteen shared work/storage boundary checks pass through four APIs. The exact
  work boundary uses 4,096 16-lane calls plus 50,212 extracts; one more extract
  rejects before writes.
- Twenty-three unit and twenty-four reference regressions pass, plus two focused
  executions: **49 total**. These include scalar extrema/funnel shifts, vector
  funnel shifts, both zero counts, population count, bit reversal, byte swap,
  integer/vector execution, memory, bitcasts, conversions, sign/rounding/sqrt/
  extrema, FMA/scaling and classification. Historical reference checkers remain
  unchanged.
- Both Swift hash modes pass all **24 software Metal groups**, with two drained
  runtimes each. Each runtime adds **1,504 dispatches across 288 kernels**:
  **1,408 complete and 96 fail as expected**. Four families, equal inputs,
  freezes, snapshot changes, chains, deferred writes, sparse bindings, guard
  words and failed completion are covered. Eight tail/i65 pipelines reject.
  All 56 compute and 40 blit refusal logs pass. The harness retains every original
  assertion and executes both modes in separate processes from one build.

The first reference run passes, but review found an undersized output binding
in the new attribute-refusal fixture. That could also fail on bounds if an
attribute were wrongly admitted. The final checker uses the full-sized binding,
after proving a valid compact attribute group through all four APIs. The complete
second run passes and supplies this checkpoint's qualification. Both attempts,
including sources, binaries, fixtures, comparisons and logs, remain retained.
No production correction was needed during reference qualification.

Complete retained original, started on November 15:

`/Users/alex/Library/Caches/vinix-ios/air-vector-integer-extrema-validation-20261115-r1`

The typed inventory covers all logical file bytes, sizes, modes, directory/root
modes and symlink targets. Recording compares two complete inventories, then a
separate check compares the root again. The adjacent compressed archive is fully
decoded by the maintained libarchive checker and compared against the complete
original. The producer rechecks the original inventory, archive checksum and tool
identities afterward. All pass. Originals remain retained; no second expanded
restoration or execution replay is claimed. No older evidence is removed or altered.

| Artifact | SHA-256 |
| --- | --- |
| Adjacent `.tar.gz` | `02d16d15c9e650b5706179d3ca158284ee474b8b1d512db0538995b2c87a3558` |
| Adjacent `.inventory.json` | `e0620869a770b06c786e71dbfc4090c8f4c1b29631317dd191856e1d997f1a21` |
| `bundle/source.tar`, revision `2381b9e17c00aed5facb0794fa91d3b58c9da297` | `a430b2df2086569b3db046749b7289005f1c56f72aff90242a02bd5fb669a476` |

Commands/log/status are adjacent under `.inventory-record.*`, `.inventory-check.*`
and `.archive.*`, all with zero statuses. `.tar.gz.audit/` retains archive checks;
`.tar.gz.sha256` also pins the full text inventory. The captured compatibility V
sources match `bundle/verified-inputs.sha256`; focused-unit and final-reference
source comparisons pass too.

The host compiler was captured before generation; the standalone compiler is
captured after checks. V libraries, SDKs, assembler, symlink targets and dylibs
remain external prerequisites. Native JIT is uninstrumented. Leak detection is
disabled; retained heap was not measured. The ordinary runner was not rebuilt.
These are synthetic CPU fixtures: no Apple shader, GPU rendering/presentation,
Vinix guest, Fortnite frame or launch gate is newly verified. Integrity receipts
do not replace historical launch auditors or authorize removing their originals.
