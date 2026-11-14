# Software Metal inline memset — 2026-11-14

`317e070dde98f940019683cdcd0e1c511d45588f` adds bounded
`llvm.memset.inline.pD.i32/i64` execution. It shares ordinary fills' runtime
i8 byte, literal length, false volatility, resolved destination, bounds,
alignment, permissions and instruction-plus-one-step-per-byte cost. Nonempty
destinations use spaces 0/1; zero length also permits readonly space-2 and empty
bindings, skips poison/undef byte evaluation, and retains alignment checks.

The [LLVM inline-fill contract](https://llvm.org/docs/LangRef.html#llvm-memset-inline-intrinsic)
guarantees filling without external function calls. The executor uses indexed
byte writes without invoking declarations or host fill routines. Ordinary and
inline fills have distinct fixed declaration-cache slots; inline fills remain
separate from the transfer/scratch path. No owned profile or execution array is
added. Inline declarations may additionally mark length immarg, with independent
length/volatile duplicate checks and the existing cumulative scan-work budget.
Destination writeonly/captures(none) and argmem-write effects retain their
allowlist; source/byte properties, noalias and atomic variants remain excluded.

Sanitized `tests/ios/air-memory-memset.v ASSEMBLER FRESH_OUTPUT inline`
passes 90,642 native LLVM comparisons. Its 88 main functions cover all 256 fill
bytes, eleven lengths through 257, i32/i64, destination spaces 0/1, shifted and
aliased bindings and GEP/PHI/select/freeze/bitcast chains. Eighteen direct zero
bodies cover spaces 0/1/2 and defined/poison/undef bytes. Two mixed ordinary/inline
sequences in opposite call orders overlap their destinations; a complement-byte
second fill overwrites the first. Each executes 34 steps and matches native
LLVM for all 256 input bytes.

All 3,168 metadata, 92 budget, 264 binding and 39 rejection/condition controls
pass. Ten decoded-call controls retarget ordinary guards to matching inline
declarations and reject poison/undef, negative/oversized and runtime lengths
before stores, checking the literal/budget or constant-index error. Poison/undef
nonempty bytes retain earlier marker stores; frozen and inactive bytes pass.
A 999,998-byte interpreter fill executes exactly one million steps; short and
cumulative budgets reject. The full LLVM module is verified. Rejection-only
bodies, and large inline budget bodies, are excluded from native compilation;
the projected `native-input.bc` is now saved in both fill modes. Invalid inputs
and huge budget cases are interpreter controls, not native comparisons.

The alignment checker's `inline` mode now exercises both inline fills and copies
without optional length immarg declarations: 16,169 native comparisons, 779
alignment controls, 252 budgets and six guards pass. Normal alignment also
passes. Ordinary memset, ordinary/inline memcpy and memmove regressions pass
90,130, 25,970/26,002 and 42,546 comparisons, totaling 307,628 across seven
reference runs. Six memory-attribute groups and four scalar-intrinsic groups
pass, including 327,680 square-root inequalities. The former inline-fill
exclusion fixture now uses i16.

All 24 software Metal groups pass in both Swift hash modes. Ordinary and new
inline-fill kernels each execute three deferred aligned fills, checking zero,
0x7f and 0xff bytes, untouched prefixes, offsets, retained resources and inputs
populated after encoding. Both drained runtimes pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-inline-fill-validation-20261114-r1.tar.zst`

The 187 MiB bundle retains all six standalone binaries, generated fixtures and
results, build receipts, compiler snapshots, generated host C, LLVM headers,
selected identities and source.tar pinned to the feature revision. The runtime
host is `software/NotificationChecks.app/Contents/MacOS/center-host`.
Decode with `zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A completed fresh extraction replaced the bundle path. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matches complete bytes, sizes,
types, modes and link targets, including the root; selected identities match.
All eleven restored runs pass: seven references, two unit binaries and both
host hash modes with separate output roots. Full inventory and archive checksum
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
| Complete `.tar.zst` | `ce5bc7d226d19078ec35c3185c171cb9f9162547a46a77b8358a3151b20b4fc4` |
| `.inventory.json` | `5f1f6a90c30aad4fd5db3e84e72f5aa1bdd83d1f491155015c8315c28fce4446` |
| `.replay.tar.zst` | `e03fd4b8f4ef8c96d834803e502fa9ffdb057f83d4dbfebb365659fb9d1c7887` |
| `.replay-inventory.json` | `47c4dfe578f03c7963bbc3ee7cc4c5493a805ab476995fbed7cb62eefad291ec` |
| `source.tar`, revision `317e070dd` | `51175a02d56524d9a99b9022a1024e6bb563fff89e1fe69f5a1a17eff7ddb84e` |
