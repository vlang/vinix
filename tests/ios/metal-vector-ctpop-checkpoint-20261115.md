# Software Metal vector population count — 2026-11-15

`034b81bf48e487f510c76c68d5153fa389cce37c` adds ordinary direct `llvm.ctpop.vNiW` calls for fixed vectors
of 1..16 integer lanes, widths i1..i64, returning the identical vector type.
Each lane counts set bits under the [LLVM population-count contract](https://llvm.org/docs/LangRef.html#llvm-ctpop-intrinsic).
The existing scalar integer counter masks the declared width and scans at most
64 bits without host floating point or a new allocation on the lane path.
Poison propagates per lane; any undef lane fails even for discarded results.
Source freezes repair indeterminate input, result freezes choose zero for
poison, and results are independent snapshots that compose with supported
integer vector operations.

The common direct-call validator checks canonical names, signature/arity,
argument/result identity, actual integer width/count, declaration identity,
calling convention, flags and attributes, including calls in cold blocks.
Mixed scalar, integer-only, void and memory APIs admit these calls. Floating
producers still require mixed execution; scalar intrinsic calls keep their
existing policy. Vector arguments/returns, PHIs, vector loads/stores, scalable
vectors, widths above 64, counts above 16, AIR aliases, tail calls and flagged
calls remain outside the supported profile. Parameter/return attributes,
including `immarg`, reject. The declaration cache adds 1,024 independent
width/count entries after the existing 640 floating identities: 1,664 stack
entries total. A call consumes one step, two lane counts of profiling work and
one shared vector construction slot. The 4,096-result, 1,000,000-vector-work
and 1,000,000-attribute-work limits are unchanged.

ASan/UBSan macOS ARM64 qualification passes:

- The new unit checks **1,032,736 exact lane values** using an independent
  low-set-bit-clearing oracle. It exhausts i1..i16, checks wide patterns and
  single-set/clear bits, masking and immutable snapshots. Another 104,448
  lane poison/undef/freeze checks and the shared cache unit cover all 1,664
  identities.
- `bundle/reference-r5` checks **25,600 decoded shapes**, every width/count,
  five input forms and five construction paths. Its 70,592 composed native
  LLVM values are exact. It checks 40,192 fixed freeze choices, 97,792 poison
  store failures, 60,224 strict undef failures, 537,600 mixed/integer API cases,
  614,400 malformed metadata/source refusals and 76,800 short-budget refusals.
  Exact steps, complete output bytes, unaligned binding offsets and derived
  buffer extents are checked.
- Sixteen bounded bulk modules add **3,276,832 exact native lane values**:
  every narrow encoding (small-width final packets repeat values) and 65,536
  deterministic patterns for each i17..i64 width. Matrix plus bulk gives
  **3,347,424 exact native comparisons**. VM inputs carry upper-bit noise;
  native loads receive canonical padding. Every result also agrees with the
  independent width-masked oracle.
- Another 286 controls check state/freeze/discard behavior, snapshots, chains,
  unsupported profiles, signature spoofing with a valid baseline, duplicate
  identities, changing-source loops and floating/integer API isolation.
  Eight bounded modules exercise all 1,024 declarations through both scalar
  APIs, summing independently to 33,280. The single combined 1,024-declaration
  module must reject the shared attribute-work bound through both APIs.
  Canonical declaration attributes admit; 48 immarg transfers to unary
  integer calls reject before writes. Sixteen exact shared work/storage
  boundary checks pass through memory, void, mixed scalar and integer APIs;
  over-limit profiles reject before writes.
- Fourteen existing unit and fifteen reference regressions pass, including
  integer execution/vector binary operations, scalar integer intrinsics,
  memory operands, bitcasts, float/integer conversions, sign/rounding/sqrt/
  extrema, vector/scalar/memory FMA and scaling, optional fusion, and scalar/
  vector classification. Historical checkers are unchanged.
- Both Swift hash modes pass all 24 software Metal groups, with two drained
  runtimes each. Each runtime adds **216 dispatches across 64 kernels**:
  192 complete and 24 fail as expected. Eight representative widths include
  i1, i3, i31, i48 and i64. Tests check deferred writes, sparse bindings,
  pipeline reuse, poison/undef/discards, source/result freezes, old snapshots,
  composed calls and guard words. Tail-call and i65 pipelines reject.
  All 56 compute and 40 blit refusal logs pass.

The initial reference run observes the captured LLVM native lowering return
255 after an i1 vector load from byte 255, while the interpreter and independent
oracle produce 1. The final checker keeps noisy padding for the VM and clears
unused bits before native loads; it does not qualify native padding behavior.
The second run completes the matrix/bulk and state controls, then reaches the
existing attribute-work limit in the combined 1,024-declaration function.
The final checker tests that refusal explicitly and uses bounded cache groups
for successful execution. An accidentally launched superseded third run was
terminated and retained. The fourth run passes all value/state/cache/attribute
checks, then reaches the parser record limit in a combined boundary module.
The fifth separates boundary fixtures by API and passes the complete suite.
Production needed no
correction for these fixture/reference issues. All attempted sources, binaries,
partial/full results and statuses remain in the bundle.

Complete retained bundle:

`/Users/alex/Library/Caches/vinix-ios/air-vector-ctpop-validation-20261115-r1`

The adjacent `.tar.gz` contains the complete bundle, including failed attempts,
fixtures/results, binaries, generated host C/objects, compiler captures,
commands, helpers and feature-pinned `bundle/source.tar`. The V archiver checks
complete typed inventories before/after compression; the maintained archive
checker compares every logical payload, path, size, type, mode and link,
including the root mode. A fresh extraction under `.restored-r1/tree/` passes
that full comparison. The restored sanitized population-count checker passes
its complete reference suite again, writing outside the restored tree, followed
by another complete archive comparison. Original and restored evidence remain.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.gz` | `eeeabc550a374506f88b3aab9ade885145b99b495f0b1637b6f29b25d9ce9c83` |
| `.tar.gz.inventory.txt` | `0757619265e0fccb029e868540aa85c9fc4759327858732c8288e53c400519eb` |
| `bundle/source.tar`, revision `034b81bf48e487f510c76c68d5153fa389cce37c` | `7d649084d35a03e5b8258d1fb832a6e6d747d30e9727b3a483f4f7b2098178cf` |

Archive commands/log/status are adjacent at `.archive-command.txt`,
`.archive-driver.log` and `.archive-status.txt`; audit receipts are under
`.tar.gz.audit/`. Extraction/comparison/replay commands/logs/status are under
`.restored-r1/`, with `finished.status.txt` zero.

Primary sources were captured before builds, the standalone compiler afterward,
and the host compiler before generation. V libraries, SDKs, assembler, symlink
targets and dylibs remain external prerequisites. Native JIT is uninstrumented.
Leak detection is disabled and retained heap unmeasured. The ordinary runner
was not rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU
rendering/presentation, Vinix guest, Fortnite frame or launch gate is newly
verified. Archive integrity does not replace historical launch auditors or
permit retiring their original evidence.
