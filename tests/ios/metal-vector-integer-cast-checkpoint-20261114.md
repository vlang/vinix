# Software Metal vector integer casts — 2026-11-14

`23ac0f31bcc23b04b43fd0d7fb8d46c8370fd8b8` adds `trunc`, `zext` and `sext`
for fixed 1..16-lane i1..i64 AIR vectors with unchanged lane count. Truncation
requires a narrower destination; extensions require a wider one. `trunc`
supports `nuw`, `nsw` or both; `zext` supports `nneg`. Violations produce
lane-local poison through the existing scalar cast evaluator.

Complete sources must be supported literals or earlier constructions.
Validation includes inactive blocks. Any undef source lane rejects at the
cast, even for discarded results or extraction of another lane. Freezing a
source repairs indeterminate lanes; freezing a result does not suppress an
earlier evaluation error. Dynamic failures preserve prior stores.

Results retain independent snapshots and compose with supported vector
operations, including another integer cast. Each executed cast costs one
step; source plus result count charge the shared 1,000,000-lane validation
budget. Casts reuse the existing 4,096 static construction slots and
execution-owned allocation, without new ownership fields or per-lane
allocations. Integer, mixed scalar, void and memory APIs share the rules.
Vector floating conversions, bitcasts, reshaping, pointer casts, arguments,
returns, PHIs, loads/stores, scalable vectors and widths above i64 remain
unsupported.

ASan/UBSan qualification passes:

- 1,806,336 independent per-bit lane checks cover every unequal i1..i64
  width pair, seven operation/flag variants, eight edge patterns and sixteen
  lanes. Upper source bits are masked and original snapshots remain intact.
  Another 719,712 lane-state checks cover all source widths, counts, target
  lanes, poison isolation, strict undef, freezes and shape/opcode/flag/tag guards.
- 42,336 serialized shapes cover every width pair and flag variant with
  1/3/16 lanes. They pass 283,192 exact native LLVM comparisons, 29,310
  explicit fixed-zero freeze choices and 364,874 poison-store failures that
  preserve prior writes. Integer/mixed APIs pass 1,354,752 checks; metadata
  and source mutations yield 423,360 rejections, with 84,672 short-budget
  rejections before writes.
- 130 focused controls cover whole/partial poison and undef, source/result
  freezing, discarded results, old snapshots, cast/comparison composition,
  poison isolation, integer/mixed loop slot reuse and unsupported profiles.
- Eight public memory/void boundaries admit exactly 4,096 constructions and
  1,000,000 lane-work units; 4,097 or 1,000,016 reject before writes.
- Existing floating arithmetic, negation, integer binary, comparison,
  per-lane/whole-vector select, freeze, shuffle and extraction references pass,
  together with scalar promise, integer execution, comparison and integer
  binary unit tests. Historical checkers and bundles remain unchanged.

LLVM verifies complete modules before native projection. Only defined selections
execute natively; indeterminate selections use explicit interpreter expectations.
The independent per-bit oracle classifies promise violations without executing
invalid native operations. Align-1 scalar accesses and byte GEPs match VM layout;
only native high padding bits in the final odd-width integer byte are masked.
All other result and guard bytes compare exactly.

All 24 software Metal groups pass in both Swift hash modes, with two drained
runtimes each. Each runtime exercises 238 new deferred dispatch samples across
five width pairs and all applicable flag variants: 156 complete and 82 fail
as expected. Source and index buffers change after encoding; sparse bindings,
source/result freezes, old snapshots and chained casts are checked. Seventeen
undef failures preserve only the prior marker; the other 65 failures also
preserve a frozen-zero store before a poison store fails. Unsupported vector
bitcasts reject at pipeline creation.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-integer-cast-validation-20261114-r1.tar.zst`

The bundle retains fixtures/results, binaries, generated host C, objects,
build receipts, compiler snapshots, LLVM headers, selected identities and
`source.tar` pinned to the feature revision. Initial checker compilation and
native function-name lookup failures remain with their sources, logs, binary
and fixtures. The final checker clones borrowed IR names before C lookup and
asserts a non-null handle; all final runs pass. All forty fresh-process blit
rejection logs remain. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A fresh extraction replaced the bundle path. The maintained
`tests/packages/wine-workspace-archive.v` checker matches complete bytes, sizes,
types, modes and link targets, including the root; all 1087 selected identities
match. All seventeen restored runs exit 0: ten references, five unit binaries
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
| `.tar.zst` | `72449eb70020ebd0c0ab9c73e4563b4e1ff74cd3a1dd4ccb0821af2cebe91aab` |
| `.inventory.json` | `cf25a788b0ac516d77a03da2209f3bf22cce4cd36c58ec43659213f17d35137d` |
| `.replay.tar.zst` | `380748e22def37e4f95d18e91efac5a6fc24b2f4df63611c04c6c48bfbf85fd3` |
| `.replay-inventory.json` | `c99833b2ebbadbf858ce6e55b686875e55d1795d456882a2bc4ad68ad0cadda1` |
| `source.tar`, revision `23ac0f31b` | `5ed1176407b7189cee9502a6339d11d8679b3c877915e636f320cd9c4cbd9559` |
