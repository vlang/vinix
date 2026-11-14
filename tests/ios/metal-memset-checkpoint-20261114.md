# Software Metal bounded memset — 2026-11-14

`0ccd57ce1` implements nonvolatile `llvm.memset.p0/p1.i32/i64` in bounded AIR
memory execution and opt-in software Metal compute. Calls require an exact
ordinary void declaration, i8 byte, defined literal length and literal false
volatility flag. Destinations resolve through the existing argument/GEP/PHI/
select/freeze/bitcast profile. Preflight derives the full destination extent
and write permission before any store. Nonempty space-2 writes reject.

Each call costs one instruction step plus one per byte. Static budgets sum
all lengths across every block/call and must fit the million-step limit.
Execution reads a nonempty fill's byte once, rejecting poison/undef before that
fill writes while retaining earlier stores. Untaken fills do not read the byte.
Zero length skips byte evaluation and adds no write requirement, including for
empty readonly space-2 bindings. This follows the no-op rule in the
[LLVM memset semantics](https://llvm.org/docs/LangRef.html#llvm-memset-intrinsics).
Literal pointer destinations still reject, including at zero length; existing
GEP extents and preceding instruction errors still apply.

The shared bounded attribute scanner accepts canonical destination writeonly,
nocapture/captures(none), fourth-parameter immarg and memory(argmem: write)
encodings 0/1/2. Unsupported declaration properties and call-site attributes
reject. Exact names use static strings. Execution uses indexed byte writes;
it adds no fill buffer or owned array and invokes no host memset. Scalar/void
intrinsic policies retain their existing profiles.

ASan/UBSan `tests/ios/air-memory-memset.v` passes 90,130 native LLVM comparisons
across 88 main functions and 18 zero-length bodies. It checks all 256 byte
values, eleven lengths from zero through 257, i32/i64 overloads, spaces 0/1,
GEP and pointer-control chains, source/destination aliases, binding offsets,
sentinels and zero-length poison/undef bytes. Empty readonly space-2 zero fills
pass. Main bounds are length + 6 for straight bodies and length + 16 for
branched bodies; executed costs are length + 6 and length + 14 respectively.

All 3,168 metadata/type controls, 90 budget controls, 264 binding/permission
controls and 39 rejection/condition bodies pass. Rejections cover dynamic,
poison, undef, negative or excessive lengths; volatile fills; literal pointers;
extent overflow; space-2 writes; tail/call attributes; inline and user calls.
Four dynamic poison/undef byte bodies check fills with/without earlier stores.
Frozen bytes and untaken poison fills pass separately. A 999,998-byte direct
fill executes exactly one million steps; a short budget and two cumulative
500,000-byte fills reject before writes. These large and rejection controls
are interpreter checks, not additional native comparisons.

Sanitized regressions pass 2,178 pointer comparisons and 917,952 rounding
comparisons with their controls. The new attribute unit and all four scalar
intrinsic unit groups pass, including 327,680 integer square-root inequalities.
All 24 software Metal groups pass under both Swift hash modes. Three deferred
fills use byte values 0/127/255 loaded after encoding, retain resources until
commit, fill exact 16-byte ranges and preserve their eight-byte prefixes in
both drained runtimes. The fixture now derives kernel metadata counts from
the name list so adding a kernel preserves existing entries.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-memset-validation-20261114-r1.tar.zst`

The 498 MiB bundle retains final/preliminary binaries, generated fixtures,
results, build logs, compiler snapshots, harness-generated C, LLVM headers,
selected identities and source.tar pinned to the feature revision. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`. Inventory/checksum receipts
and the replay archive use the same external prefix. Preliminary attribute,
native checker symbol/name and hardcoded runtime-metadata failures remain;
qualification uses the `*-verified` binaries and `software-verified` host.

An initial restore check ran before extraction completed and failed on
incomplete data. Its logs and split trees remain in `incomplete-bundle` and
`restore-incomplete`. A fresh extraction completed before replacing the bundle
path. The unchanged maintained `tests/packages/wine-workspace-archive.v`
checker matches every file byte, size, type, mode and link target, including
the root; selected identities match. All seven restored runs pass: three
reference suites, two unit binaries and both runtime hash modes with separate
output roots. Complete bundle inventory and archive checksum match after
replay. A fresh replay-archive extraction matches its complete inventory.
Original bundle/replay trees remain alongside restored evidence.

The standalone compiler snapshot was saved after builds; harnesses captured
their compilers before generation. External SDKs, assembler, library symlinks
and dylibs remain unsealed prerequisites. Native MCJIT code is not sanitizer
instrumented. Leak detection is disabled; retained heap was not measured.
The ordinary runner was not rebuilt. This remains single-thread CPU execution
of synthetic valid LLVM fixtures. No Apple-produced shader, GPU rendering,
presentation, Vinix guest, Fortnite frame or launch gate is newly verified.
Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `4d15526a8269b783c4fc7a2b787f52f3e730be2415cce3c1a5b5ada5a91c108e` |
| `.inventory.json` | `443909810e8a4dab72590d960846e7f318fde8dba849e30a693c44a14cebe2f2` |
| `.replay.tar.zst` | `5f6ee30f31407a62d85719147add483e60614baab0def143f2053a3b89506cdf` |
| `.replay-inventory.json` | `ce20714cba656cd306125954b53987e9160f7343ebe057c56a49d797285d49b7` |
| `source.tar`, revision `0ccd57ce1` | `9c842e1cd9263150b650c173b618a5d4280b5dd185678a5bac6b1c15bc1ff774` |
