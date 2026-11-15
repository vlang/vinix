# Software Metal vector power-of-two scaling — 2026-11-15

`084ca3e88b17323db517f1a37f4851f95ffe1845` adds unflagged `llvm.ldexp.vNf16.vNi32` and
`llvm.ldexp.vNf32.vNi32` for fixed 1..16-lane AIR vectors. Floating inputs use
matching i32 exponent vectors, following [LLVM's scaling signature](https://llvm.org/docs/LangRef.html#llvm-ldexp-intrinsic).
The existing scalar integer evaluator supplies nearest/ties-to-even results,
gradual underflow, signed zeros/infinities and preferred positive quiet NaNs.
Both inputs are masked to their declared width; INT_MIN/MAX have bounded
handling. There is no host floating point or allocation in the lane evaluator.

Admission checks actual heterogeneous declaration/source types independently
of canonical overload names, direct identity, calling convention, flags and
attributes. Either source's poison propagates locally; any undef source lane
rejects at the executed call, including discarded results. Source freezes
repair indeterminate lanes; result freezes retain prior undef errors. Results
are independent snapshots and failures preserve earlier stores. Each call
costs one step, three lane counts and one shared construction slot. The existing
4,096-slot and 1,000,000-work limits remain. Thirty-two identities follow the
previous 576, giving 608 cache entries. Mixed scalar, void and memory APIs admit
the calls; the integer-only API rejects floating lanes. Vector arguments,
returns, PHIs, loads/stores, scalable/wider vectors, other precisions/exponent
widths, AIR aliases, fast-math, tail calls and strict FP remain unsupported.

ASan/UBSan qualification passes:

- `bundle/reference-r3` checks 800 decoded shapes across both formats, every
  count 1..16, five source forms and five constructions. All 2,099,850 value
  comparisons pass, including 2,097,152 sweep samples covering every half
  encoding and deterministic float patterns against sixteen signed exponent
  boundaries, plus 512 directed corpus pairs. A separate binary64 scaling
  oracle checks exact values and explicit freeze choices. Half quantization
  uses exact representable-value midpoints with ties to even. Finite values
  and signed zeros compare bitwise; native NaNs compare by class while the VM
  must return its preferred representation.
- There are 1,256 fixed-zero choices, 3,040 poison-store failures, 1,882 strict
  undef failures, 4,212,056 scalar/integer API checks, 18,400 malformed
  metadata/source refusals and 1,600 short-budget refusals. Full output/guard
  bytes, unaligned bindings and derived bounds are checked. Another 136
  controls cover both sources, freezes/discards, snapshots, composition,
  changing integer exponents in cached loops, malformed signatures, unsupported
  profiles and duplicate declarations. Sixteen declaration-attribute refusals
  and eight exact memory/void storage/work boundaries pass; invalid profiles
  reject before writes.
- Focused units check 6,528 exact scaling/tie/subnormal/special/masking lane
  results, 2,097,152 zero-exponent identity results, 6,528 two-source state
  checks and all 32 canonical overloads. Eleven existing unit and eleven
  reference regressions pass, including vector/scalar/memory FMA, optional
  fusion, scalar/memory scaling, integer execution, memory operands, vector
  bitcasts, sign, rounding, sqrt, extrema and conversions. The shared cache
  unit covers all 608 identities.
- Both Swift hash modes pass all 24 software Metal groups with two drained
  runtimes each. Each runtime exercises 94 new dispatches across 24 kernels:
  82 complete and 12 fail as expected. Cases cover corpus/exponent pairs,
  rounding ties, normalization, overflow, extreme exponents, deferred input
  writes, sparse bindings, pipeline reuse, both sources' poison/undef,
  discarded undef results, freezes, old snapshots and composition. Fast-math
  and i64 exponent calls reject at pipeline creation. All 56 compute and 40
  blit refusal logs pass.

The first reference attempt exits 138 in LLVM native compilation, before
comparisons. Its macOS crash report identifies SelectionDAG vector
legalization. A minimal one-lane half `ldexp` reproduces an `llc` failure
(exit 11), while scalar half and 2/3/5/7/9/16-lane probes compile. The final
native projection extracts/calls scalar/reinserts for N=1 in both precisions;
N=2..16 retain direct vector calls. Vinix always executes the original vector
IR. This qualifies one-lane semantics against scalar LLVM, not native one-lane
vector code generation. Original/projected IR, target/features, reproducer
sources, commands, logs and crash report are retained. An intermediate reference
build failed on an accidentally retained native-builder variable in a control
fixture; the corrected fresh complete run passes. No production correction was
needed for either reference setup issue. Sources were captured before builds.

Complete retained bundle:

`/Users/alex/Library/Caches/vinix-ios/air-vector-ldexp-validation-20261115-r1`

The adjacent `.tar.gz` contains the complete bundle, including failed attempts,
probes, fixtures, outputs, binaries, generated host C/objects, compiler captures,
commands, helpers and feature-pinned `bundle/source.tar`. The V workspace
archiver compares complete original typed inventories before/after compression;
the maintained archive checker decodes every logical archived payload and
compares all paths, bytes, sizes, modes, link targets and root mode. A fresh
extraction under `.restored-r1/tree/` passes that same complete comparison.
The restored sanitized `ldexp` checker then passes its full reference suite
again, writing outside the restored tree, followed by another full archive
comparison. Both original and restored evidence remain. This does not retire
or replace any historical evidence.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.gz` | `c137ec93e24ed69dc6315d93bd5c4a3021f957a99fe5cdd5b8b4aa6258590d7e` |
| `.tar.gz.inventory.txt` | `21eedad6dfe1801e2f8814b3c1a8a9558f4e66fb7957d40188e03764c6ef54bd` |
| `bundle/source.tar`, revision `084ca3e88b17323db517f1a37f4851f95ffe1845` | `21cd75356040a3080f01c9cb63643e31d3d32733a6a4ff35086e57ed2465fe73` |

Archive commands/log/status are adjacent at `.archive-command.txt`,
`.archive-driver.log` and `.archive-status.txt`; archive audit receipts are
under `.tar.gz.audit/`. Extraction, comparison and replay commands/logs/status
are under `.restored-r1/`, with `finished.status.txt` equal to zero.

The standalone compiler was captured after builds and the host compiler before
generation. V libraries, SDKs, assembler, symlink targets and dylibs remain
external prerequisites. Native JIT code is uninstrumented. Leak detection is
disabled and retained heap was not measured. The ordinary runner was not
rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU rendering or
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Archive integrity does not replace historical launch auditors.
