# Software Metal vector floating-point classification — 2026-11-15

`b5f0b1fa16993d92ebe8148300454330f493e297` adds unflagged `llvm.is.fpclass.vNf16` and `.vNf32` for fixed
1..16-lane AIR inputs and matching i1 result vectors. A defined scalar i32 mask
in 0..1023 selects the ten classes, following [LLVM's classification contract](https://llvm.org/docs/LangRef.html#llvm-is-fpclass-intrinsic).
The existing integer classifier distinguishes signaling/quiet NaNs, both signs
of zero/infinity, subnormals and normals without quieting or host floating-point
operations. Source values are masked to their declared precision.

Admission checks canonical names, actual heterogeneous signatures and source
shapes, direct declaration identity, calling convention, flags and attributes.
Every call validates its mask, including calls after declaration attributes
were cached. Only scalar integer/zero constants in range are admitted;
arguments, instruction results, poison/undef and other mask types reject.
Parameter two's exact `immarg` is allowed for classification while other vector
floating families retain their prior attribute policy. Thirty-two new identities
follow the previous 608, giving 640 cache entries distinguished by input precision.
Poison propagates per lane even for empty/full masks; any undef input lane
rejects at execution, including discarded results. Source freezes repair floating
inputs before classifying; a frozen poison predicate chooses false. Results
are independent snapshots and feed supported vector integer/select operations.
Each call costs one step, two lane counts and one shared construction slot.
The existing 4,096-slot and 1,000,000-work limits remain. Mixed scalar, void
and memory APIs support the calls; the integer-only API rejects floating
construction/classification. Vector arguments/returns, PHIs, loads/stores,
scalable/wider vectors, other precisions, AIR aliases, fast-math, tail calls
and strict FP remain outside the supported profile.

ASan/UBSan macOS ARM64 qualification passes:

- `bundle/reference-r6` checks 800 decoded shapes across both formats, every
  count 1..16, five input forms and five constructions. Its 2,206 bit-exact
  native LLVM comparisons include predicates and floating selects preserving
  exact NaN/zero bits. There are 1,256 fixed freeze choices, 3,056 poison-store
  failures, 1,882 strict undef failures, 16,800 scalar/integer API checks,
  18,400 malformed metadata/source refusals and 1,600 short-budget refusals.
  Full bytes, unaligned bindings and derived buffer extents are checked.
- Eight bounded bulk modules add 2,359,296 native lane comparisons: every half
  encoding and 65,536 deterministic float patterns against eighteen singleton/
  composite masks. Another 65,536 native lane comparisons cover all 1,024 masks
  with twenty class/sign/boundary representatives. All **2,427,038** matrix/bulk
  comparisons are bit-exact. An independent field decoder also checks every
  expected predicate; native inputs remain vectors for all counts and formats.
- Another 154 controls cover source/result freezes, discards, old snapshots,
  predicate/select composition, distinct masks through one cached declaration,
  invalid masks after valid calls, wrong input/mask/result types, changing-source
  loops, unsupported profiles and duplicate identities. Canonical attributes
  admit; sixteen immarg slot/enum/encoding corruptions and four immarg transfers
  to `fabs` reject before writes. Eight exact memory/void storage/work boundaries
  pass, including per-call masks varied over all 1,024 values; over-limit profiles
  reject before writes.
- Focused units check 5,570,560 exact lane values across all masks, ten classes,
  both precisions and every count, plus masking/snapshots and 16,320 state checks.
  Twelve existing unit and thirteen reference regressions pass, including
  scalar classification, vector/scalar/memory FMA and scaling, optional fusion,
  integer execution, memory operands, bitcasts, sign, rounding, sqrt, extrema
  and conversions. The shared cache unit covers all 640 identities.
- Both Swift hash modes pass all 24 software Metal groups with two drained
  runtimes each. Each runtime exercises 736 new dispatches across 52 kernels:
  728 complete and eight fail as expected. Cases cover all ten classes and
  signs against eighteen masks, deferred input writes, sparse bindings,
  pipeline reuse, poison with empty/full masks, undef/discards, source/result
  freezes, old snapshots and predicate/select composition. Tail-call and double
  classification pipelines reject. All 56 compute and 40 blit refusal logs pass.

Thirty-two environment controls require clear Vinix FP exception flags in
nearest/upward/downward/toward-zero modes and compare exact native predicates.
A positive control raises `FE_INVALID` and verifies the flag probe detects it.
The captured LLVM native lowering raises `FE_INVALID` in sixteen controls:
vector masks 3/96 with signaling NaNs, both precisions and all four rounding
modes. Native values still agree. The checker records these deviations in each
bulk module's `environment.tsv`; it requires clear VM flags, exact native values
and no native flags other than `FE_INVALID`. This does not qualify native
exception conformance against LLVM's documented no-exception behavior.
An isolated 192-probe diagnostic confirms the sixteen observations require
signaling NaNs; quiet NaN, infinity, negative-zero, subnormal and normal controls
stay clear. Its input/native IR, target/features, assembly, commands and results
remain under `environment-isolation-results/`.

The first reference attempt passed its matrix and hit the parser's record limit
with one oversized bulk module. Splitting into eight modules preserves all masks
and comparisons without changing production limits. The second attempt stops
at the native exception assertion described above; it is retained intact. The
third completes all bulk comparisons and stops assembling a fast-math call with
an i1 return, which LLVM rejects as invalid IR. That textual guard is removed;
800 decoded fast-math corruptions remain in the metadata checks. The fourth
complete run passes. The fifth run additionally checks the exception-flag
positive control and passes. The final sixth run also repairs each invalid-mask
fixture as a positive baseline and checks direct integer-only API isolation;
the complete suite passes. Sources, binaries and partial/complete results are
retained for every reference attempt. Production code needed no correction
for these fixture/reference issues. Historical checkers and bundles are unchanged.

Complete retained bundle:

`/Users/alex/Library/Caches/vinix-ios/air-vector-fpclass-validation-20261115-r1`

The adjacent `.tar.gz` contains the complete bundle, including failed attempts,
fixtures/results, binaries, generated host C/objects, compiler captures,
commands, helpers and feature-pinned `bundle/source.tar`. The V archiver compares
complete typed inventories before/after compression; the maintained archive
checker decodes every logical payload and compares paths, bytes, sizes, types,
modes, links and root mode. A fresh extraction under `.restored-r1/tree/` passes
that comparison. The restored sanitized classifier then passes its complete
reference suite again, writing outside the restored tree, followed by another
full archive comparison. Original and restored evidence remain intact.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.gz` | `3f51e4780cff111c47f32dfb78c94ced714382a15851c8a8246330b953a1783b` |
| `.tar.gz.inventory.txt` | `1eb764ebc590bad57a4f7bf5d057392fed2ecc88d674bfcb8bb31ca4ba2af913` |
| `bundle/source.tar`, revision `b5f0b1fa16993d92ebe8148300454330f493e297` | `6016dc887d59a612a8bb8031a34af914a096bfc327f42f2c82833f3239908a8e` |

Archive commands/log/status are adjacent at `.archive-command.txt`,
`.archive-driver.log` and `.archive-status.txt`; audit receipts are under
`.tar.gz.audit/`. Extraction/comparison/replay commands/logs/status are under
`.restored-r1/`, with `finished.status.txt` equal to zero.

New primary sources were captured before builds. The standalone compiler was
captured after builds and the host compiler before generation. V libraries,
SDKs, assembler, symlink targets and dylibs remain external prerequisites.
Native JIT code is uninstrumented. Leak detection is disabled; retained heap
was not measured. The ordinary runner was not rebuilt. These are synthetic CPU
fixtures: no Apple shader, GPU rendering/presentation, Vinix guest, Fortnite
frame or launch gate is newly verified. Archive integrity does not replace
historical launch auditors or authorize retiring their original evidence.
