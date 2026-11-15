# Software Metal vector fused multiply-add — 2026-11-15

`8b6052b344e14cd1acd943786944aeeb009e755c` adds unflagged `llvm.fma.vNf16`/`vNf32` calls for fixed
1..16-lane AIR vectors. Each lane uses the existing integer-based scalar FMA:
the product and sum remain exact until one nearest/ties-to-even rounding, as
required by [LLVM FMA](https://llvm.org/docs/LangRef.html#llvm-fma-intrinsic).
There is no intermediate product overflow or underflow. Signed zeros,
infinities, gradual underflow and preferred positive quiet NaNs follow the
existing scalar policy. All three inputs are masked to their declared width.
Vector `fmuladd` remains unsupported.

The existing profile scanner validates all three complete sources, exact
homogeneous signatures, direct declaration identity, calling convention,
flags and attributes. Execution reads the third source on each call. Poison
propagates per lane; any undef source lane rejects at the executed call,
including discarded results. Source freezes repair indeterminate lanes;
result freezes do not suppress prior undef errors. Errors retain earlier
stores. Independent snapshots compose with fneg, raw bitcasts, comparisons,
selects and shuffles. Each call costs one step, four lane counts of shared
work and one of the existing 4,096 construction slots. The 1,000,000 shared
lane-work limit remains. The declaration cache expands from 512 to 544
entries, preserving earlier keys. Mixed scalar, void and memory APIs admit
the calls; the integer-only API rejects floating lanes. Vector arguments,
returns, PHIs and loads/stores, scalable/wider vectors, double/bfloat,
fast-math flags, tail calls, strict FP and FP exceptions remain unsupported.

ASan/UBSan qualification passes:

- Two focused units check 7,888 exact fused-pattern lane results across both
  formats and all counts, including cancellation, overflow rescue, underflow
  ties, tiny midpoint perturbations, signed zeros and NaNs. Another 2,097,152
  exact `a*1+signed-zero` identity lane results cover every half encoding and
  deterministic float patterns. There are 9,792 three-source poison/undef/
  freeze checks, plus masking, snapshots, canonical overloads and shape/tag
  refusals. The cache regression checks all 544 identities without collisions.
- The final reference run (`bundle/reference-r3`) covers 800 decoded shapes:
  both formats, every count 1..16, five source forms and five constructions.
  All 403,594 native vector LLVM comparisons pass, including 393,216 sweeps
  placing every half encoding and deterministic float patterns in each of
  the three operand positions, plus all 8,192 directed corpus edge triples.
  Numeric state predictions and explicit freeze choices use a separate native
  scalar FMA oracle. Finite results and signed zeros compare bitwise; arithmetic
  NaNs compare by class while the VM must produce its preferred representation.
  Host CPU/features and both native projections remain in the bundle.
- There are 1,256 explicit freeze choices, 3,040 poison-store failures, 1,882
  strict undef failures, 819,544 scalar/integer API checks, 20,800 malformed
  metadata/source refusals and 1,600 short-budget refusals. Full output/guard
  bytes and derived bounds are checked with unaligned bindings. Another 144
  focused controls cover exact fused witnesses, all three sources, discards,
  freezes, snapshots, composition, repeated loops, unsupported profiles and
  duplicate declarations. Sixteen declaration-attribute refusals and eight
  exact memory/void storage/work boundaries pass before writes.
- Eight unit and eight reference regressions pass, including scalar and memory
  FMA, integer execution, memory operands, vector bitcasts, sign, rounding,
  sqrt, both min/max families and float-to-integer conversion. Existing
  standalone checkers and historical bundles are unchanged.
- Both Swift hash modes pass all 24 software Metal groups with two drained
  runtimes each. Each runtime exercises 102 new dispatches across 32 kernels:
  84 complete and 18 fail as expected. The 72 raw cases include corpus triples
  in both multiplicand orders and eight exact fused witnesses. Cases check
  deferred input writes, sparse bindings, pipeline reuse, poison/undef in
  every source, source/result freezes, discarded undef results, old snapshots
  and fneg/bitcast/comparison/select composition. Prior stores and all guard
  bytes match. A fast-math FMA call rejects at pipeline creation. All 56 fresh
  compute and 40 blit refusal logs pass.

The initial reference build rejected an ambiguous boolean expression in the
checker. The corrected checker passed every primary comparison but then
rejected its focused fixture for a missing data-layout declaration. The final
complete run passes after correcting that fixture. Failed source/build logs,
the complete partial run and the final run remain. No production change was
needed for these test setup failures. Sources were captured before new builds;
preparation helpers and their available failure logs remain too.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-fma-validation-20261115-r1.tar.gz`

The expanded original remains at the same path without `.tar.gz`. It retains
fixtures, results, binaries, generated host C/objects, compiler captures,
commands, helpers and feature-pinned `bundle/source.tar`. Maintained V tools
compare every logical archive payload, path, type, size, byte, mode, symlink
target and root mode with the original; before/after inventories and hashes
agree. Audit receipts are beside the archive under `.tar.gz.audit`, with the
typed inventory at `.tar.gz.inventory.txt`. No restored replay was performed.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.gz` | `983516e325de0f18352d5b2f788be2f9b7405af1ee4db3cdd4a1c93b42d33e0c` |
| `.tar.gz.inventory.txt` | `ac32dc124de2e8fc6650d5ddfbcca1dd8b0c0c39b070921f487038d13c753abd` |
| `bundle/source.tar`, revision `8b6052b344e14cd1acd943786944aeeb009e755c` | `21e95691ceee16ff64ebcbe1f565b8d623f78d4f8121a8e8ed4747aa4a0510d3` |

The standalone compiler was captured after builds; the host compiler before
generation. V libraries, SDKs, assembler, symlink targets and dylibs remain
external prerequisites. Native JIT code is uninstrumented. Leak detection is
disabled and retained heap was not measured. The ordinary runner was not
rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU rendering or
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Archive integrity does not replace historical launch auditors.
