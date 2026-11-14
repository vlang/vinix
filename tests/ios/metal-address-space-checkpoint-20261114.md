# Software Metal pointer address-space casts — 2026-11-14

`75a9a762ccb43a6fe476777049c2f6b2437f34dc` admits scalar pointer
`addrspacecast` between all six distinct space-0/1/2 pairs in the interpreter's
flat virtual target. Casts preserve binding identity and byte offset, resolve
during preflight and cost one executed step without entering scalar value slots
or constructing host pointers. Results feed existing GEP, PHI/select,
freeze/bitcast, comparison, scalar-access and memory-intrinsic paths.

Both pointer types must have 64-bit pointer and index widths in an explicit
supported little-endian layout. Missing, narrower/wider, non-integral and
unsupported layouts reject, as do flags, literal/vector pointers, same-space
casts and other spaces. The existing per-profile layout table is reused and
freed after preflight; no owned cached-profile or execution array is added.
The [LLVM definition](https://llvm.org/docs/LangRef.html#addrspacecast-to-instruction)
makes conversion support target-dependent. Flat identity conversion here is
an explicit virtual-target policy, not a claim about arbitrary GPU targets.

Original argument bounds, alignment and permissions remain in force. A
space-2 argument cannot acquire write access by conversion to another space.
Nonempty scalar and intrinsic writes through a space-2 view also reject,
including when the original argument is writable. Returning a writable argument
to a writable view preserves its original permission. Zero-length intrinsics
add no access requirement. All blocks are checked before stores, including
inactive writes; converted aliased bindings retain distinct identities.

Sanitized `tests/ios/air-memory-address-space.v` passes 76,116 native LLVM
comparisons. Its 1,584 main functions cover i1..i64, half/float, all six source
cast directions, output spaces 0/1, round trips and pointer-flow chains, with
nonperiodic inputs, shifted and aliased bindings. Straight bodies execute 12
steps; chained bodies have a conservative 28-step bound and execute 25.
All 42,768 metadata, 1,585 budget and 5,280 binding controls pass before stores.

The 47 guard bodies cover readonly writes through converted arguments/views,
scalar stores and all five memory-intrinsic variants, literal pointers,
vectors, unsupported spaces, inactive writes and cross-binding select/compare.
Twenty zero operations pass with empty readonly bindings. Ten layout controls
use a cast-only prefix, ensuring validation without relying on a GEP to parse
the layout. A three-cast read probe and a nonempty inline-fill/inline-copy/
overlapping-move sequence also match native LLVM. The sequence executes exactly
85 steps and rejects a short budget before its fill writes. The complete LLVM
module is verified; guards are excluded from native compilation and the
projected `native-input.bc` is retained. Invalid cases never execute natively.

Sanitized regressions pass 54,712 pointer-identity, 2,178 pointer-comparison,
90,130/90,642 ordinary/inline fill, 25,970/26,002 ordinary/inline copy and
42,546 move comparisons: 408,296 across eight reference runs. The identity
checker's former address-space exclusion now targets unsupported space 3.
Six memory-attribute and four scalar-intrinsic groups pass, including 327,680
square-root inequalities.

All 24 software Metal groups pass in both Swift hash modes. A deferred sum
kernel exercises all six cast directions with shifted bindings, derived bounds,
inputs changed after encoding and preserved output bytes. Pipelines reject
writes through converted constant arguments and constant views. Both drained
runtimes pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-address-space-validation-20261114-r1.tar.zst`

The 213 MiB bundle retains binaries, generated fixtures/results, build receipts,
compiler snapshots, generated host C, LLVM headers, selected identities and
source.tar pinned to the feature revision. Preliminary lookup and checker
compilation failures remain recorded. The cast qualification binary is
`address-space-qualified-final`; regression binaries use their plain names.
The host is `software/NotificationChecks.app/Contents/MacOS/center-host`.
Decode with `zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`.

A completed fresh extraction replaced the bundle path. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matches complete bytes, sizes,
types, modes and link targets, including the root; selected identities match.
All twelve restored runs pass: eight references, two unit binaries and both
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
| Complete `.tar.zst` | `37502d950485463e8fa914747745f1d1c0b225a9546bfb5c4b55cf819100bda9` |
| `.inventory.json` | `6986257a285aca3f837d342db1a8f57fe9c74b078c646b2d040cbbd1e6df213c` |
| `.replay.tar.zst` | `c8df0e7964fd15b100db43dddf3a9d3aea16f07e2e94038b4540724920dc33b9` |
| `.replay-inventory.json` | `27340ffaec5e86ce56b45a31e6f144f4297a57d16ca9aca01eaf2b1acc0ab8f7` |
| `source.tar`, revision `75a9a762c` | `bc2ceaa18e81514028e6609f1e90b0ca559e1e362faacc1de6622a38fefbeca7` |
