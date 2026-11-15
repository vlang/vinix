# Software Metal vector leading-zero count — 2026-11-15

`c6b6821df6f8def13d1d38afa409d57b679d2ae9` adds ordinary direct `llvm.ctlz.vNiW` calls for fixed 1..16-lane
integer vectors, widths i1..i64. A false i1 flag returns W on zero; a true flag
produces lane poison, following [LLVM's leading-zero contract](https://llvm.org/docs/LangRef.html#llvm-ctlz-intrinsic).
Both scalar execution APIs, void and memory execution admit these vector calls.
The scalar poison-aware evaluator supplies results; untagged integer evaluators
still reject leading-zero operations. The normal lane path adds no allocation.

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
independent snapshots. Slots 2752..3775 add 1,024 width/count identities after
all earlier slots, making 3,776 stack entries. Flags share an identity but are
read per call. Each call costs one step, two lane counts of profiling work and
one shared construction slot. Existing 4,096-result and 1,000,000-work limits
remain. Vector trailing-zero count, vector arguments/returns/PHIs/loads/stores,
scalable/oversized vectors, i65 and wider lanes, AIR aliases and flagged calls
remain outside the supported profile.

ASan/UBSan macOS ARM64 qualification passes:

- Units check **2,065,472 value/poison lane comparisons**, independently using
  the standard-library leading-zero counter adjusted to the declared width,
  plus **208,896 lane-state checks**. Both flags, every narrow encoding, wide
  patterns, individual bits, high-bit noise, snapshots and guards are covered.
  The shared cache unit covers all 3,776 identities. Older vector units update
  unsupported-ctlz names to unsupported-cttz names while retaining their value/
  state coverage and rejection by untagged evaluators.
- `bundle/reference-r2` checks **51,200 decoded shapes**, all widths/counts,
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
- Eighteen existing unit and nineteen reference regressions pass, including
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

The first reference build fails on an iteration-variable scope collision in
the new control fixture. The second uses a distinct attribute-loop variable,
builds, and passes the full suite. Attempted source/build logs and the complete
final source/binary/results are retained. Production needed no correction during
reference qualification.

Complete retained bundle:

`/Users/alex/Library/Caches/vinix-ios/air-vector-ctlz-validation-20261115-r1`

Qualification began with about 2.9 GiB free. To avoid another large copy, the complete
original bundle is retained in place, including fixtures/results, binaries,
generated host C/objects, compiler captures, commands, helpers and feature-pinned
`bundle/source.tar`. The maintained V inventory tool records every logical file
byte, size and mode, directory/root mode and symlink target. Recording compares
two complete inventories before publishing the adjacent `.inventory.json` receipt;
a separate `check-inventory` compares the retained root again. Both pass.
This checkpoint claims in-place integrity verification, without an archive or
restoration replay. No older evidence has been removed or altered.

| Artifact | SHA-256 |
| --- | --- |
| Adjacent `.inventory.json` | `328e72a244d787a21710c95745ef8b5f74c91f2b1f46c64b0cf21e792d7ff9e4` |
| `bundle/source.tar`, revision `c6b6821df6f8def13d1d38afa409d57b679d2ae9` | `8b58e4365b36f1cdc160fbaa84a8814c15dc94b5808213e2ce445633718c251a` |

Commands/log/status are adjacent under `.inventory-record.*` and
`.inventory-check.*`, with both status files zero. Recheck using the retained
`inventory-check check-inventory BUNDLE BUNDLE.inventory.json` executable.

The final runtime fixture removes one extra blank line at EOF after testing.
`check-source-inputs.v` asserts this is exactly one LF and records the final
hash in `bundle/verified-inputs.sha256`; `bundle/runtime-final-source.v` retains
the final source beside the original build input. No executable statements changed.

Primary sources were captured before builds, the standalone compiler afterward,
and the host compiler before generation. V libraries, SDKs, assembler, symlink
targets and dylibs remain external prerequisites. Native JIT is uninstrumented.
Leak detection is disabled; retained heap was not measured. The ordinary runner
was not rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU rendering/
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Integrity receipts do not replace historical launch auditors or permit retiring
their original complete evidence.
