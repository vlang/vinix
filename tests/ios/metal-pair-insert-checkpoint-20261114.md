# Software Metal overflow-pair insertion — 2026-11-14

`05dcd3f9a` admits unflagged `insertvalue` on literal unpacked `{iN, i1}`
overflow pairs in bounded AIR buffer kernels and opt-in software Metal compute.
One literal index selects field 0 or 1; source/result pair types must match
and the replacement must have the field's exact scalar type. Preflight checks
shape, types, index, source origin and result slot before any stores.

Insertion changes only the chosen field and its poison tag. Defined scalars
repair that field; replacing both repairs the pair. Poison replacements leave
the neighbor intact. Zero/poison base constants are supported; undef bases
reject in preflight and undef replacements reject dynamically, even if ignored
or subsequently overwritten. Each insertion costs one step. The scalar and
buffer interpreters now share the same insertion reader/evaluator. Arithmetic,
the 16-byte value format and ownership remain unchanged. General aggregates,
nested paths, aggregate memory, arguments and returns remain unsupported.

Normal and ASan/UBSan runs of `tests/ios/air-memory-pair-insert.v` each pass
245,760 exact native value/flag pairs across all six i1..i64 overflow families
and both replacement fields. Every function checks a 12x12 edge matrix plus
16 mixed pairs with two replacement variants, neighboring fields, offsets,
padding and exact 12-step execution. The interpreter receives unmasked
replacement bytes; native references receive canonical bytes to exclude
unspecified padding. Native target/layout receipts are retained; MCJIT uses
optimization level 2 and FastISel off. Guard functions are not called natively.

All 9,216 insertion metadata/index, 1,536 operand-type and 768 short-budget
controls reject before an earlier store; restored baselines pass. Another
4,608 zero/poison/undef cases check chosen and untouched fields, pair freeze
and full repair: 3,072 expected rejections and 1,536 defined choices pass with
sentinels intact. These include undef replacements that a later operation
would overwrite or ignore.

The shared helper passes the sanitized scalar insertion checker: 786,432
native comparisons across 768 functions, including 12,288 boundary results,
both fields, repair, partial poison through select/parallel loop PHIs, budgets,
metadata and corruption controls. Units pass 2,048 field/poison states and
shape/type/index/scope guards. Sanitized overflow regressions pass 665,592
native pairs, 531,192 independent widened checks, 122,736 defined pair-freeze
checks and their existing controls. Aggregate stores still reject in each
shard; the prior complete checkpoint retains the former insertion exclusion.

All 24 software Metal groups pass under normal and deterministic Swift hashing.
Each runtime checks seven inserted deferred dispatches through 98 exact u64
words, replacing either field while retaining the neighbor. Four additional
dispatches each check 18 words, including partial repair, partial poison through
select/freeze, full repair and poisoning one repaired field. Caller handles
release before commit, sentinels persist until commit, and retained snapshots
and two-runtime drainage pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-pair-insert-validation-20261114-r1.tar.zst`

The 269 MiB bundle includes binaries, fixtures/results, all scalar comparison
rows, generated C, compiler snapshots, LLVM header, selected identity hashes
and source.tar pinned to the feature revision. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`. Receipts and replay evidence
use the same prefix outside Git. Original expanded evidence is retained.

A fresh extraction replaced the original bundle path while retaining
`original-bundle`. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matched every file byte,
size, type, mode and link target, including the root; selected identity hashes
also match. All five restored suites pass: sanitized buffer insertion,
scalar insertion, overflow/freeze regressions, insertion units and all 24
software Metal groups with normal hashing. The complete bundle inventory
and archive checksum still match after replay. The replay archive also matches
its own inventory after a fresh extraction; both replay trees remain.

The standalone compiler snapshot was saved after builds; the harness captured
its compiler before generation. External SDKs, assembler, library symlinks and
dylibs remain unsealed prerequisites. Native MCJIT code is not sanitizer
instrumented. Leak detection is disabled; retained heap was not measured.
The ordinary runner was not rebuilt. This remains bounded single-thread CPU
execution of synthetic valid LLVM fixtures. No Apple-produced shader, GPU
rendering, presentation, Vinix guest, Fortnite frame or launch gate is newly
verified. Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `3cbfdb66bcf4c8454273e6c44a813b9780a0182e1d4c99bd57d11d89f2107493` |
| `.inventory.json` | `bcc255a850f3a9161514d551da88dfa56b70619827c3ee24c4cca2d0f6bfe525` |
| `.replay.tar.zst` | `e47c284517b2cce00dd8c987fe8346a179ebf704e5964b7f3d5606b3ff21c2ae` |
| `.replay-inventory.json` | `2146e72d981cb13e8ef3fcc202b273c810a0840b491fa36aa3c0c211fcd59dbb` |
| `source.tar`, revision `05dcd3f9a` | `755ce5ef87f722521c9c7109d5b5cc9a85f17a6a9c5c2a3b08a6b434c72a933d` |
