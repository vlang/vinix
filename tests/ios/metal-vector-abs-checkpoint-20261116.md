# Software Metal vector integer absolute value — 2026-11-16

`f0f06132562f1d869ca9adefab2484d954f974d8` admits ordinary direct `llvm.abs.vNiW(<N x iW>, i1)` calls for
1..16 lanes and i1..i64 through both scalar APIs, void and memory execution.
Result and first-argument types match. A constant scalar flag applies per lane:
signed minimum keeps its bits under false and produces poison under true;
other inputs produce their magnitude, following the
[LLVM abs contract](https://llvm.org/docs/LangRef.html#llvm-abs-intrinsic).

The evaluator reuses unsigned modular negation; no signed minimum is negated
and no normal-path allocation is added. Source poison propagates per lane;
any undef source lane fails even for discarded results. Freezes choose zero;
results are snapshots. Canonical names, signatures, shapes, direct declaration
identity, ordinary flags and calling convention are required. Return and first-
argument attributes reject; parameter two permits only exact immarg. Harmless
function attributes remain allowed. Each call revalidates its i1
constant, including cache hits and cold blocks. Scalar integer-only calls retain
their existing restrictions; floating producers still require mixed execution.

Slots 10944..11967 add 1,024 width/count identities, making 11,968 stack cache
entries. Flags share an identity but retain their own meaning. A call costs one
step, two lane counts of profiling work and one result construction slot. The
4,096-result and 1,000,000-work limits remain unchanged.

ASan/UBSan macOS ARM64 qualification passes:

- Units: **2,065,472** independent value/poison comparisons, exhausting i1..i16
  under both flags, plus wide patterns, all shapes, boundary values, upper-bit
  noise and snapshots. Another **208,896** poison/undef/freeze checks pass.
  The shared cache unit covers all **11,968** identities. Older units now use
  unsupported vector saturating-add name guards; positive coverage remains.
- `bundle/reference-r3`: **51,200** decoded shapes across both flags, five source
  forms and five paths. **137,111** exact native results, **80,617** fixed freeze
  choices, **199,424** poison-store refusals, **120,448** strict-undef refusals,
  **1,075,200** scalar/integer API cases, **1,413,120** malformed metadata/source
  refusals and **153,600** short-budget refusals pass. Every output byte, exact
  instruction count, unaligned binding and derived extent is checked.
- Bulk adds **655,424** exact native lane comparisons: **792,535** native values
  in total. True-flag minimum patterns use zero in this defined sweep; independent
  minimum-poison matrix/unit cases remain. Native comparisons consume defined
  extracted results with canonical padding; the VM also receives noisy padding.
  Native padding behavior is not qualified.
- **2,769** controls cover both flags at every width with one cached declaration,
  repaired valid baselines, nonconstant arguments/SSA/poison/undef flags, raw
  nonboolean pool words, immarg slots/enums/encoding and a cold i65 block.
  Both scalar APIs, void and memory paths are exercised. Sixteen exact shared
  work/storage boundary checks pass through all four APIs. Work uses 4,096
  16-lane calls plus 54,308 extracts; one more rejects before writes.
- `bundle/final`: **15** focused/regression executions pass: vector/scalar abs,
  shared rounding/cache, vector extrema, population count, bit reversal, byte
  swap, both zero counts, funnel shifts, integer execution, memory, floating sign,
  scalar intrinsics and the unchanged scalar abs LLVM reference. This is a focused
  batch; it does not rerun every historical standalone checker.
- `bundle/software-r2`: both hash modes pass all **24 software Metal groups**,
  with two drained runtimes each. Each runtime adds **240 dispatches across 128
  kernels**: **180 complete and 60 fail as expected**. Both flags, i1/i64,
  freezes, poison/undef/discard, snapshots, mixed-flag chains, deferred inputs,
  sparse bindings and guards are covered. Tail, i65 and dynamic-flag pipelines
  reject; all **56 compute and 40 blit refusal logs** pass. Original harness
  assertions remain; modes run in separate processes from one built binary.

The dynamic-flag fixture assembles as ordinary `test.abs.v1i32`, then renames
that one string-table entry to `llvm.abs.v1i32` before wrapping the synthetic
library. This distinct overload avoids duplicating a declaration. LLVM otherwise
rejects a nonconstant intrinsic flag before the backend can inspect it. Only
the negative fixture is renamed. Decoded-reference controls independently repair
every bad flag before testing refusal through four APIs.

Partial test attempts are retained. The first unit state fixture used known i1
lanes of one, itself INT_MIN, and incorrectly expected them to stay defined under true;
zero fixes the fixture. The first host attempt stopped after that unit failure.
The next host attempt failed assembly on the intentional dynamic flag; a renamed
placeholder then duplicated an existing overload and correctly caused whole-
library rejection. The final fixture uses the distinct v1 overload. No production
correction was needed. Empty reference-r1/r2 prelaunch attempts and an incomplete
host input copy from transient disk exhaustion are retained; reference-r3 is the
first executed new reference. No failed attempt qualifies this checkpoint.

Complete retained original:

`/Users/alex/Library/Caches/vinix-ios/air-vector-abs-validation-20261116-r1`

New generated reference IR, bitcode and comparison tables are individually gzip-
compressed after each module. Each is immediately decoded and compared with its
original SHA-256; `compressed.sha256` pins logical and compressed bytes. Nothing
from an older evidence bundle is changed or removed. Low free space motivates
retaining this complete bundle in place with a typed inventory rather than
another compressed copy. No archive restoration or replay is claimed.

| Artifact | SHA-256 |
| --- | --- |
| Adjacent `.inventory.json` | `097030cc8d9b9aab71b90e0e3e2ed7c1eb294ac04c6d08e1e6ddb5cdcbce1167` |
| `bundle/source.tar`, revision `f0f06132562f1d869ca9adefab2484d954f974d8` | `89e53e38afa3eed05e3d386b82fcbf211ac1658e0262151616d6a5d375b730af` |

Recording compares two complete inventories; the separate check compares again.
Both adjacent `.inventory-record.status.txt` and `.inventory-check.status.txt`
are zero. The receipt pins logical bytes, sizes, file/directory/root modes and
symlink targets. `bundle/verified-inputs.sha256` compares the passing production
inputs, compatibility V sources, final runtime source and dispatch assembly.
The final harness reuses the already captured compiler through a symlink within
the retained bundle. The standalone compiler is recorded after checks. V libraries,
SDKs, assembler, symlink targets and dylibs remain external prerequisites.

Native JIT is uninstrumented; leak detection is disabled and retained heap was
not measured. The ordinary runner was not rebuilt. These synthetic CPU checks
qualify no Apple shader, GPU rendering/presentation, Vinix guest, Fortnite frame
or launch gate. Integrity receipts do not replace historical auditors or
permit removal of their original evidence.
