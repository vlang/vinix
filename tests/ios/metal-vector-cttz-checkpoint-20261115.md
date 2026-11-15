# Software Metal vector trailing-zero count — 2026-11-15

`cd5271020cdaf9e8dc05fe8c9fe017eff5c43a7f` adds ordinary direct `llvm.cttz.vNiW` calls for fixed 1..16-lane
integer vectors, widths i1..i64. A false i1 flag returns W on zero; a true flag
produces lane poison, following [LLVM's trailing-zero contract](https://llvm.org/docs/LangRef.html#llvm-cttz-intrinsic).
Both scalar execution APIs, void and memory execution admit these vector calls.
The scalar poison-aware evaluator supplies results; untagged integer evaluators
still reject trailing-zero operations. The normal lane path adds no allocation.

The shared direct-call validator checks canonical names, exact vector types,
width/count, declarations, signatures, flags and calling convention. Every call
requires a nonsplat, defined i1 integer/zero constant whose raw value is 0/1,
including calls after declaration attributes were cached. Arguments, SSA results,
poison/undef, wrong types and malformed values reject before execution. Only
parameter two's exact `immarg` is permitted alongside harmless function attributes.
Cold blocks are validated too. Floating producers retain their mixed-only policy.

Poison propagates per lane and any undef source lane fails, even for discarded
results. Source freezes choose zero for indeterminate input; a true-flag call
can then produce poison. Result freezes choose zero for poison. Results are
independent snapshots. Slots 3776..4799 add 1,024 width/count identities after
all earlier slots, making 4,800 stack entries. Flags share an identity but are
read per call. Each call costs one step, two lane counts of profiling work and
one shared construction slot. Existing 4,096-result and 1,000,000-work limits
remain. Vector funnel shifts, vector arguments/returns/PHIs/loads/stores,
scalable/oversized vectors, i65 and wider lanes, AIR aliases and flagged calls
remain outside the supported profile.

ASan/UBSan macOS ARM64 qualification passes:

- Units check **2,065,472 value/poison lane comparisons**, independently using
  the standard-library trailing-zero counter adjusted to the declared width,
  plus **208,896 lane-state checks**. Both flags, every narrow encoding, wide
  patterns, individual bits, high-bit noise, snapshots and guards are covered.
  The shared cache unit covers all 4,800 identities. Older vector units update
  unsupported-cttz names to unsupported-fshl names while retaining their value/
  state coverage and rejection by untagged evaluators.
- `bundle/reference-r1` checks **51,200 decoded shapes**, all widths/counts,
  both flags, five input forms and five construction paths. It checks **114,713
  exact native values**, 57,901 fixed freeze choices, **244,538 poison-store
  failures**, **120,448 strict undef failures**, 1,075,200 mixed/integer API cases,
  1,413,120 malformed metadata/source refusals and 153,600 short-budget refusals.
  Exact steps, whole output bytes, unaligned bindings and derived extents agree.
- Bounded bulk modules add **655,424 exact defined native lane comparisons**,
  exhausting narrow inputs for a false flag and nonzero narrow inputs for a
  true flag, with 4,096 wide patterns per flag. True-flag zeros in the bulk input
  use one, ensuring native calls have defined results. Independent zero/poison
  checks remain in the matrix and units. Matrix plus bulk totals **770,137 exact
  native comparisons**. VM high-bit noise and native canonical padding are checked
  against the independent oracle; native padding behavior is not qualified.
- **2,769 controls** cover both flag values through one cached declaration for
  every width, repaired positive baselines, and rejection of argument/SSA/poison/
  undef flags after a valid call. Raw i1 words mutated to 2 reject through all
  four APIs. Immarg return/first/other slots, enum and encoding corruptions reject
  before writes. An LLVM-valid i65 call in a cold block also rejects. Sixteen exact
  shared storage/work boundary checks pass through all four APIs, including
  over-limit refusal before writes.
- Nineteen existing unit and twenty reference regressions pass, including
  scalar zero counts, population count, bit reversal, byte swap, integer/vector
  binary execution, memory operands, bitcasts, conversions, sign/rounding/sqrt/
  extrema, FMA/scaling, optional fusion and classification. Historical reference
  checkers are unchanged.
- Both Swift hash modes pass all 24 software Metal groups, with two drained
  runtimes each. Each runtime adds **448 dispatches across 144 kernels**:
  **384 complete and 64 fail as expected**. Eight representative widths include
  i1, i3, i31, i48 and i64. Both flags, explicit zero, freezes, snapshots, chains,
  deferred input writes, sparse bindings, guard words and failed completion are
  checked. Tail and i65 pipelines reject. All 56 compute and 40 blit refusal logs pass.

The initial qualification driver, normal host and final leading-zero regression
stopped without completion receipts; their cause is not established. Completed
checks and available partial files remain retained. `resume.v` uses the same binaries
and fresh `vector-ctlz-resumed-results` / `software-resumed` directories. It runs
both host hash modes in separate processes, retains every original host marker
assertion, and checks all 24 groups plus refusal-log counts. The resumed final
reference and both host runs pass. `software-resume.status.txt` and the final
qualification receipt are zero; the incomplete harness is not marked successful.

Complete retained bundle:

`/Users/alex/Library/Caches/vinix-ios/air-vector-cttz-validation-20261115-r1`

The complete original bundle remains retained in place, including fixtures/
results, binaries, generated host C/objects, compiler captures, commands, helpers
and feature-pinned `bundle/source.tar`. A typed inventory receipt records every
logical file byte, size, mode, directory/root mode and symlink target. Recording
compares two complete inventories, followed by a separate `check-inventory`.

The adjacent `.tar.gz` archive is produced by the maintained V workspace tool.
Its libarchive checker decodes every payload and compares the complete named
root, including sparse logical bytes and recorded metadata, against the retained
original. The tool rechecks the full original inventory, archive checksum and
tool identities afterward. All checks pass. No second expanded restoration or
execution replay is claimed, and no older evidence has been removed or altered.

| Artifact | SHA-256 |
| --- | --- |
| Adjacent `.tar.gz` | `d5971db72a99dab5a70d9392f72811db6c56b908c71d7741f34b7d894be9f353` |
| Adjacent `.inventory.json` | `56b8477116d4f79f416f980315bec4c37bee29b879032845bbb79ee243fe0a5c` |
| `bundle/source.tar`, revision `cd5271020cdaf9e8dc05fe8c9fe017eff5c43a7f` | `e1ac3f7e565cc941b568c06f88305c96c6aab5f19cd392c7348dfa65ade893c2` |

Commands/log/status are adjacent under `.inventory-record.*`,
`.inventory-check.*` and `.archive.*`, with all status files zero. Archive
verification receipts are under `.tar.gz.audit/`; `.tar.gz.sha256` also pins
its complete text inventory. Recheck the retained root using the retained
`inventory-check check-inventory BUNDLE BUNDLE.inventory.json` executable.
`bundle/verified-inputs.sha256` records the exact captured compatibility V
sources; the checker also matches focused-unit and new-reference inputs.

Primary sources were captured before builds, the standalone compiler afterward,
and the host compiler before generation. V libraries, SDKs, assembler, symlink
targets and dylibs remain external prerequisites. Native JIT is uninstrumented.
Leak detection is disabled; retained heap was not measured. The ordinary runner
was not rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU rendering/
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Integrity receipts do not replace historical launch auditors or permit retiring
their original complete evidence.
