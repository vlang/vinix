# Software Metal vector funnel shifts — 2026-11-15

`2334fa35cecb7a8652bfb30d1248536fe6c42b82` adds ordinary direct `llvm.fshl.vNiW` and `llvm.fshr.vNiW` calls
for fixed 1..16-lane integer vectors at widths i1..i64. All three arguments and
the result have identical types. Each shift amount is masked to W bits, then
reduced modulo W. Equal high/low operands give rotations. This follows the
[LLVM funnel-shift contract](https://llvm.org/docs/LangRef.html#llvm-fshl-intrinsic).

The mixed scalar, integer-only, void and memory APIs admit these vector calls;
floating producers retain their mixed-only policy. The direct-call validator
checks canonical names, ordinary flags/calling convention, declaration identity,
exact signatures/types and every source before execution. Harmless function
attributes remain allowed. Return/parameter attributes, including `immarg`, reject.
Cold unsupported blocks reject before memory writes. Vector arguments/returns/
PHIs/loads/stores, scalable/oversized shapes, i65/wider lanes and AIR aliases remain
outside this profile.

Poison propagates from any of the three inputs, including an input not selected
by a zero shift. LLVM's [funnel-forming transformation](https://llvm.org/docs/doxygen/InstCombineSelect_8cpp_source.html)
also accounts for this distinction. Any undef source lane fails even when the
result is discarded. Source freezes choose zero for indeterminate lanes; result
freezes choose zero for poison. Results are independent snapshots. Production
reuses the existing scalar unsigned-shift evaluator, with no new normal-path
allocation or host builtin. No shift by 64 occurs.

Slots 4800..5823 and 5824..6847 add 2,048 separate left/right width/count identities,
making 6,848 shared stack entries. Attributes are cached per declaration/identity;
all three sources are checked per call. Each call costs one instruction, four
lane counts of profiling work and one shared construction slot. Existing
4,096-result and 1,000,000-work limits remain unchanged.

ASan/UBSan macOS ARM64 qualification passes:

- Units check **1,968,288 independent value comparisons** using per-output-bit
  selection from a conceptual concatenation, including every i1..i5 triple and
  4,096 wider patterns per direction, all widths/counts, modulo/zero shifts,
  high-bit noise and snapshots. Another **626,688 poison/undef/freeze checks**
  cover all three inputs. The cache unit checks all 6,848 identities. Older units
  replace newly admitted funnel-left name guards with unsupported vector-smin
  names, preserving positive coverage and unary evaluator rejection.
- `bundle/reference-r2` checks **51,200 decoded shapes**, both directions, five
  source forms and five construction paths. It checks **141,184 exact native
  results**, 80,384 fixed freeze choices, **195,584 poison-store refusals**,
  **120,448 strict-undef refusals**, 1,075,200 scalar/integer API cases,
  1,597,440 malformed metadata/source refusals and 153,600 short-budget refusals.
  Exact steps, derived extents, unaligned bindings and all output bytes agree.
- Bulk modules add **655,424 exact native lane comparisons**, exhausting A's
  i1..i16 encodings with paired B/shift patterns; wider widths receive 4,096
  deterministic triples per direction. They do not exhaust every narrow triple;
  unit tests exhaust all triples through i5. Matrix plus bulk totals
  **796,608 exact native comparisons**. VM noisy padding and native canonical
  padding are checked against the independent oracle. Native padding behavior
  is not qualified; indeterminate native results are never executed for comparison.
- **6,482 controls** check both declarations in one function at every width,
  every poison/undef operand including zero shifts through four APIs, discarded
  results, repaired positive attribute baselines, forbidden return/parameter
  `immarg`, and cold i65 blocks. Sixteen exact shared storage/work boundary checks
  pass through four APIs, including refusal before writes. The work boundary uses
  4,096 16-lane calls plus 46,116 extracts; one additional extract rejects.
- Twenty-one unit and twenty-two reference regressions pass in addition to the
  two focused executions, including scalar funnel shifts, both zero counts,
  population count, bit reversal, byte swap, integer/vector execution, memory,
  bitcasts, conversions, sign/rounding/sqrt/extrema, FMA/scaling and classification.
  Historical reference checkers remain unchanged.
- Both Swift hash modes pass all **24 software Metal groups**, with two drained
  runtimes each. Each runtime adds **752 dispatches across 144 kernels**:
  **704 complete and 48 fail as expected**. Cases include both directions,
  rotations, freezes, snapshot changes, chains, deferred inputs, sparse slots,
  guard words and failed completion. Four tail/i65 pipelines reject. All 56
  compute and 40 blit refusal logs pass. The host harness retains all original
  assertions and runs its two hash modes in separate processes from one build.

The first reference attempt completes its comparison matrix and bulk sweeps,
then fails in the new attribute control's assumption that LLVM emits a four-word
attribute group. LLVM adds intrinsic attributes. The corrected control first
proves a compact harmless group valid through all four APIs, then tests exact
immarg groups. The complete second run passes. Both attempts and their sources,
binaries, commands and outputs remain retained. No production correction was
needed during reference qualification.

Complete retained original:

`/Users/alex/Library/Caches/vinix-ios/air-vector-funnel-validation-20261115-r1`

A typed inventory covers every logical file byte, size, mode, directory/root mode
and symlink target. Recording compares two inventories; a separate check compares
the root again. The adjacent compressed archive is fully decoded by the maintained
libarchive checker and compared with the complete original. The producer rechecks
the original inventory, archive checksum and tool identities afterward. All checks
pass. Originals remain retained; no second expanded restoration or execution replay
is claimed. No older evidence has been removed or altered.

| Artifact | SHA-256 |
| --- | --- |
| Adjacent `.tar.gz` | `782587791223c2bad878c11bb0bc23aecaff21ee0effbcacc9b31f956482ff9a` |
| Adjacent `.inventory.json` | `90913292ed93b8b82b0ba62ed135f46e46b774fb7142fa12ca17b5411eaa76ae` |
| `bundle/source.tar`, revision `2334fa35cecb7a8652bfb30d1248536fe6c42b82` | `ed6f0591a47f31976711260084a80163769b1bec162916a998b8d4ea6dcc3c3d` |

Commands/log/status are adjacent under `.inventory-record.*`, `.inventory-check.*`
and `.archive.*`, with all status files zero. Archive verification receipts are
under `.tar.gz.audit/`; `.tar.gz.sha256` also pins its complete text inventory.
`bundle/verified-inputs.sha256` matches captured compatibility V sources exactly;
the input checker also matches focused-unit and final-reference sources.

The host compiler was captured before generation; the standalone compiler is
captured after checks. Libraries, SDKs, assembler, symlink targets and dylibs remain
external prerequisites. Native JIT is uninstrumented. Leak detection is disabled;
retained heap was not measured. The ordinary runner was not rebuilt. These are
synthetic CPU fixtures: no Apple shader, GPU rendering/presentation, Vinix guest,
Fortnite frame or launch gate is newly verified. Integrity receipts do not replace
historical launch auditors or authorize removing their original complete bundles.
