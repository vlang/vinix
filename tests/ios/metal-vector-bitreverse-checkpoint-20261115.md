# Software Metal vector bit reversal — 2026-11-15

`d0eb3172790672883a158917e1a6e59ffc431b18` adds ordinary direct `llvm.bitreverse.vNiW` calls for fixed
vectors of 1..16 integer lanes, widths i1..i64. Bit M moves to bit W-M-1
within each lane; element order and vector type remain unchanged, following
[LLVM's bit-reversal contract](https://llvm.org/docs/LangRef.html#llvm-bitreverse-intrinsics).
Production reuses the existing scalar integer shift loop, masks each input
width and adds no allocation on the normal lane path. Population count and
reversal now share integer-overload parsing, type/source validation and lane
execution. The population-count wrapper remains for its focused unit.

Admission checks canonical names, argument/result identity, exact width/count,
direct declarations, signature/arity, flags, calling convention and attributes,
including cold blocks. Both integer-only and mixed execution admit these
integer calls; floating producers still require mixed execution. Poison
propagates per lane, any undef lane fails even if discarded, source freezes
repair inputs and result freezes choose zero for poison. Results are independent
snapshots. Parameter/return attributes, including `immarg`, reject. Vector
arguments/returns, PHIs, vector loads/stores, scalable vectors, i65 and wider
lanes, counts above 16, AIR aliases, tail and flagged calls remain outside the
supported profile.

Reversal adds 1,024 cache identities at slots 1664..2687; all older 1,664 stay
at their previous slots. The shared stack cache has 2,688 entries. Each call
consumes one step, two lane counts of profiling work and one shared construction
slot. The 4,096-result, 1,000,000-vector-work and 1,000,000-attribute-work limits
remain unchanged.

ASan/UBSan macOS ARM64 qualification passes:

- Focused reversal units check **1,032,736 exact lane values**, independently
  using the standard-library 64-bit reverser shifted to the declared width,
  plus **705,024 involutions** and 104,448 lane poison/undef/freeze checks.
  Cases exhaust i1..i16, include 4,096 wide patterns and single-set/clear bits,
  high-bit noise, snapshots and guards. The shared cache unit covers all 2,688
  identities. The population-count unit's former unsupported-reversal name is
  replaced by unsupported byte swap because reversal is now admitted; its
  positive values and state checks stay unchanged.
- `bundle/reference-r2` checks **25,600 decoded shapes**, all widths/counts,
  five source forms and five constructions. It checks 70,592 exact composed
  native LLVM values, 40,192 fixed freeze choices, 97,792 poison-store failures,
  60,224 strict undef failures, 537,600 mixed/integer API cases, 614,400 malformed
  metadata/source refusals and 76,800 short-budget refusals. Exact steps, whole
  output bytes, unaligned bindings and derived buffer extents are checked.
- Sixteen bounded bulk modules add **3,276,832 exact native lane values**:
  every narrow encoding (small-width final packets repeat values) and 65,536
  deterministic patterns per i17..i64 width. Matrix plus bulk gives
  **3,347,424 exact LLVM comparisons**. VM inputs retain noisy upper bits;
  native loads receive canonical padding, following the prior population-count
  qualification. Both results agree with the independent reversal oracle;
  native padding behavior is not qualified.
- Another **606 controls** cover state/freeze/discards, snapshots, chains,
  unsupported profiles, signatures with a valid baseline, duplicates,
  changing-source loops and floating/integer API isolation. Of these, 320
  cross-family API cases check that reversal twice restores the input and
  reversal preserves population count, with both call orders and both scalar
  APIs. Eight bounded modules exercise all 1,024 new identities through both
  APIs; their all-one results sum modulo 2^64 to 18,446,744,073,709,550,560.
  The combined 1,024-declaration module rejects the shared attribute-work bound.
  Canonical attributes admit; 48 immarg transfers reject before writes.
  Sixteen exact shared storage/work boundary checks pass through memory, void,
  mixed scalar and integer APIs, with over-limit refusals before writes.
- Fifteen existing units and sixteen reference regressions pass, including
  vector population count, scalar integer intrinsics, integer/vector binary
  execution, memory operands, bitcasts, conversions, sign/rounding/sqrt/extrema,
  vector/scalar/memory FMA and scaling, optional fusion and classification.
  Historical reference checkers remain unchanged.
- Both Swift hash modes pass all 24 software Metal groups with two drained
  runtimes each. Each runtime adds **216 dispatches across 64 kernels**:
  192 complete and 24 fail as expected. Eight representative widths include
  i1, i3, i31, i48 and i64. Tests check high-bit noise, deferred writes, sparse
  bindings, pipeline reuse, poison/undef/discards, source/result freezes, old
  snapshots, nontrivial double reversal with integer comparison/select and
  guard words. Tail-call and i65 pipelines reject. All 56 compute and 40 blit
  refusal logs pass.

The first full reference run passes. The second changes the bulk TSV column
label from the inherited `count` to `reversed` and passes the complete suite
again. Both sources, binaries and complete results are retained. Production
needed no correction during reference qualification.

Complete retained bundle:

`/Users/alex/Library/Caches/vinix-ios/air-vector-bitreverse-validation-20261115-r1`

The adjacent `.tar.gz` preserves the complete bundle: fixtures/results,
binaries, generated host C/objects, compiler captures, commands, helpers and
feature-pinned `bundle/source.tar`. The V archiver compares complete typed
inventories before/after compression. The maintained archive checker compares
every logical payload, path, size, type, mode and link, including the root mode.
A fresh extraction under `.restored-r1/tree/` passes that comparison. The
restored sanitized reversal checker passes its entire suite again, writing
outside the restored tree, followed by another complete archive comparison.
Original and restored evidence remain intact.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.gz` | `b944fd690eb50d8e881bb8fc91666d4c82504a070725bc041f3653ddacd56bd0` |
| `.tar.gz.inventory.txt` | `daa7d87a562e1efe1839a4154bd0e872043eaf78afca4bbf1d3b646971d0509f` |
| `bundle/source.tar`, revision `d0eb3172790672883a158917e1a6e59ffc431b18` | `55d2a87564d0d8bed1ee3bd1f44471cd084e437735a44d14bb4771502fc91686` |

Archive commands/log/status are adjacent at `.archive-command.txt`,
`.archive-driver.log` and `.archive-status.txt`; audit receipts are under
`.tar.gz.audit/`. Extraction/comparison/replay commands/logs/status are under
`.restored-r1/`, with `finished.status.txt` zero.

Primary sources were captured before builds, the standalone compiler afterward,
and the host compiler before generation. V libraries, SDKs, assembler, symlink
targets and dylibs remain external prerequisites. Native JIT is uninstrumented.
Leak detection is disabled; retained heap was not measured. The ordinary runner
was not rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU
rendering/presentation, Vinix guest, Fortnite frame or launch gate is newly
verified. Archive integrity does not replace historical launch auditors or
permit retiring their original evidence.
