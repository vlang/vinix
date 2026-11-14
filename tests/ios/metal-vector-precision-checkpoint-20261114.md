# Software Metal vector precision conversion — 2026-11-14

`4fbde3625b14eaf3d65c7ffba60d1bf6d86ae419` adds unflagged `fpext` (half to float) and `fptrunc`
(float to half) for fixed AIR vectors with unchanged lane count (1..16).
Each lane uses the existing integer-based scalar converter. Finite widening
is exact; narrowing rounds nearest/ties-to-even with gradual underflow,
signed zeros and signed infinity on overflow. Conversion NaNs choose the
preferred positive quiet encoding (`0x7e00`/`0x7fc00000`).

Complete sources must be supported literals or earlier constructions;
validation includes inactive blocks. Poison remains local. Any undef source
lane rejects at the executed cast, including discarded results. Source
freezes repair indeterminate lanes; result freezes do not suppress earlier
errors. Dynamic failures preserve prior writes. Independent snapshots compose
with existing vector operations, raw bitcasts and integer casts.

One executed cast costs one step and source plus result lane work. The shared
1,000,000-lane budget, 4,096 static construction slots and execution-owned
array are reused; no ownership field or per-lane allocation is added. Mixed
scalar, void and memory APIs support these conversions. The integer-only API
rejects floating lanes. Fast-math flags, other formats, integer/floating
numeric vector conversions, reshaping, vector arguments/returns, PHIs and
loads/stores remain unsupported.

ASan/UBSan qualification passes:

- 65,547 unit value checks cover every half encoding through widening and
  narrowing, plus exact tie/subnormal/overflow/NaN cases, source masking and
  immutable snapshots. Another 3,264 lane-state checks cover every count/lane,
  poison isolation, strict undef, freezes and width/direction/opcode/tag guards.
- 800 decoded shapes cover every count 1..16, both directions, five source
  forms and literal/inserted/source-frozen/round-trip/shuffled results.
  There are 323,722 LLVM comparisons: 321,201 exact representations and
  2,521 permitted conversion-NaN choices. A 321,536-sample sweep includes all
  half encodings, both signs of all 31,744 narrowing midpoints and their
  adjacent float encodings, plus 65,536 deterministic float patterns. The last
  midpoint is the finite-to-infinity overflow threshold.
- 1,256 explicit frozen-zero choices, 3,040 poison-store failures and 1,882
  strict undef failures preserve the documented prior writes. Every output
  and guard byte is checked with unaligned accesses and derived bounds.
  Scalar/integer APIs pass 659,800 checks; metadata/source mutations yield
  16,000 rejections and short budgets yield 1,600 before writes.
- 81 focused controls cover source/result freezes, discards, old snapshots,
  round trips, fneg/bitcast/comparison/select composition, poison isolation,
  loop slot reuse, every fast-math flag, unsupported profiles/type mutations
  and independence from upward/downward host rounding modes.
- Eight public memory/void boundaries admit exactly 4,096 constructions and
  1,000,000 lane-work units; 4,097 or 1,000,016 reject before writes.
- Focused regressions cover the shared cast dispatcher, existing vector
  bitcasts/integer casts, scalar half conversion, integer execution and vector
  floating arithmetic. The scalar-half checker now validates supported
  two-lane vector freeze and rejects a new 17-lane freeze fixture. Historical
  bundles retain their original checkers.

The test oracle uses exact f64 half values, binary search and distances to
adjacent encodings, independently of production normalization/jam/packing.
LLVM verifies modules before native projection. Only defined selections execute
natively. Conversion NaNs require the interpreter's preferred encoding while
allowing native payload/sign choices; inserted/copied bits compare exactly.
The native environment is set to its default nearest rounding mode.

Both Swift hash modes pass all 24 software Metal groups, with two drained
runtimes each. Each runtime exercises 58 new deferred samples: both directions,
ties, subnormal/normal boundaries, overflow, signed zeros/infinities, raw NaNs,
source/result freezing, old snapshots, round trips and composed operations.
Source/index writes after encoding remain visible through sparse bindings.
54 dispatches complete and four fail as expected. Two undef failures preserve
only the marker; two poison failures also preserve a frozen-zero store.
Flagged precision casts reject at pipeline creation. All prior synthetic
kernel groups remain in the host suite.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-precision-validation-20261114-r1.tar.zst`

The bundle retains complete fixtures/results, binaries, generated host C,
objects, receipts, compiler snapshots, LLVM headers, qualification helpers and
`source.tar` pinned to the feature revision. Initial helper compilation and
regression invocation failures remain, along with the scalar-half checker's
stale freeze rejection and its complete comparison output. Helper quoting,
array construction and the scalar-half `self-test` invocation were corrected.
The final scalar-half fixture checks both supported freeze and its lane limit.
All forty final fresh-process blit rejection logs remain. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

The first restored replay ended before recording the deterministic host result.
Its complete tree remains under `replay-interrupted`, with retained-path receipt
`.interrupted-replay-retained.inventory.json` (SHA-256
`47e2de9335347f6eef7272aa36bdb23cae85d6ecb36eb3ea7c83a491e40bad02`).
Receipts bind their absolute source path, so the original receipt refused the
renamed path. Both receipts and that refusal are retained. A strict comparison
allowing only the exact root/source-path rename proves every byte hash, size,
mode, link and entry matches. The earlier clone also matched the original
receipt before continuation. Only the remaining host check was resumed, with
the same checksum-verified restored executable and fresh output roots; it
passes all 24 groups. The replay archive includes these receipts and helpers.

A fresh extraction replaced the bundle path. The maintained
`tests/packages/wine-workspace-archive.v` checker matches all bytes, sizes,
types, modes and links, including the root; all 28 selected identities match.
All twelve restored runs exit 0: five units, five references and both 24-group
host modes in fresh output roots. Reference logs match the saved results.
Complete inventory, selected identities and archive checksum match after
replay. A fresh replay archive extraction also matches its complete inventory.
Original expanded trees remain.

The standalone compiler was captured after builds; the host harness captured
its separate toolchain before generation. Standalone V libraries, SDKs,
assembler, library symlinks and dylibs remain external prerequisites. Native
JIT code is uninstrumented. Leak detection is disabled and retained heap was
not measured. The ordinary runner was not rebuilt. These are synthetic CPU
fixtures: no Apple shader, GPU rendering, presentation, Vinix guest, Fortnite
frame or launch gate is newly verified. Integrity checks do not replace
historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` | `14ec61fb6c58ff4bbf9bd1aa15f178638e492d0021d61788a519b73e5e791fbe` |
| `.inventory.json` | `051d17a005044ceb8f21fa9651943901d970b5320aa93687118dfce92bdf69b4` |
| `.replay.tar.zst` | `f03fa11cfe114991dc2fea3cc88213a0558b2c3134831b4606cd97c60a5d3276` |
| `.replay-inventory.json` | `14c8a407a12c2421613dc3eb68eb1d91a9e409052b16e1964a31c43d9793cfd1` |
| `source.tar`, revision `4fbde3625` | `6a8f2071d6dfd01e5bd65ba0db241400a8fdf897fee495ae1dea72fdb0484271` |
