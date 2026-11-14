# Software Metal disjoint memcpy — 2026-11-14

`1414f1f38` adds nonvolatile constant-length `llvm.memcpy.pD.pS.i32/i64`
to bounded AIR memory execution and opt-in software Metal compute. It shares
the move signature checks, resolved pointer sources, full read/write extents,
permissions, reusable per-run scratch and instruction + two-steps-per-byte
budget. Nonempty destinations use spaces 0/1 and sources use 0/1/2; zero length
adds no access requirement, including empty readonly space-2 bindings.

This bounded memcpy profile requires disjoint actual byte ranges. Partial
overlap and identical nonempty ranges reject before any instruction executes,
including when a later copy or an inactive block overlaps. All binding and
budget checks precede the overlap scan. The executor compares borrowed
backing-array addresses only for this guard, so differing virtual arguments or
sliced views cannot conceal shared storage. Address bits never enter AIR
value slots or become accepted numeric pointer inputs. Copies use indexed
reads/writes and existing scratch storage; no host memcpy call or new owned
array is added. Binding/data stability remains a caller precondition.

The [LLVM memcpy definition](https://llvm.org/docs/LangRef.html#llvm-memcpy-intrinsic)
permits equal or non-overlapping ranges; this implementation deliberately
accepts the disjoint subset for nonempty copies. Memmove retains its overlap
and identical-range support. Zero-length memcpy skips the overlap guard.
Canonical pointer noalias declaration attributes are admitted only for memcpy;
memmove still rejects them. Other declaration/call attributes, volatility,
dynamic/indeterminate lengths, literal pointers, unsupported integer widths
and inline/atomic variants retain their exclusions.

ASan/UBSan `tests/ios/air-memory-memcpy.v` passes 25,970 native LLVM
comparisons and 16,320 overlap rejections before an earlier marker store.
It covers 240 main functions, 18 direct zero bodies and a two-copy sequence:
ten lengths from zero through 257, i32/i64, every supported nonempty space
pair, pointer-control chains, nonperiodic source bytes, disjoint/adjacent aliases
and borrowed slices with different data heads. Overlapping and identical
nonempty inputs never execute natively. The sequence copies 17 bytes, then
copies nine bytes from a shifted part of that output to a disjoint range,
checking scratch refresh and reuse. It executes 59 steps.

Straight bodies have a length * 2 + 7 bound and execute that cost; branched
bodies have a length * 2 + 21 bound and execute length * 2 + 18. All 8,640
metadata/type controls, 243 budget controls and 720 binding/permission controls
pass. The 72 guard/condition bodies include unsupported shapes/lengths,
pointer-select poison/undef, and late/inactive overlapping copies. Frozen
conditions and untaken poison selects with disjoint copies pass separately.
A 499,999-byte direct copy executes exactly one million steps; short,
cumulative and mixed fill/copy budgets reject before stores. Large and
rejection controls are interpreter checks, not additional native comparisons.
The complete LLVM module is verified; rejection-only guard/condition bodies
are excluded from MCJIT compilation and `native-input.bc` is retained.

Sanitized regressions pass 42,546 memmove and 90,130 memset native comparisons
with their controls. The maintained move checker's former memcpy exclusion
now uses the unsupported i16 overload, preserving its 70 guard/condition
bodies. All three memory-attribute and four scalar-intrinsic unit groups pass,
including 327,680 integer square-root inequalities.

All 24 software Metal groups pass under both Swift hash modes. Five deferred
copies cover separate buffers, disjoint aliases and adjacent ranges, with data
populated after encoding, retained resources and preserved bytes. Two failed
commands cover partial overlap and identical ranges; neither executes the
kernel's earlier marker store. Both drained runtimes pass. An initial host
generation failed on a local variable name collision; the corrected final
host is qualified and the failed build receipt remains.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-memcpy-validation-20261114-r1.tar.zst`

The 211 MiB bundle retains final/preliminary binaries, generated fixtures and
results, build receipts, compiler snapshots, harness-generated C, LLVM headers,
selected identities and source.tar pinned to the feature revision. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`. Inventory/checksum receipts
and replay evidence use the same external prefix. Qualification uses the
`*-verified` standalone binaries and `software-final` host.

A completed fresh extraction replaced the original bundle path. The unchanged
maintained `tests/packages/wine-workspace-archive.v` checker matches every file
byte, size, type, mode and link target, including the root; selected identities
match. All seven restored runs pass: three reference suites, two unit binaries
and both runtime hash modes using separate output roots. Complete bundle
inventory and archive checksum match after replay. A fresh replay-archive
extraction matches its complete inventory. Original expanded bundle and replay
trees remain alongside restored evidence.

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
| Complete `.tar.zst` | `e45d1c92fe62f52550a14ba1a01a784904811ef1ab94e7f719ea041688628ccd` |
| `.inventory.json` | `aa5292af126d30001c52b2fcd73d8f1f1c8ea562536c65c8501366300322462e` |
| `.replay.tar.zst` | `c95dc34250e8224a03ae8ef1438fd9aa085a7fc1ccb42ddbcba80e8bb8d94ecb` |
| `.replay-inventory.json` | `e4d70ec3822b70020bcc66944a78ac2136185aa849d28c5e78eb01b899bbd83a` |
| `source.tar`, revision `1414f1f38` | `e09b0e8124f7a3781a9cd6d374aedfbce5c5b43ead78356bbf341249ca01771d` |
