# Software Metal vector optional-fusion multiply-add — 2026-11-15

`749815627694d81cce3d8491e738ff193ab231ed` adds unflagged `llvm.fmuladd.vNf16`/`vNf32` for fixed
1..16-lane AIR vectors. It consistently chooses fused evaluation through
the existing integer-based FMA evaluator, matching scalar `fmuladd`. This
is a refinement permitted by [LLVM's optional-fusion contract](https://llvm.org/docs/LangRef.html#llvm-fmuladd-intrinsic).
The product and sum stay exact until one nearest/ties-to-even rounding.
Intermediate product overflow/underflow is avoided. Preferred quiet NaNs,
signed zeros and gradual underflow retain the existing FMA policy.

All three complete sources, canonical names, homogeneous signatures, direct
declaration identity, calling convention, flags and attributes are checked.
Inputs are masked to the declared width. Poison propagates per lane; any
undef source lane rejects at the executed call, including discarded results.
Source freezes repair indeterminate lanes; result freezes do not suppress
prior undef errors. Errors preserve earlier stores, and results are independent
snapshots. Each call costs one step, four lane counts and one of 4,096 shared
construction slots. The 1,000,000 lane-work limit is unchanged. The cache adds
32 distinct identities after the previous 544, for 576 total. Mixed scalar,
void and memory APIs admit these calls; the integer-only API rejects floating
lanes. Vector arguments/returns, PHIs, loads/stores, scalable/wider vectors,
double/bfloat, fast-math flags, tail calls, strict FP and FP exceptions remain
outside the supported profile. AIR aliases remain unsupported.

ASan/UBSan qualification passes:

- `bundle/reference-r3` checks 800 decoded shapes across both formats, every
  count 1..16, five source forms and five constructions. All 403,594 LLVM
  fused-refinement comparisons pass, including 393,216 operand-position sweep
  samples covering every half encoding and deterministic float patterns,
  plus 8,192 directed corpus edge triples. VM `fmuladd` results compare with
  native vector clones calling `llvm.fma`; numeric state predictions and
  explicit freeze choices also use a native scalar FMA oracle. Finite values
  and signed zeros compare bitwise; NaNs compare by class while the VM must
  return its preferred representation.
- A separate table retains 403,594 original native `fmuladd` results and checks
  that each matches either fused evaluation or separate multiply/add evaluation.
  There are 5,161 fused-only choices, zero separate-only and 398,433 matching
  both. The 5,161 distinguishing cases prove the two oracles differ. This is
  the observed host choice; the production comparison always requires its
  chosen fused refinement. Input modules, host CPU/features and native
  projections remain in the bundle.
- There are 1,256 explicit freeze choices, 3,040 poison-store failures, 1,882
  strict undef failures, 819,544 scalar/integer API checks, 20,800 malformed
  metadata/source refusals and 1,600 short-budget refusals. Full output/guard
  bytes and derived bounds are checked with unaligned bindings. Another 144
  controls cover exact fused witnesses, all three sources, discards, freezes,
  snapshots, composition, mixed FMA/fmuladd cached loops, unsupported profiles
  and duplicate declarations. Sixteen declaration-attribute refusals and eight
  exact memory/void storage/work boundaries pass; over-limit profiles reject
  before writes.
- Ten unit and nine reference regressions pass, including the existing FMA
  value/state units, vector/scalar/memory FMA, integer execution, memory
  operands, vector bitcasts, sign, rounding, sqrt, min/max and conversions.
  Shared FMA units check 7,888 exact pattern results, 2,097,152 identity lane
  results and 9,792 three-source state cases. The cache unit covers all 576
  identities. The FMA checker's former unsupported-`fmuladd` case now rejects
  an unsupported AIR alias; the new checker exercises admitted LLVM calls.
  Historical sources and complete bundles remain unchanged.
- Both Swift hash modes pass all 24 software Metal groups with two drained
  runtimes each. Each runtime exercises 102 new `fmuladd` dispatches across
  32 kernels: 84 complete and 18 fail as expected. The existing FMA cases
  run alongside them through the same fixture/dispatch helpers. Cases cover
  corpus triples, eight exact fused witnesses, deferred input writes, sparse
  bindings, pipeline reuse, every source's poison/undef, freezes, discarded
  undef results, old snapshots and fneg/bitcast/comparison/select composition.
  A fast-math `fmuladd` call rejects at pipeline creation. All 56 compute and
  40 blit refusal logs pass.

The first reference run passed its primary comparisons and native-choice
checks, then failed assembling a duplicate FMA declaration in its control
fixture. Removing the redundant declaration fixes the setup; the complete
fresh run passes. Review then identified inherited FMA names in the scalable
guard and shared-limit fixtures. The final checker exercises `fmuladd` there
and passes a complete fresh run. All three source snapshots, binaries,
partial/complete results and logs remain. No production change was needed for
these fixture corrections. New sources were captured before their builds.

Complete retained bundle:

`/Users/alex/Library/Caches/vinix-ios/air-vector-fmuladd-validation-20261115-r1`

It retains fixtures, results, native-choice diagnostics, binaries, generated host C/objects,
compiler captures, commands, helpers and feature-pinned `bundle/source.tar`.
Disk headroom briefly fell to about 500 MiB during finalization. Preservation
therefore uses the repository's full-inventory workflow without another
compressed copy. The maintained V tool records two matching complete typed
inventories, covering every logical file byte, size, path, type, mode, symlink
target and root mode. A separate check compares the retained tree again.
The receipt is beside the bundle at `.inventory.json`; record/check commands,
logs and status are at `.inventory-commands.txt`, `.inventory-driver.log` and
`.inventory-status.txt`. The original remains intact. No compressed archive,
restored replay or historical evidence retirement is claimed.

| Artifact | SHA-256 |
| --- | --- |
| `.inventory.json` | `4cedafd4cf808d50a3a90053b2f3a4f46b3538fa3060085a4262e035ff43226a` |
| `bundle/source.tar`, revision `749815627694d81cce3d8491e738ff193ab231ed` | `baa9340050324a924c37121655d57eaa3e3902e84c9a0a6192fb8d80ca21c24d` |

The standalone compiler was captured after builds; the host compiler before
generation. V libraries, SDKs, assembler, symlink targets and dylibs remain
external prerequisites. Native JIT code is uninstrumented. Leak detection is
disabled and retained heap was not measured. The ordinary runner was not
rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU rendering or
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Inventory integrity does not replace historical launch auditors.
