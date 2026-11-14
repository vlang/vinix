# Software Metal inline memcpy — 2026-11-14

`ba4493e3afee8fb7d533a6b8ea5e1d54fc68475a` adds bounded
`llvm.memcpy.inline.pD.pS.i32/i64` execution. It shares ordinary copies'
resolved pointer sources, literal lengths, false volatility, bounds,
permissions, alignment, disjoint-range preflight and reusable scratch.
Nonempty destinations use spaces 0/1 and sources use 0/1/2; zero length also
permits readonly space-2 destinations and empty bindings while retaining
alignment requirements. Each copy costs its instruction plus two steps per byte.

The [LLVM inline-copy contract](https://llvm.org/docs/LangRef.html#llvm-memcpy-inline-intrinsic)
requires non-overlapping memory and guarantees no external function calls.
The interpreter uses indexed byte transfers without invoking declarations or
host copy routines. Actual backing ranges, including identical nonempty ranges,
reject overlap before any instruction, even for later/inactive copies.

Inline declarations additionally admit an optional third-parameter length
immarg. Both immarg slots have independent duplicate checks; canonical pointer
noalias/access/captures(none) and argmem effects retain bounded validation.
Ordinary and inline overloads have distinct fixed declaration-cache slots,
allowing both in one function. No owned profile or execution array is added.
Inline memset, atomic variants and other prior exclusions remain unsupported.

Sanitized `tests/ios/air-memory-memcpy.v ASSEMBLER FRESH_OUTPUT inline`
passes 26,002 native LLVM comparisons and 16,320 overlap rejections before
stores. It covers 240 functions, ten lengths through 257, both length widths,
all admitted nonempty space pairs, pointer-control chains, borrowed aliases,
adjacent ranges and eighteen direct zero bodies. Two mixed ordinary/inline
sequences in opposite call orders each execute 59 steps and verify scratch
refresh from earlier output. All 8,640 metadata, 243 budget, 720 binding and
72 rejection/condition controls pass. An exact 499,999-byte interpreter copy
executes one million steps; short/cumulative/mixed budgets reject.

Twelve additional decoded-call controls retarget verified ordinary guards to
matching inline declarations and reject poison/undef, negative/oversized and
runtime lengths before marker stores. They check literal/budget errors, with
runtime values rejected by the existing constant-index guard. These mutations
are interpreter checks, not additional native comparisons. The full LLVM
module is verified; rejection-only and large inline budget bodies are omitted
from native compilation, and `native-input.bc` is retained.

The alignment checker's trailing `inline` mode passes 16,169 native comparisons,
779 alignment controls, 252 budgets and six guards, including cache collisions,
zero readonly bindings and declarations without length immarg. Its normal mode
also passes. Ordinary memcpy, memmove and memset regressions pass 25,970,
42,546 and 90,130 comparisons respectively: 216,986 across six reference runs.
Five memory-attribute groups and four scalar-intrinsic groups pass, including
327,680 square-root inequalities. Former inline-copy exclusions now use i16.

All 24 software Metal groups pass in both Swift hash modes. Ordinary and new
inline-copy kernels each exercise five deferred copies over separate buffers
and disjoint/adjacent aliases, inputs populated after encoding, retained
resources and untouched bytes. Partial-overlap and identical-range commands
fail before marker stores. Both drained runtimes pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-inline-copy-validation-20261114-r1.tar.zst`

The 192 MiB bundle retains binaries, generated fixtures/results, build receipts,
compiler snapshots, generated host C, LLVM headers, identities and source.tar
pinned to the feature revision. Preliminary helper compilation and checker
error-classification failures remain recorded. Qualification uses the
`*-verified` binaries and `software` host. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A completed fresh extraction replaced the bundle path. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matches all bytes, sizes,
types, modes and link targets, including the root; selected identities match.
All ten restored runs pass: six references, two unit binaries and both host
hash modes using separate output roots. Full inventory and archive checksum
match after replay. A fresh replay-archive extraction matches its complete
inventory. Original expanded bundle and replay trees remain preserved.

Standalone compiler capture followed builds; the harness captured its compiler
before generation. SDKs, assembler, external library symlinks and dylibs remain
unsealed prerequisites. Native MCJIT code is not sanitizer instrumented. Leak
detection is disabled; retained heap was not measured. The ordinary runner was
not rebuilt. This remains single-thread CPU execution of synthetic LLVM fixtures.
No Apple-produced shader, GPU rendering, presentation, Vinix guest, Fortnite
frame or launch gate is newly verified. Integrity checks do not replace
historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `95531b5f84aad45ee95316a85889239e54207ffb498e6aa9a849033bf8c3059f` |
| `.inventory.json` | `9cd628385e944716d6a822cafedc12834360bfb3b4cb188943d1538e0594078a` |
| `.replay.tar.zst` | `8a9eda3b5210df4f6953bf020281cfb6121e8cbbc3e04478c1f35376a950e426` |
| `.replay-inventory.json` | `f6ffb10512b4c86fe9ea537f52766e0f2b10433c3b650ddb30a494873cd96004` |
| `source.tar`, revision `ba4493e3a` | `b954e6d5956193094dc69d47f2b10ea3b6d4772672307ffcf4038126c7bcb4ad` |
