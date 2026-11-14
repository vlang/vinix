# Software Metal overflow-pair freeze — 2026-11-14

`b3b1f4a24` admits `freeze` on literal unpacked `{iN, i1}` overflow pairs
in bounded AIR buffer kernels and opt-in software Metal compute. Defined
fields retain their bits, each poison field independently chooses zero, and
a direct undef pair chooses two zero fields. Earlier undef computations still
reject. Each freeze costs one step and reuses the scalar validator/evaluator;
repeated uses share the stored result. General aggregate operations retain
their existing restrictions. No numerical algorithm or value layout changed.

The maintained scalar pair-freeze checker reproduced a pre-existing duplicate
validation bug: the profile checked a pair correctly, then rejected it through
the scalar-only unary validator. Skipping that second check fixes whole-program
pair freeze. The failing baseline binary, source revision, original validator,
fixtures and rejection log remain in the bundle.

Normal and ASan/UBSan buffer runs each pass 122,736 defined native freeze and
idempotence comparisons across all six i1..i64 overflow families. Another 3,072
computed poison/undef cases and 768 frozen constant cases pass. All 3,456 freeze
metadata and 384 source-type corruptions reject before preceding stores; the
restored baselines pass. Existing coverage remains: 665,592 exact native
overflow pairs, 531,192 independent widened checks, exhaustive i1..i8 inputs,
offsets, padding, budgets, extraction/cached-call/type corruptions and scalar
choices. Aggregate stores/select/insertion still reject in each of four shards.

The initial enlarged module exceeded the production parser's abbreviation
reference limit. Both failed attempts remain in `failed-parser`, with their
exact checker source in `failed-checker.v` at the bundle root. The final checker
uses four bounded modules and verifies
their aggregate counts without changing parser limits. The intermediate
`sharded-v1` runs passed but printed an empty parent summary after consuming
the string builder twice; final runs retain and print the same summary string.

The sanitized scalar checker passes 524,288 native defined/property comparisons
across 1,152 functions, including partial poison, control flow, repeated uses,
budgets and corruption controls. Pair-freeze units pass 2,048 independent field
states and guards; all 16 integer/mixed unit groups pass. All 24 software Metal
groups pass under normal and deterministic Swift hashing. Each runtime's seven
frozen deferred dispatches preserve 98 exact u64 value/flag words. Two additional dispatches
check literal poison/undef and computed poison; sentinels, released caller
handles, retained snapshots and two-runtime drainage pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-pair-freeze-validation-20261114-r1.tar.zst`

The 266 MiB bundle includes failed/intermediate/final attempts, binaries, all
fixtures and scalar comparisons, generated C, compiler snapshots, LLVM header,
selected identity hashes and source.tar pinned to the feature revision. Decode
with `zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`. Receipts and complete
replay evidence use the same prefix outside Git. Originals are retained.

A fresh extraction replaced the original bundle path while retaining
`original-bundle`. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matched every file byte,
size, type, mode and link target, including the root; selected identities
also match. All five restored suites pass: sanitized buffer references,
scalar references, pair-freeze units, integer/mixed units and all 24 software
Metal groups with normal hashing. The complete bundle inventory and archive
checksum still match after all replays. The `.replay.tar.zst` archive also
matches its own inventory after a fresh extraction; both replay trees remain.
These integrity checks do not replace historical launch auditors.

The standalone compiler snapshot was saved after builds; the harness captured
its compiler before generation. External SDKs, assembler, library symlinks and
dylibs remain unsealed prerequisites. Native MCJIT reference code is not
sanitizer-instrumented; leak detection is disabled and retained heap is not
measured. The ordinary runner was not rebuilt. This is bounded single-thread
CPU execution of synthetic valid LLVM fixtures. No Apple-produced shader,
GPU rendering, presentation, Vinix guest, Fortnite frame or launch gate is
newly verified.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `aa7f2452947a17e7e14dc2106343bfac17c16e4eecb5896918231f179a8833b1` |
| `.inventory.json` | `b27392ddaae861722296c7bd22f76fb32ff79d099bcbcfdc0a2781f7faae47d7` |
| `.replay.tar.zst` | `8423807ee902d21c0ca5b5fb59057d612cdc63aa3174058912547e74f1e36566` |
| `.replay-inventory.json` | `6ea8e4363c19af71c8cb9b9ff30b0ae3d3bf4792d1bcb9f9f0e48913b0d4c6a1` |
| `source.tar`, revision `b3b1f4a24` | `b48c20e1a47e348c508fafbb7e75d688cfd41d121a8c99ba9b10739dfd243667` |
