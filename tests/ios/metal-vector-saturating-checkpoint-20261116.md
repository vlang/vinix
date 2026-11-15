# Software Metal vector saturating arithmetic — 2026-11-16

`669fd76fee1cc96369a42849d382a5804e2adc50` adds ordinary direct vector `llvm.sadd.sat`, `llvm.uadd.sat`,
`llvm.ssub.sat` and `llvm.usub.sat` calls for 1..16 lanes at widths i1..i64.
Both arguments and the result must have identical integer vector types. Signed
results clamp to signed limits; unsigned addition clamps to the unsigned maximum
and unsigned subtraction to zero, following the
[LLVM saturation contract](https://llvm.org/docs/LangRef.html#saturation-arithmetic-intrinsics).

The scalar evaluator supplies unsigned arithmetic and sign-bit overflow detection,
including i1 and i64, without host signed overflow or new normal-path allocation.
Poison propagates per lane from either source; any undef source lane fails even
for discarded results. Freezes choose zero for indeterminate lanes and results
are snapshots. Both scalar APIs, void and memory execution admit these vector
calls. Scalar integer-only calls retain their restrictions; floating producers
still require mixed execution.

Canonical names, exact shapes/signatures, direct declaration identity, ordinary
flags/calling convention and both sources are checked. Harmless function
attributes remain allowed; return/parameter attributes, including immarg, reject.
Cold unsupported blocks reject before writes. Vector arguments/returns/PHIs/
loads/stores, scalable/oversized vectors, i65/wider lanes and AIR aliases remain
outside the profile. The existing extrema argument profiler moves unchanged to
the shared binary integer helper; its source checks and work accounting remain.

Four separate 1,024-entry ranges occupy 11968..12991, 12992..14015, 14016..15039
and 15040..16063 in the operation order above. The shared declaration cache has
16,064 stack entries. Each call costs one step, three lane counts of profiling
work and one construction slot. The 4,096-result and 1,000,000-work caps remain.

ASan/UBSan macOS ARM64 qualification passes:

- Units: **4,124,032** independent value comparisons using checked signed margins
  and unsigned 32-bit limbs with explicit carry. Every i1..i8 pair, 4,096 wider
  patterns per operation, all widths/counts, **36,864 boundary pairs**, addition
  commutativity, zero identities, masking and snapshots are covered. Another
  **835,584** poison/undef/freeze checks cover both sources. All **16,064** shared
  cache identities pass. Older units use unsupported vector saturating-shift
  name guards and retain their positive coverage.
- `bundle/reference-r2`: **102,400** decoded shapes across four operations, five
  source forms and five paths. **282,368** exact native results, **160,768** fixed
  freeze choices, **391,168** poison-store refusals, **240,896** strict-undef
  refusals, **2,150,400** scalar/integer API cases, **2,826,240** malformed metadata/
  source refusals and **307,200** short-budget refusals pass. Every output byte,
  exact step count, unaligned binding and derived extent is checked.
- Bulk adds **1,267,072** exact native lane comparisons: **1,549,440** new native
  values total. All i1..i8 pairs and 4,096 wider pairs per operation are checked.
  Native calls consume defined extracted results with canonical padding; the VM
  also receives noisy padding. Native padding behavior is not qualified.
- **4,676** controls cover all four declarations together with two edge pairs at
  each width, both poison/undef sources, discarded results, repaired attribute
  baselines, forbidden return/parameter immarg groups and cold i65 blocks through
  four APIs. Attribute-refusal outputs have valid full-sized bindings. Sixteen
  exact shared work/storage boundary checks pass through four APIs. Work uses
  4,096 16-lane calls plus 50,212 extracts; one more rejects before writes.
- `bundle/regressions`: **19** focused executions pass, including the new vector
  unit, scalar saturation unit/reference, unchanged vector extrema LLVM reference,
  scalar/vector abs, rounding/cache, population count, reversal, byte swap, both
  zero counts, funnel shifts, integer execution, memory, floating sign and scalar
  intrinsics. The old extrema reference independently rechecks the shared profile.
  This batch does not rerun every historical standalone checker.
- Both hash modes in `bundle/software` pass all **24 software Metal groups**, with
  two drained runtimes each. Each runtime adds **1,504 dispatches across 288
  kernels**: **1,408 complete and 96 fail as expected**. Four families, equal
  inputs, source/result freezes, poison/undef/discard, nonzero old snapshots,
  repeated saturating chains, deferred writes, sparse bindings and guards are
  covered. Eight tail/i65 pipelines reject. All **56 compute and 40 blit refusal
  logs** pass. Every original harness assertion remains; the two modes run in
  separate processes from one build.

The first reference build failed because a checker-local `mask` variable shadowed
the C function `mask(width)`. The final checker names the function `bit_mask`;
reference-r2 is the first executed new reference. The r1 source and build rejection
are retained. No production correction was needed. The only difference between
tested and committed runtime fixture text is removal of one final LF. Both copies,
their hashes and the exact one-byte comparison are retained in
`bundle/runtime-eof-proof.txt`; no token, function body or internal line differs.

Complete retained original:

`/Users/alex/Library/Caches/vinix-ios/air-vector-saturating-validation-20261116-r1`

New reference IR, bitcode and comparison records are individually gzip-compressed
only after each module finishes. Each is immediately decoded and compared with
its original SHA-256; `compressed.sha256` records both hashes. Historical checker
outputs retain their original layout. No older evidence is changed or removed.

The typed inventory compares two complete root inventories, then a separate check
compares again. The adjacent compressed archive is fully decoded and compared
against the complete original's logical bytes, sizes, types, modes, links and
root mode. The producer rechecks original inventory, archive checksum and tool
identities afterward. All pass; originals remain retained. No second expanded
restoration or execution replay is claimed.

| Artifact | SHA-256 |
| --- | --- |
| Adjacent `.tar.gz` | `a003c381da8714ac1152dbc3c100d8ca85f147b5127e74c3dc59763afd7b21f8` |
| Adjacent `.inventory.json` | `5d4bb416927a0b9cc570f6d45b241ebbe3a65122307b7c99f8be54c58ed92d67` |
| `bundle/source.tar`, revision `669fd76fee1cc96369a42849d382a5804e2adc50` | `050117e57e9866f3ef35c4a6549b1d4f36b410b23b279516dade288f0820a74e` |

Adjacent `.inventory-record.*`, `.inventory-check.*` and `.archive.*` retain
commands, logs and zero statuses; `.tar.gz.audit/` retains the archive checks.
`bundle/verified-inputs.sha256` compares captured compatibility V and dispatch
assembly, with the explicit runtime final-LF proof, and the exact final reference.
The host compiler was captured before generation; the standalone compiler is
recorded after checks. V libraries, SDKs, assembler, symlink targets and dylibs
remain external prerequisites.

Native JIT is uninstrumented; leak detection is disabled and retained heap was
not measured. The ordinary runner was not rebuilt. These synthetic CPU checks
qualify no Apple shader, GPU rendering/presentation, Vinix guest, Fortnite frame
or launch gate. Integrity receipts do not replace historical auditors or permit
removing their original evidence.
