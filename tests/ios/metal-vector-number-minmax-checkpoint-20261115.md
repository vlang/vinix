# Software Metal number-preferring vector extrema — 2026-11-15

`931a9233e897f0605e885aa6a6589c262c3cb52e` adds unflagged `llvm.minimumnum.vNf16`/`vNf32`,
`llvm.maximumnum.vNf16`/`vNf32` and legacy `llvm.minnum`/`llvm.maxnum`
overloads for fixed 1..16-lane AIR vectors. The existing scalar evaluator
selects the numeric operand when exactly one operand is NaN, including a
signaling NaN. Two NaNs produce the preferred positive quiet NaN. For two
zeros, minimum selects negative zero when present and maximum selects positive
zero when present. Both inputs are masked to the declared width. VM evaluation
uses integer operations.

Legacy calls use the deterministic number-preferring refinement permitted by
[LLVM's minnum/maxnum contract](https://llvm.org/docs/LangRef.html#llvm-minnum-intrinsic).
The LLVM checker executes the modern names directly. For legacy calls, its
native reference clone substitutes the corresponding modern intrinsic. The
original legacy native kernels execute separately and their raw outputs are
retained as diagnostics. This qualification does not claim exact agreement
with every raw native legacy result.

Both complete sources are validated and evaluated. Poison stays local to a
lane; any undef source lane rejects at the executed call, including discarded
results. Source freezes repair indeterminate lanes; result freezes cannot
suppress earlier undef failures. Dynamic errors preserve prior stores.
Snapshots compose with bitcasts, fneg, comparisons, selects and shuffles.
Existing signature, declaration, arity, calling-convention, flags and attribute
checks apply. The declaration cache expands from 384 to 512 entries while
preserving every earlier key. The 128 new keys are distinct. Shared storage,
step and lane-work limits remain in effect. Vector arguments/returns, PHIs,
loads/stores, scalable or wider vectors, double/bfloat, fast-math flags, tail
calls, strict FP and FP exceptions remain outside the admitted profile.

ASan/UBSan qualification passes:

- The extended min/max unit checks all six operations with 12,582,912 exact
  ordered-key comparisons across every half encoding and deterministic float
  patterns, plus 3,072 directed edge pairs and 39,168 two-source lane-state
  checks. Masking, commutativity and immutable sources pass. The cache unit
  checks all 512 float intrinsic identities without collisions.
- Four decoded operation batches cover 3,200 shapes: both formats, every
  count 1..16, five source forms and five constructions. All 535,080 LLVM
  refinement comparisons pass, including 524,288 exhaustive half/deterministic
  float sweep samples and 2,048 directed edge pairs. Finite values and signed
  zeros compare bitwise. Native arithmetic NaNs compare by class; the VM must
  return its preferred quiet NaN. An independent host-double oracle checks VM
  results. The projected native bitcode remains in each batch.
- The original legacy kernels produce 267,540 diagnostic values. There are
  18,096 raw differences from the chosen refinement: 16,762 native NaN versus
  numeric results and 1,334 NaN-representation differences. There are zero
  signed-zero or other differences. These diagnostics remain separate from
  the canonical refinement comparisons.
- There are 5,024 explicit freeze choices, 12,160 poison-store failures, 7,528
  strict undef failures, 1,119,584 scalar/integer API checks, 73,600 malformed
  metadata/source refusals and 6,400 short-budget refusals. All output/guard
  bytes are checked with unaligned bindings and derived bounds. Another 396
  focused controls cover both sources, discards, freezes, isolation, snapshots,
  composition, loops, unsupported profiles, declaration mutations and duplicate
  identities. Sixteen declaration attribute mutations and eight exact shared
  storage/lane-work boundary checks pass before writes.
- Seven unit and five reference regressions pass for scalar execution,
  integer execution, memory operands, vector bitcasts, sign, rounding, sqrt,
  propagating min/max and float-to-integer conversions. Existing standalone
  reference checkers are unchanged. Historical bundles remain unchanged.
- Both Swift hash modes pass all 24 software Metal groups with two drained
  runtimes each. Each runtime exercises 328 new dispatches across 80 kernels:
  296 complete and 32 fail as expected. Cases cover deferred input writes,
  sparse bindings, pipeline reuse, both-source poison/undef, freezes, old
  snapshots and fneg/raw-bitcast/comparison/select composition. Strict undef
  failures preserve the marker; poison failures also preserve a frozen-zero
  store. A fast-math number-preferring call rejects at pipeline creation.
  All 56 fresh-process compute and 40 blit refusal logs pass.

No unit, reference or host test failed. External preparation helpers had
compiler errors; their logs remain with the corrected helpers. New unit,
reference and runtime fixture sources were saved before their builds. LLVM
verifies the generated reference modules. Indeterminate freeze choices are
checked separately from native execution.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-number-minmax-validation-20261115-r1.tar.gz`

The expanded workspace at the same path without `.tar.gz` remains. It retains
results, raw diagnostics, fixtures, binaries, generated host C and objects,
compiler captures, commands, helpers and feature-pinned `bundle/source.tar`.
Maintained V tools compare every logical archive payload, path, type, size,
byte, mode, symlink target and root mode with the original. Complete
before/after inventories and archive/tool hashes agree. No restored replay
was performed. Audit receipts are beside the archive under `.tar.gz.audit`;
the typed inventory is `.tar.gz.inventory.txt`.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.gz` | `17415f6ac3e1b89b17acf0437449a122d812571a3226d870441b4cd1bbbc3bff` |
| `.tar.gz.inventory.txt` | `532552f6be1fa2c30c6c6e02614d5de3ae81035ea8401945312bb6e9df49cb8b` |
| `bundle/source.tar`, revision `931a9233e897f0605e885aa6a6589c262c3cb52e` | `76c064dc55dc08516e7edd2efd0a3d4dc7b94057c3ac539d288c19f1fbf69456` |

The standalone compiler was captured after builds; the host compiler before
generation. V libraries, SDKs, assembler, symlink targets and dylibs remain
external prerequisites. Native JIT code is uninstrumented. Leak detection is
disabled and retained heap was not measured. The ordinary runner was not
rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU rendering or
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Archive integrity does not replace historical launch auditors.
