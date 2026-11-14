# Software Metal vector insertion — 2026-11-14

`3faebfad0205522ce4e354d50e0ba4f360259170` adds `insertelement` for fixed
vectors of 1..16 i1..i64/half/float lanes. Sources may be supported constants
or earlier insertion results. Scalar i1..i64 indices are masked and treated
as unsigned, following [LLVM insertion semantics](https://llvm.org/docs/LangRef.html#insertelement-instruction).
Each insertion creates an independent snapshot. Extraction may read older or
newer versions; exact scalar bits, poison and undef are preserved per lane.
Invalid or poison insertion indices poison the whole new vector. Undef
indices error. Later valid insertions may repair individual lanes. Selected
undef still errors at extraction; unselected undef does not affect other lanes.

Integer, mixed scalar, void and memory execution share the implementation;
the integer API admits integer lanes only. Each insertion/extraction costs one
executed step. Preflight caps insertion results at 4,096 per function and
shares the existing million-lane work budget across both operations. One
execution-owned snapshot array is freed on every exit, and static slots are
reused on loop visits. Scalar result slots remain sixteen bytes. Vector
PHIs/selects/freezes, arguments/returns, loads/stores, arithmetic and shuffles
remain unsupported, as do scalable vectors and other lane formats/counts.

ASan/UBSan checks pass:

- 65,280 independent lane-state checks across every count 1..16, defined,
  poison, undef and mixed sources, defined/poison/undef replacements, invalid indices,
  repairs and immutable snapshots.
- 15,840 serialized shapes across all 66 lane formats, counts 1/2/3/4/8/16,
  index widths 1/8/32/64, five source forms and old/new snapshot selection:
  314,754 defined native LLVM comparisons, 664,224 poison and 34,782 undef
  failures preserving earlier writes, and 2,027,520 scalar/integer checks.
- 190,080 metadata, 990 poison/undef/repair/freeze/select/loop and 31,680 step
  budget controls. Both memory and void whole-function fixtures reject 4,097
  insertion results or 1,000,016 shared lane-work units before execution.
- The constant-extraction regression passes 76,560 native comparisons,
  124,410 poison and 1,782 undef failures, 405,504 scalar checks and all its
  remaining controls. Its obsolete insertion exclusion now checks unsupported
  shuffles; the historical archived checker is unchanged.
- All sixteen integer/scalar execution groups pass, including 1,397,052
  narrow arithmetic-flag comparisons. Both pair insertion and freeze groups
  pass their 2,048 value states and guards; constant-extraction units pass
  1,351,680 exact lane/index checks.

LLVM verifies complete modules before native projection; retained
`native-input.bc` files contain only comparison functions. Only defined
selections execute natively. Poison, undef and freeze choices use explicit
interpreter expectations. Byte GEPs and align-1 accesses agree with the VM
layout; MCJIT selects a compatible host layout.

All 24 software Metal groups pass in both Swift hash modes. Deferred dispatch
kernels construct integer, half and float vectors after input changes,
preserve old snapshots when a lane is overwritten, preserve raw NaN/zero
bits, repair poison/undef lanes, freeze invalid selections and fail two poison
stores with the expected earlier writes. Both drained runtimes pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-vector-insert-validation-20261114-r1.tar.zst`

The bundle retains binaries, fixtures/results, build receipts, compiler
snapshots, generated host C, LLVM headers, selected identities and `source.tar`
pinned to the feature revision. Final unit binaries use the `-final` suffix
where rebuilt after the last core edit; preliminary binaries remain retained.
Decode with `zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A completed fresh extraction replaced the bundle path. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matches complete bytes, sizes,
types, modes and link targets, including the root; all 182 selected identities
match. All nine restored runs exit 0: two references, five unit binaries and
both 24-group host modes, using separate output roots. Full inventory, selected
identities and archive checksum match after replay. A fresh replay-archive
extraction also matches its complete inventory. Original expanded trees remain.

Standalone compiler capture followed builds; the harness captured its separate
toolchain before generation. SDKs, assembler, external library symlinks and
dylibs remain unsealed prerequisites. Native MCJIT code is not sanitizer
instrumented. Leak detection is disabled; retained heap was not measured.
The ordinary runner was not rebuilt. This is single-thread CPU execution of
synthetic LLVM fixtures. No Apple-produced shader, GPU rendering,
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` | `7e73734e2df40d19f6cf96f16e45b622d15d76b7c7ae8e9a48eae7fc7e9dc798` |
| `.inventory.json` | `b17b84ba6551d64fff4c247a241e08e1afe53d4b0ff2685281ea7459c1a2f985` |
| `.replay.tar.zst` | `ac77fbd52ac3a09d2b27524fd47b0b14b5bb8fd02debdb4cef641d400db42e58` |
| `.replay-inventory.json` | `4e1b9a36baeb0d5947106b9f525218e759f9ab7c528c6593918fe744d3739d78` |
| `source.tar`, revision `3faebfad0` | `0da246cd502c81d98f9c375b6de948d415b5c7c1478861cdf65a40295327f456` |
