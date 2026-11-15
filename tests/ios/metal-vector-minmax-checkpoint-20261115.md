# Software Metal vector minimum and maximum — 2026-11-15

`dc5849bf07a7b2bba6041976d08f35099076a2a7` adds direct unflagged `llvm.minimum.vNf16`/`vNf32` and
`llvm.maximum.vNf16`/`vNf32` calls for fixed 1..16-lane AIR vectors. Each lane
uses the existing scalar evaluator after masking both inputs to their declared
width. For two zero inputs, minimum selects negative zero when present and
maximum selects positive zero when present. A NaN in either input produces the
preferred positive quiet NaN. Number-preferring vector intrinsics remain
unsupported. VM evaluation uses integer operations rather than host FP.

Both complete sources are validated and evaluated. Poison remains local to
each lane. Any undef source lane rejects at the executed call, including
discarded results and calls with a NaN in the other input. Source freezes
repair indeterminate lanes; result freezes do not suppress earlier undef
errors. Dynamic errors preserve prior stores. Independent result snapshots
compose with bitcasts, fneg, comparisons, selects, shuffles and extraction.

Shared validation checks canonical names, exact signatures, arity, direct
declaration identity, calling convention, call flags, source order and
declaration attributes. The vector declaration cache has 384 entries; the
previous 320 keys are unchanged and 64 min/max keys follow them. Duplicate
reserved declarations reject. Each call costs three lane counts, one executed
step and one of the existing 4,096 vector result slots. Shared lane work stays
bounded at 1,000,000. Mixed scalar, void and memory APIs admit these calls;
the integer-only API rejects floating lanes even for constant vectors with
integer results. Vector arguments/returns, PHIs and loads/stores, scalable or
wider vectors, double/bfloat, fast-math flags, tail calls, call-site attributes,
strict FP and FP exceptions remain outside the admitted profile.

ASan/UBSan qualification passes:

- 4,194,304 independent ordered-key comparisons cover every half encoding and
  deterministic float patterns across both operations and all 16 lanes.
  Another 1,024 edge pairs check commutativity, signed zeros, infinities,
  subnormals and NaN propagation. Masking and immutable source snapshots pass.
  There are 13,056 two-source poison/undef/freeze checks, all 64 new overload
  identities, and malformed name/shape/family/tag refusals. The rounding cache
  regression verifies all 384 identities without collisions.
- 1,600 decoded shapes cover both formats and operations, every count 1..16,
  five source forms and five constructions. All 267,540 native LLVM
  comparisons pass: 262,144 exhaustive half/deterministic float sweep samples,
  1,024 directed edge pairs and the remaining constructed cases. The directed
  pairs include both argument orders of positive/negative zero, infinity,
  subnormal and NaN patterns. Finite results and signed zeros compare bitwise;
  arithmetic NaNs compare by class while the VM must produce its preferred
  quiet NaN. A host-double oracle independently checks VM results.
- There are 2,512 explicit freeze choices, 6,080 poison-store failures,
  3,764 strict undef failures, 559,792 scalar/integer API checks, 36,800
  malformed-call/source refusals and 3,200 short-budget refusals. All output
  and guard bytes are checked with unaligned bindings and derived bounds.
  Another 200 controls cover both sources, discards, freezes, isolation,
  snapshots, composition, repeated loops, API isolation, unsupported profiles,
  declaration mutations and duplicate identities. Sixteen retained declaration
  attribute mutations reject before writes. Eight memory/void boundaries
  check exact shared storage and lane-work admission/refusal before stores.
- Seven unit and four reference regressions pass for sqrt, sign, rounding,
  scalar execution, memory operands, vector bitcasts and float-to-integer
  conversions. The standalone reference checkers are unchanged; the rounding
  cache unit expands its identity set. Historical bundles remain unchanged.
- Both Swift hash modes pass all 24 software Metal groups with two drained
  runtimes each. Each runtime exercises 164 new dispatches across 40 kernels:
  148 complete and 16 fail as expected. Cases cover signed inputs, NaNs,
  deferred input writes, sparse bindings, pipeline reuse, both-source
  poison/undef, source/result freezes, old snapshots and fneg/raw-bitcast/
  comparison/select composition. Strict undef failures preserve the marker;
  poison failures also preserve a frozen-zero store. A fast-math min/max call
  rejects at pipeline creation.

The original normal host run passed, while the deterministic run failed an
existing fork/wait encoding guard before the new kernels. The old guard closed
its output streams, so its child diagnostic was unavailable. This does not
establish a specific child failure cause. The full failed attempt remains.
Fourteen compute encoding/extent guards now execute in fresh processes and
require their exact runtime diagnostic and exit status; all 56 checks pass
across both hash modes and runtimes. The existing blit guard workflow is
unchanged. Other legacy fork guards remain.

The first unit build exposed a local variable name collision; its exact source
and compiler log remain. The corrected unit passes. Passing initial and tidied
reference attempts remain too; the final checker adds directed native edge
pairs. Every new source was saved before its build. LLVM verifies the input
modules. The native projection retains comparison kernels and intrinsic
declarations and uses the host target. Indeterminate freezes are checked
separately from native execution; a source frozen to zero can subsequently
select a defined value from the other operand.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-minmax-validation-20261115-r1.tar.gz`

The expanded workspace at the same path without `.tar.gz` remains. It retains
results, fixtures, binaries, generated host C and objects, compiler captures,
commands, helpers and feature-pinned `bundle/source.tar`. Maintained V tools
compare every logical archive payload, path, type, size, byte, mode, symlink
target and root mode with the original. Complete before/after inventories and
archive/tool hashes agree. No restored replay was performed. Audit receipts
are beside the archive under `.tar.gz.audit`; the typed inventory is
`.tar.gz.inventory.txt`.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.gz` | `76ba318f90c825dc47a81cd338b9bace979f9f57314d6401e9a69a1b51296f27` |
| `.tar.gz.inventory.txt` | `afb65ca03263f4714a1285e6c046112a1ee1a8abd88181b2a0290e4af6480b3d` |
| `bundle/source.tar`, revision `dc5849bf07a7b2bba6041976d08f35099076a2a7` | `ec386e81828347b00cb3f490e7b76e006df3cb092c3fa39e16bd57c40281ca9b` |

The standalone compiler was captured after builds; the host compiler before
generation. V libraries, SDKs, assembler, symlink targets and dylibs remain
external prerequisites. Native JIT code is uninstrumented. Leak detection is
disabled and retained heap was not measured. The ordinary runner was not
rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU rendering or
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Archive integrity does not replace historical launch auditors.
