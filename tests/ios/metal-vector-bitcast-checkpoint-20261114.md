# Software Metal vector bitcasts — 2026-11-14

`eaacb559b2f5e4ba24e08e20a3682b1f32cdc3e9` adds raw `bitcast` between i16/half and i32/float AIR
vectors, in either direction, with unchanged lane counts (1..16). Every bit is
preserved, including signed zero, NaN signs/payloads and signaling NaNs. No
floating arithmetic or quieting occurs.

Complete sources must be supported literals or earlier constructions.
Validation includes inactive blocks. Poison remains local to each lane; any
undef source lane rejects at the cast, including discarded results. Source
freezes repair indeterminate lanes; result freezes do not suppress earlier
errors. Dynamic failures preserve prior stores. Results retain independent
snapshots and compose with existing vector operations and integer casts.

Each executed cast costs one step and charges source plus result count to
the shared 1,000,000-lane validation budget. It reuses the existing 4,096
static construction slots and execution-owned array. No ownership field or
per-lane allocation is added. Mixed scalar, void and memory APIs support these
casts; the integer-only API rejects floating lanes. Numeric floating
conversions, other formats, reshaping, scalar/vector and pointer casts,
scalable vectors, vector arguments/returns, PHIs and loads/stores remain
unsupported.

ASan/UBSan qualification passes:

- 2,097,152 raw-bit unit checks cover every half encoding and deterministic
  float patterns, source masking and immutable snapshots. Another 3,264
  lane-state checks cover every count/lane in both widths, poison isolation,
  strict undef, freezes and width/count/tag guards.
- 1,600 decoded AIR shapes cover all counts 1..16, four directions, five
  literal forms and literal/inserted/source-frozen/round-trip/shuffled results.
  There are 266,516 exact native LLVM comparisons, including 262,144 sweep
  samples: every half encoding in both directions and 65,536 deterministic
  float patterns in each direction. Signed zeros and signaling/quiet NaN bits
  compare exactly, without normalization or padding masks.
- Another 2,512 cases check explicit fixed-zero freeze choices, 6,080 check
  poison-store failures and 3,764 check strict undef failures. Every result
  and guard byte is checked, including prior writes after dynamic failures.
  Scalar/integer APIs pass 557,744 checks; metadata/source mutations yield
  32,000 rejections and short budgets yield 3,200 rejections before writes.
- 121 focused controls cover source/result freezing, discards, old snapshots,
  round trips, fneg/comparison/select composition, poison isolation, loop slot
  reuse, unsupported profiles and lane-type mutations. Width mismatch and
  same-category casts require the bitcast shape diagnostic before any store.
- Eight public memory/void boundaries admit exactly 4,096 constructions and
  1,000,000 lane-work units; 4,097 or 1,000,016 reject before writes.
- Existing integer casts, floating arithmetic, negation, integer binary,
  comparison, per-lane/whole-vector select, freeze, shuffle and extraction
  references pass, along with scalar promise and integer execution units.
  Existing unsupported bitcast fixtures now use double. Historical bundles
  retain their original checkers.

LLVM verifies complete modules before native projection. Only defined
selections execute natively; indeterminate cases use explicit interpreter
expectations. Align-1 scalar accesses and byte GEPs match VM layout; native
MCJIT uses the host layout.

Both Swift hash modes pass all 24 software Metal groups, with two drained
runtimes each. Per runtime, 92 new deferred dispatch samples exercise both
widths and directions, signed zeros, subnormals, infinities and raw NaNs,
poison/undef, source/result freezes, old snapshots, round trips and composed
negation/comparison/select. Source and index writes after encoding remain
visible through sparse bindings. 84 dispatches complete; eight fail as
expected. Four undef failures preserve only the prior marker; four poison
failures also preserve a frozen-zero store. Reshaping rejects at pipeline
creation. Metadata ordering is asserted; rejection assertions name the fixture.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-bitcast-validation-20261114-r1.tar.zst`

The bundle retains fixtures/results, binaries, generated host C, objects,
build receipts, compiler snapshots, LLVM headers, selected identities and
`source.tar` pinned to the feature revision. Initial checker and host fixture
failures remain with their sources, binaries and logs. The checker initially
omitted the explicit GEP layout from focused controls; the final version
supplies it and validates profiles before runtime assertions. New host
fixture names initially followed the intentionally metadata-free final entry;
the final version restores that entry's position and asserts the ordering.
All forty final fresh-process blit rejection logs remain. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A fresh extraction replaced the bundle path. The maintained
`tests/packages/wine-workspace-archive.v` checker matches complete bytes, sizes,
types, modes and link targets, including the root; all 1100 selected identities
match. All nineteen restored runs exit 0: eleven references, six unit binaries
and both 24-group host modes, using separate output roots. Complete inventory,
selected identities and archive checksum match after replay. A fresh replay
archive extraction also matches its complete inventory. Original expanded
trees remain.

The standalone compiler was captured after builds; the harness captured its
separate toolchain before generation. SDKs, assembler, library symlinks and
dylibs remain external prerequisites. Native JIT code is uninstrumented. Leak
detection is disabled and retained heap was not measured. The ordinary runner
was not rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU
rendering, presentation, Vinix guest, Fortnite frame or launch gate is newly
verified. Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` | `ded1e02bbe0c3577dc56a5451e6b74def8f4894612f738e33fcdb8e7f3d0c489` |
| `.inventory.json` | `bd8ebad4c825348e8314ab97ffaf15447566745a11584cdfff3cd14c8a7e6771` |
| `.replay.tar.zst` | `f0b1d93c09281f080e0d31d0a1dc8ebf3d886416291656f2772f1510972dc5b0` |
| `.replay-inventory.json` | `0ac268a866728f29d178042cb9ae5a94291b3ef810a4eac5641ba3b2cf498f3e` |
| `source.tar`, revision `eaacb559b` | `80045e1838c441e867150611ff2d250bf4e6cc5e2273ee4cfb7c1f689dd09747` |
