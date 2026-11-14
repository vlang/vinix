# Software Metal vector integer operations — 2026-11-14

`3b7144240547f926f086d54ed0c9eb5405c20c23` adds all thirteen integer binary
operations to fixed 1..16-lane i1..i64 AIR vectors: add/subtract/multiply,
signed/unsigned division/remainder, shifts, AND/OR/XOR. `nuw`, `nsw`, `exact`
and OR `disjoint` use the existing scalar rules and produce per-lane poison,
as do oversized shifts. See [LLVM integer operations](https://llvm.org/docs/LangRef.html#binary-operations).
The integer, mixed scalar, void and memory APIs share validation/evaluation.

Supported constants and earlier vector results may supply either operand.
Preflight checks both complete sources, including inactive blocks. Undef in
any operand lane rejects at the binary instruction, including discarded
results or extraction of a different lane. Poison division/remainder, zero
divisors and signed-minimum/-1 reject the whole instruction under the existing
bounded scalar policy; this also rejects signed remainder at minimum/-1.
Freezing sources can repair poison/undef; freezing a zero divisor still leaves
a rejected division. Freezing a result does not suppress evaluation errors.
Earlier stores remain visible after dynamic errors.

Results retain independent snapshots and may feed further arithmetic,
comparison, select, insertion, shuffle, freeze or extraction. One executed
instruction costs one step. Both source counts plus result count charge the
shared 1,000,000-lane validation budget. All vector constructions share the
existing 4,096 static slots and execution-owned array, reused on loop visits
and freed on every exit. No new ownership field or per-lane allocation is
introduced. Floating vector arithmetic, vector PHIs, arguments/returns,
loads/stores, scalable vectors and other lane formats/counts remain unsupported.

ASan/UBSan qualification passes:

- 425,472 independent widened i1..i16 lane checks and 9,840 whole-vector
  division rejections cover all counts, opcodes and thirty flag variants.
  Another 452,608 poison/undef controls cover every i1..i64 width, count,
  lane, operand and opcode. Snapshot and count/width/opcode/flag guards pass.
- 34,560 serialized shapes across i1..i64, six counts, thirty opcode/flag
  variants and raw/frozen/compared/selected results pass 130,212 defined native
  LLVM comparisons, 149,736 fixed-zero freeze choices, 136,716 poison-store
  failures and 44,136 whole-vector division/remainder rejections. All failures
  preserve earlier writes. Integer/mixed scalar APIs pass 921,600 checks.
- 380,160 metadata/source, 69,120 budget and 3,092 focused controls pass,
  including undef/poison, strict division, oversized shifts, source/result
  freezing, discards, unchanged old snapshots, result-shape mutations and
  unsupported profiles. Eight memory/void boundary checks admit exactly
  4,096 constructions and 1,000,000 lane-work units, rejecting 4,097 or
  1,000,016 before output writes.
- Existing comparison, per-lane/whole-vector select, freeze, shuffle and
  extraction references and their controls pass. Integer execution, scalar
  promise guards, comparison units and per-lane select units pass. Historical
  bundles and checkers remain unchanged.

LLVM verifies complete modules before projecting native comparison functions.
Independent range/sign/remainder and 128-bit-product checks classify poison
and rejected divisions. Invalid native division and indeterminate native
selections never execute. Frozen choices use explicit interpreter expectations.
Byte GEPs, align-1 accesses and integer padding agree with VM layout; MCJIT
selects a compatible host layout.

All 24 software Metal groups pass in both Swift hash modes. One hundred new
deferred dispatch samples cover all thirty flag variants, input changes after
encoding, poison isolation, undef rejection, zero/poison/signed-overflow
division, oversized shifts, frozen sources/results and preserved old snapshots
through insertion/shuffle/arithmetic chains. Sixty-one succeed and thirty-nine
fail. Every failure preserves the prior marker; thirty-four stop before a
result write and five preserve an additional frozen-value store before a
poison store fails. Floating vector arithmetic pipelines reject. Both drained
runtimes pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-binary-validation-20261114-r1.tar.zst`

The bundle retains binaries, fixtures/results, generated host C, build receipts,
compiler snapshots, LLVM headers, selected identities and a `source.tar` pinned
to the feature revision. An initial host generator compilation rejected error
propagation from a void test helper and did not execute; its source/log remain.
All final qualification runs pass. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A fresh extraction replaced the bundle path. The maintained
`tests/packages/wine-workspace-archive.v` checker matches complete bytes, sizes,
types, modes and link targets, including the root; all 881 selected identities
match. All fourteen restored runs exit 0: seven references, five unit binaries
and both 24-group host modes, using separate output roots. Complete inventory,
selected identities and archive checksum match after replay. A fresh replay
archive extraction also matches its complete inventory. Original expanded
trees remain.

Standalone compiler capture followed builds; the harness captured its separate
toolchain before generation. SDKs, assembler, external library symlinks and
dylibs remain unsealed prerequisites. Native JIT code is uninstrumented.
Leak detection is disabled; retained heap was not measured. The ordinary runner
was not rebuilt. These are synthetic CPU fixtures: no Apple shader, GPU
rendering, presentation, Vinix guest, Fortnite frame or launch gate is newly
verified. Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` | `f44bb7552cac7afb1f93a040d03248f1368354cc5650796865d950a6e1db9c82` |
| `.inventory.json` | `1d5b0268329e82dad579af3bd72e9aaefe741be19552cc646725b88d76b459fb` |
| `.replay.tar.zst` | `8b833eb74f565c2ce8bfed9ff6ead6dc89b6288871efca1589f7f1de1541f317` |
| `.replay-inventory.json` | `0dee1497e90a8130d2d1a97eff58cba1fb51fd838f491c3fa33b20366c8fb897` |
| `source.tar`, revision `3b7144240` | `5110307caa9da068bb10e5549f84314015438ff8d87af2642d1a37562fcf4b6a` |
