# Software Metal overflow-pair select — 2026-11-14

`118c8b953` admits unflagged selects of literal unpacked `{iN, i1}` overflow
pairs in bounded AIR buffer kernels and opt-in software Metal compute. Arms
and result must have exactly matching pair types; the condition must be scalar
i1. Preflight rejects indices, malformed shapes/types, flags and unsupported
pair constants before any stores. The existing scalar validator and evaluator
provide selection without changing arithmetic or the 16-byte value layout.

Only the chosen pair is read. Both fields and poison tags survive selection;
a poison condition poisons both fields, and a subsequent pair freeze makes
fixed zero choices. Zero/poison pair constants are supported. Undef pair
constants in either arm reject during preflight, including unchosen arms.
Undef conditions and earlier dynamic errors still reject. Each select costs
one step; aggregate stores, insertion, arguments and returns remain excluded.

Normal and ASan/UBSan runs of `tests/ios/air-memory-pair-select.v` each pass
122,880 exact native value/flag comparisons across all 384 overloads of six
i1..i64 overflow families. Both condition values select independently computed
pairs, including reversed subtraction operands. Every overload checks a 12x12
edge matrix and 16 mixed pairs, offsets, padding and an exact 13-step budget.
All 3,456 metadata, 1,152 operand-type and 384 short-budget controls reject
before an earlier store; restored metadata baselines pass. Another 2,624
constant/poison/undef/freeze/earlier-error cases yield 1,792 expected rejections
and 832 defined choices, with sentinels intact.

The initial native references received noncanonical i1 bytes. A diagnostic
recorded native selection differing for byte 0xfe, despite its low bit being
zero. Final references use canonical condition bytes while the interpreter
continues to check explicit low-bit masking with 0xfe/0xff. Failed binaries,
exact checker sources, fixtures and logs remain in `failed-native-condition`
and the bundle root. Native target/layout receipts are retained. Native guard
functions are not executed; MCJIT uses optimization level 2 and FastISel off.

Sanitized regressions pass 665,592 native overflow pairs, 531,192 independent
widened checks, 122,736 defined pair-freeze checks and all existing corruption,
poison/undef, choice and constant controls. The updated exclusion fixtures
retain aggregate store/insertion rejection in every shard; the prior complete
checkpoint preserves the historical select rejection fixture. The scalar
select suite passes 86,016 comparisons across 672 functions and 11 guards;
pair-flow units pass shape/type/scope, tags, availability and layout checks.

All 24 software Metal groups pass with normal and deterministic Swift hashing.
Each runtime checks seven selected deferred dispatches through 98 exact u64
value/flag words, both comparison outcomes and zero arms. Three additional
dispatches each check ten zero words, including unchosen poison and frozen
poison conditions. Sentinels persist until commit, caller pipeline/buffer
handles release before commit, and snapshots and two-runtime drainage pass.

Complete archive:

`/Users/alex/Library/Caches/vinix-ios/air-memory-pair-select-validation-20261114-r1.tar.zst`

The 208 MiB bundle contains failed and successful attempts, binaries, fixtures,
results, generated C, compiler snapshots, LLVM header, selected identity hashes
and source.tar pinned to the feature revision. Decode with
`zstd -dc ARCHIVE | tar -xf - -C FRESH_DIRECTORY`. Receipts and replay artifacts
use the same prefix outside Git; original expanded evidence is retained.

A fresh extraction replaced the original bundle path while retaining
`original-bundle`. The unchanged maintained
`tests/packages/wine-workspace-archive.v` checker matched every file byte,
size, type, mode and link target, including the root; selected identity hashes
also match. All five restored suites pass: sanitized pair-select references,
overflow/freeze regressions, scalar-select references, pair-flow units and all
24 software Metal groups with normal hashing. The complete bundle inventory
and archive checksum still match after replay. The replay archive also matches
its own inventory after a fresh extraction; both replay trees remain.

The standalone compiler snapshot was saved after builds; the harness captured
its compiler before generation. External SDKs, assembler, library symlinks and
dylibs remain unsealed prerequisites. Native MCJIT code is not sanitizer
instrumented. Leak detection is disabled; retained heap was not measured.
The ordinary runner was not rebuilt. This is bounded single-thread CPU
execution of synthetic valid LLVM fixtures. No Apple-produced shader, GPU
rendering, presentation, Vinix guest, Fortnite frame or launch gate is newly
verified. Integrity checks do not replace historical launch auditors.

| Artifact | SHA-256 |
| --- | --- |
| Complete `.tar.zst` | `fa9a78be99ed3f19497231718a6ba64b1166d2382349edecdfbce40f173f5a1d` |
| `.inventory.json` | `01794cc6a7b56e0d6a100711f4f27ab7ad76459fe6a4391656a0dc547514365a` |
| `.replay.tar.zst` | `4e8e26e2b3c413e5e61513e7ff560b167cbc07e92483471a656ba2696c16b1e4` |
| `.replay-inventory.json` | `c88ed4c53d97e3a4796b2b098d196aadc96befddd3c03749e77df3b20bb298c0` |
| `source.tar`, revision `118c8b953` | `cfe3067ac934c83d4364b9c823b59c6d45fd84cc2405b5c3957ab1f101b0ba1b` |
