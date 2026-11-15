# Software Metal vector byte swap — 2026-11-15

`6a4330c5f8d1063bea7ad13811bc8d2d41acec2e` adds ordinary direct `llvm.bswap.vNiW` calls for fixed vectors
of 1..16 lanes at i16, i32, i48 and i64. Each lane reverses its bytes without
changing bit order within a byte or lane order. These are the even-byte widths
in the interpreter's integer range, following [LLVM's byte-swap contract](https://llvm.org/docs/LangRef.html#llvm-bswap-intrinsics).
Production reuses the scalar byte-swap loop and the shared integer-vector
parser/profile/executor. The normal lane path adds no allocation.

Canonical names, exact argument/result type, width/count, direct declarations,
signature/arity, flags, calling convention and attributes are checked before
execution, including cold blocks. Both scalar APIs, void and memory execution
admit the calls. Poison propagates per lane; any undef lane fails even for a
discarded result. Source freezes repair inputs, result freezes choose zero
for poison, and results are independent snapshots. Parameter/return attributes,
including `immarg`, reject. Other widths, oversized/scalable vectors, vector
arguments/returns/PHIs/loads/stores, AIR aliases, tail and flagged calls remain
outside the supported profile. An LLVM-valid i80 call in a cold block rejects.

The 64 new cache identities occupy slots 2688..2751 without moving older
identities; the shared stack cache has 2,752 entries. A call consumes one step,
two lane counts of profiling work and one shared construction slot. The existing
4,096-result, 1,000,000-vector-work and 1,000,000-attribute-work limits remain.

ASan/UBSan macOS ARM64 qualification passes:

- Focused units check **130,048 exact lane values** with the standard-library
  64-bit byte reverser shifted to the declared width, plus **52,224 involutions**
  and **6,528 lane-state checks**. Cases exhaust i16 and include 4,096 patterns
  per wider width, individual set/clear bits, high-bit noise, snapshots, invalid
  widths and guards. The shared cache unit checks all 2,752 identities. Earlier
  integer-vector units replace unsupported-byte-swap guards with unsupported
  leading-zero count because byte swap is now admitted; their positive value
  and state checks remain unchanged.
- `bundle/reference-r2` checks **1,600 decoded shapes** across every supported
  width/count, five source forms and five constructions. Its **4,412 composed
  native LLVM values** are exact. It checks 2,512 fixed freeze choices, 6,112
  poison-store failures, 3,764 strict undef failures, 33,600 mixed/integer API
  cases, 38,400 malformed metadata/source refusals and 4,800 short-budget
  refusals. Exact steps, whole output bytes, unaligned bindings and derived
  extents are checked.
- Four bulk modules add **262,144 exact native lane values**: every i16 encoding
  and 65,536 patterns per i32/i48/i64 width. Matrix plus bulk gives **266,556
  exact LLVM comparisons**, also checked against the independent byte-reversal
  oracle. VM inputs contain high-bit noise and native loads receive canonical
  values. All supported widths occupy whole bytes; native padding behavior is
  not qualified.
- **926 controls** cover states, freezes/discards, snapshots, chains, signatures
  with a valid baseline, unsupported profiles, duplicates, changing-source
  loops and floating/integer API isolation. They include 320 population-count/
  involution cases and 320 byte-swap/bit-reversal commutation cases, both call
  orders and both scalar APIs. A floating predicate is widened to i16 before
  swapping and yields 256 through mixed execution; integer-only execution
  rejects the floating producer.
- All 64 byte-swap declarations execute together through both scalar APIs,
  independently summing all-one results modulo 2^64 to 4,503,668,347,895,744.
  Canonical attributes admit; 48 immarg transfers reject before writes.
  Sixteen exact shared storage/work boundary checks pass through all four
  APIs, with over-limit refusals before writes. Historical population-count
  and bit-reversal checkers retain their full attribute-work refusal controls.
- Sixteen existing units and seventeen reference regressions pass, including
  vector population count/reversal, scalar integer intrinsics, integer/vector
  binary execution, memory operands, bitcasts, conversions, sign/rounding/sqrt/
  extrema, vector/scalar/memory FMA and scaling, optional fusion and classification.
  Historical reference checkers remain unchanged.
- Both Swift hash modes pass all 24 software Metal groups, with two drained
  runtimes each. Each runtime adds **108 dispatches across 32 kernels**:
  96 complete and twelve fail as expected. All four widths check high-bit noise,
  deferred writes, sparse bindings, pipeline reuse, poison/undef/discards,
  source/result freezes, snapshots, nontrivial double swaps with integer
  comparison/select, and guard words. Tail-call and i80 pipelines reject.
  All 56 compute and 40 blit refusal logs pass.

The first full reference run passes. The second corrects cache-output width
labels from internal indexes to actual widths and names both mixed-family
properties in the control summary. It passes the complete suite again. Both
sources, binaries and complete results are retained. Production needed no
correction during reference qualification.

Complete retained bundle:

`/Users/alex/Library/Caches/vinix-ios/air-vector-bswap-validation-20261115-r1`

The adjacent `.tar.gz` preserves the complete bundle: fixtures/results,
binaries, generated host C/objects, compiler captures, commands, helpers and
feature-pinned `bundle/source.tar`. The V archiver compares complete typed
inventories before/after compression. The maintained archive checker compares
every logical payload, path, size, type, mode and link, including the root mode.
A fresh extraction under `.restored-r1/tree/` passes that comparison. The
restored sanitized byte-swap checker passes its complete suite again, writing
outside the restored tree, followed by another complete archive comparison.
Original and restored evidence remain intact.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.gz` | `cd31c8dc9843720475dbc0c7896b10a50f098d2ae71b43a8be5e07b89b18c52a` |
| `.tar.gz.inventory.txt` | `f03f4ab86cba58e9bd2a429d6ae5c97ef9c8c6d425e3ab7baa8724092994c968` |
| `bundle/source.tar`, revision `6a4330c5f8d1063bea7ad13811bc8d2d41acec2e` | `03b17cc0255b9c3f6e1d4b899e5660842f0f4538ab7fd40dc19cd720d96c4314` |

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
