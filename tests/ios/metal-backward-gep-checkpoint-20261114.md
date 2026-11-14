# Software Metal backward scalar GEPs — 2026-11-14

`3119f57ba` adds bounded negative constant indexes to AIR buffer execution and
opt-in software Metal compute. A single index into an i1..i64, half or float
element may subtract from an earlier GEP's proven offset, staying at or above
the binding's logical base. Unsigned magnitude calculation handles the signed
minimum without host signed overflow; division checks the scaled subtraction
before multiplication. Pointer/index widths remain 64 bits and offsets remain
bounded by 64 MiB. Buffer binding offsets supply no extra subtraction headroom.

Plain, nusw and inbounds forms, including historical inbounds flag 1, are
supported. Any nuw bit on a negative GEP rejects conservatively. Negative
aggregate/multi-index paths, dynamic, poison/undef and wider indexes still
reject. Every earlier intermediate retains its extent requirement, even when
the final pointer is lower. Existing alignment, permissions, instruction
budgets and preflight-before-stores rules apply. No ownership or runtime value
representation changed. This checkpoint also updates capability documentation
and its corresponding source comment; executed code is pinned to the feature
revision above.

Normal and ASan/UBSan `tests/ios/air-memory-backward-gep.v` runs each pass
93,840 native LLVM comparisons across 2,760 functions. They cover every
supported element width, every i1..i64 index width, two bounded distances,
plain/nusw/inbounds flags, aliases and historical inbounds with forward
intermediates exactly one-past the bound views. Native inputs use canonical
narrow-integer padding; comparisons mask unused native output padding.
All 27,600 nuw/unknown-flag controls, 2,760 conservative-budget controls,
8,280 extent/writability controls and 18 additional profile/layout/underflow/
alignment guards reject before an earlier store. Guard functions are never
executed natively.

Sanitized regressions pass 59,520 native forward GEP comparisons, all existing
GEP controls, 144,320 native branch/PHI comparisons and their metadata/type/
budget/poison controls. All three GEP layout unit groups pass. All 24 software
Metal groups pass with normal and deterministic Swift hashing. The new deferred
kernel advances three pointers then subtracts using inbounds, nusw and plain
forms at mixed index widths. It checks sparse binding offsets, derived bounds,
the unchanged output sentinel until commit and the exact sum afterward, in
both drained runtimes.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-backward-gep-validation-20261114-r1.tar.zst`

The 200 MiB bundle contains binaries, build receipts, fixtures/results,
compiler snapshots, harness-generated C, LLVM headers, selected identities and
source.tar pinned to the feature revision. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`. Inventory receipts and replay
evidence use the same prefix outside Git. Original expanded evidence remains.

A fresh extraction replaced the original bundle path while retaining
`original-bundle`. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matched every file byte,
size, type, mode and link target, including the root. Selected identities also
match. All seven restored runs pass: normal and sanitized backward references,
sanitized forward GEP and branch/PHI references, sanitized GEP layout units,
and both software Metal hashing modes. The full bundle inventory and archive
checksum still match after replay. The complete replay archive also matches
its own inventory after a fresh extraction; both replay trees remain.

The standalone compiler snapshot was saved after builds; the harness captured
its compiler before generation. External SDKs, assembler, library symlinks and
dylibs remain unsealed prerequisites. Native MCJIT code is not sanitizer
instrumented. Leak detection is disabled; retained heap was not measured.
The ordinary runner was not rebuilt. This remains single-thread CPU execution
of synthetic valid LLVM fixtures. No Apple-produced shader, GPU rendering,
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `2338f56e1fedbad2dcdef29a46a152b5b4fb0e9cb71976a8439750fbc8c007ff` |
| `.inventory.json` | `51775681fc6e7ab7a25e2125a62e79c458af77b100d69d17f45f4fdb5183bd62` |
| `.replay.tar.zst` | `1539aa12d7826c1b143fcc6c9df8ef9e48f554948a638d146cda06e24f0ac085` |
| `.replay-inventory.json` | `58ea62130fa498cd300a8d9199832c8af20e3343752e3b1a942b9d129b9c5d3f` |
| `source.tar`, revision `3119f57ba` | `1f95d724367469c5d5d14706aa9de4f18fe85321fc374f2507c37dc8c40285d1` |
