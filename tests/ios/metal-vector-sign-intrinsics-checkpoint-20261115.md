# Software Metal vector sign intrinsics — 2026-11-15

`74a0343fcbe7ea13f1572388a77fc8f28a25f267` adds direct unflagged `llvm.fabs.vNf16`/`vNf32`
and `llvm.copysign.vNf16`/`vNf32` calls for fixed 1..16-lane AIR vectors.
Fabs clears the sign bit; copysign takes the second operand's sign bit.
Every other bit is preserved, including NaN payloads and signaling bits.
Neither operation quiets NaNs or uses host floating arithmetic.

Poison stays local to each lane. Any undef source lane rejects at the executed
call, including discarded results. Source freezes repair indeterminate lanes;
result freezes do not suppress earlier undef errors. Copysign validates and
evaluates both complete sources. Independent result snapshots compose with
existing bitcasts, arithmetic, comparisons, selects, shuffles and extraction.
Dynamic failures preserve prior stores.

Each call costs one executed step. Fabs charges two lane counts and copysign
three to shared lane work. Calls reuse the existing 4,096 construction slots
and execution-owned array. A separate fixed 64-entry declaration cache covers
both operations, formats and every lane count; scalar cache identities stay
unchanged. Canonical names, exact signatures, direct declaration identity,
arity, calling convention, call flags and source construction order are checked.
Harmless declaration attributes use the existing bounded scanner once per
overload; duplicate reserved declarations reject.

Mixed scalar, void and memory APIs admit these calls. The integer-only API
rejects floating lanes, including constant calls with integer results and no
floating arguments. Fast-math flags, tail calls, call-site attributes,
unsupported declaration attributes, other vector intrinsics/formats, vector
arguments/returns, PHIs and loads/stores remain unsupported.

ASan/UBSan qualification passes:

- 4,194,304 independent raw-bit checks cover every half encoding and
  deterministic float patterns across all 16 lanes and both operations,
  including source masking, NaN payloads/signaling bits and immutable inputs.
  Another 13,056 lane-state checks cover both sources, all lane counts,
  localized poison, strict undef, freezes and tag/shape guards. All 64
  canonical overload names and unique cache keys are checked.
- 1,600 decoded shapes cover both formats/operations, every lane count,
  five source forms and five constructions. All 266,516 native LLVM values
  match exactly, including 262,144 exhaustive half/deterministic float sweep
  samples. There are 2,512 explicit freeze choices, 6,080 poison-store
  failures, 3,764 strict undef failures and 557,744 scalar/integer API checks.
  Every output and guard byte is checked with unaligned bindings and derived
  bounds. Defined comparison rows and the native projection are retained.
- 34,400 malformed-call/source mutations and 3,200 short budgets reject
  before writes. Another 200 focused controls cover both source states,
  discards, isolation, freezes, old snapshots, raw bitcasts, comparisons,
  selects, loop slot reuse, API isolation, unsupported profiles, declaration
  mutations and duplicate declarations in both memory and scalar profiles.
  Canonical declaration attributes are accepted, while 16 retained-group
  mutations reject strictfp, return, parameter and string attributes before
  writes. Eight public memory/void boundaries admit exactly 4,096 results
  and 1,000,000 lane-work units; exceeding either rejects before writes.
- Seven unit and seven reference regressions pass for scalar floating/integer
  intrinsics, scalar execution, memory operands/attributes, overflow pairs,
  memmove, saturation, vector bitcasts/fneg and the previous float-to-integer
  vector conversions. Existing checkers were unchanged.
- Both Swift hash modes pass all 24 software Metal groups with two drained
  runtimes each. Each runtime exercises 164 new dispatches across 40 kernels:
  152 complete and 12 fail as expected. Cases cover both signs and source
  formats, NaN payloads, deferred input writes, sparse bindings, pipeline reuse,
  two-source poison/undef, source/result freezes, snapshots and fneg/raw-bitcast/
  comparison/select composition. Strict undef failures preserve only the
  marker; poison failures also preserve a frozen-zero store. A fast-math
  vector intrinsic rejects during pipeline creation.

Native execution is limited to defined selections. Explicit indeterminate
freeze choices are checked separately; NaN results compare as raw bits without
normalization. LLVM verifies the input modules. The native projection retains
only comparison kernels and their intrinsic declarations, using the host target.

Initial build logs remain. The first comparison run and its diagnostic retry
exposed an expected-sign error for a zero-initialized sign vector; both complete
attempts remain. A passing primary-only run is retained too. A later guard
expected strictfp to survive LLVM assembly, but LLVM canonicalized it away.
That failure and its disassembled module remain. Final tests admit the canonical
baseline, then mutate retained attribute groups directly; all guards pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-sign-intrinsics-validation-20261115-r1.tar.gz`

The canonical expanded workspace at the same path without `.tar.gz` remains.
It retains fixtures/results, failure evidence, binaries, generated host C and
objects, compiler captures, commands, helpers and `bundle/source.tar` pinned to
the feature revision. `tests/packages/wine-workspace-archive.v` seals it using
`tests/ios/swift-staging-archive.v check-archive-root`. Every logical archive
payload, path, type, size, byte, mode, symlink target and root mode matches the
original; complete before/after inventories and tool/archive hashes agree.
No restored replay was performed. Original trees remain. Audit receipts are
beside the archive under `.tar.gz.audit`; the typed inventory is
`.tar.gz.inventory.txt`.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.gz` | `7f7fa73ed2c86c335761e557f27908f13fe2cf52e11c47ed389553068cd3540f` |
| `.tar.gz.inventory.txt` | `9d859b9799f2483dfa23fd723dd48696bafdd13df30b336bc009838afb7a8c4d` |
| `bundle/source.tar`, revision `74a0343fcbe7ea13f1572388a77fc8f28a25f267` | `fa75e8d9e9bdbb41eb6f3d7484693b8c4248720aac11f58c88e12420a4941263` |

The standalone compiler was captured after builds; the host compiler was
captured before generation. V libraries, SDKs, assembler, symlink targets and
dylibs remain external prerequisites. Native JIT code is uninstrumented. Leak
detection is disabled and retained heap was not measured. The ordinary runner
was not rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU
rendering/presentation, Vinix guest, Fortnite frame or launch gate is newly
verified. Archive integrity does not replace historical launch auditors.
