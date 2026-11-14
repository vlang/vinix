# Software Metal vector negation — 2026-11-14

`b5089a91819b54ed3c2682cd4b83ec7694268989` adds unflagged `fneg` for
fixed 1..16-lane half/float AIR vectors. Negation flips only the sign bit,
including signed zeros, and preserves NaN quiet/signaling bits and payloads,
following [LLVM fneg](https://llvm.org/docs/LangRef.html#fneg-instruction).
Mixed scalar, void and memory execution share validation and evaluation;
the integer API rejects floating vectors.

Sources may be supported literals or earlier supported constructions. Preflight
checks the complete source, including inactive blocks. Poison propagates per
lane. Any undef source lane rejects at negation, even for a discarded result
or extraction of another lane, following the bounded arithmetic policy.
Freezing the source repairs indeterminate lanes; freezing the result does not
suppress earlier errors. Dynamic failures preserve preceding writes.

Independent snapshots support further negation, insertion, shuffle, freeze,
comparison, select and extraction. Negation costs one executed step. Source
and result counts charge the shared 1,000,000-lane validation budget. Results
share the existing 4,096 static construction slots, reused on loop visits and
freed with the execution-owned array on every exit. No ownership field or
per-lane allocation is added. Floating vector binary arithmetic, fast-math
flags, other lane formats, scalable vectors, vector arguments/returns, PHIs
and vector loads/stores remain unsupported.

ASan/UBSan qualification passes:

- All 65,536 half encodings preserve magnitude bits, flip sign, restore under
  double negation and retain source snapshots. Another 2,992 lane checks cover
  both formats and every count/lane, poison isolation, source/result freezing,
  strict undef rejection and shape/tag guards.
- 300 serialized shapes cover six counts, five constant forms and literal,
  computed, doubled, inserted and shuffled results: 526 exact native LLVM
  comparisons, 222 fixed-zero freeze choices, 990 poison-store failures and
  562 strict undef rejections. All dynamic failures preserve the prior marker.
  Scalar/integer APIs pass 4,600 checks; metadata/source mutations pass 5,400,
  and short budgets pass 600 rejection checks before writes.
- 64 focused controls cover source/result freezing, localized poison, undef
  in unselected lanes, discarded results, unchanged old snapshots, repeated
  loop slots, comparison/select composition, inactive wide vectors, fast-math
  flags, unsupported sources/formats and nonfloating lane-type mutations.
- Eight public memory/void boundary checks admit exactly 4,096 constructions
  and 1,000,000 lane-work units, rejecting 4,097 or 1,000,016 before writes.
- Existing integer binary, comparison, per-lane/whole-vector select, freeze,
  shuffle and extraction references pass. Integer execution, scalar promise,
  comparison and integer vector binary units pass. Historical bundles and
  checkers remain unchanged.

LLVM verifies complete modules before projection to native comparison
functions. Only defined selections execute natively; indeterminate native
selections are skipped. Freeze choices have explicit interpreter expectations.
Byte GEPs and align-1 accesses match VM layout; MCJIT uses the host layout.

All 24 software Metal groups pass in both Swift hash modes, with two drained
runtimes each. Forty-six new deferred dispatch samples per runtime cover both
formats, signed zeros, infinities, subnormals, signaling/quiet NaN payloads,
input writes after encoding, poison/undef handling, source/result freezing,
old snapshots, double negation and comparison/select/shuffle composition.
Forty-two complete successfully and four fail as expected. Two failures preserve
only the prior marker; two also retain a frozen-zero store before a poison
store fails. A fast-math vector-negation pipeline rejects.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-fneg-validation-20261114-r1.tar.zst`

The bundle retains fixtures/results, binaries, generated host C, objects and
build receipts, compiler snapshots, LLVM headers, selected identities and a
`source.tar` pinned to the feature revision. The initial host build stopped
when TLS archive creation encountered a missing temporary directory. That
attempt remains complete; creating the directory and rerunning the full harness
succeeded. Decode with `zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A fresh extraction replaced the bundle path. The maintained
`tests/packages/wine-workspace-archive.v` checker matches complete bytes, sizes,
types, modes and link targets, including the root; all 894 selected identities
match. All fifteen restored runs exit 0: eight references, five unit binaries
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
| `.tar.zst` | `65990fa178c24860c5dff781763b5c463d8ad74d77ab68262ff397541798f843` |
| `.inventory.json` | `eb471606f85be633f54f1a43b5a4e7a96cfd0ddccd715d04d884664c79326a51` |
| `.replay.tar.zst` | `431370d7e4e69eceee727c6142dbb4028400800f50f3b5a28a83c68f313cb3b8` |
| `.replay-inventory.json` | `554c92a8840a58eed96597a0f6526ab229afea3f6810187a436cb6f54f60fac0` |
| `source.tar`, revision `b5089a918` | `6d6e354ac3a5717827c447b4fbc9565aaf628ea6da03d09d5db2d40afa884c43` |
