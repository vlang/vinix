# Bounded cached snapshot decoding

Cached `catalog.json` wrappers now use the internal `StoredReader`. The array
shape, complete repository/text/signature fields, input order and canonical writer
bytes remain unchanged. The decoder only admits the wrapper: signature, publisher
curve, expiry, signed-index shape and replay-floor admission remain with existing
authentication callers. Syntax-valid retired keys and legacy signature whitespace
stay representable for recovery.

The decoder bounds strings while reading, limits inventories to 4,096 records
and refuses encoded input above 8 MiB before parsing. It rejects missing, unknown,
duplicate and escaped duplicate fields, wrong value types, malformed UTF-8 and
Unicode escapes, invalid repository identities, empty text/signatures, oversized
signatures and trailing data. Snapshot text stays opaque, including JSON-looking
content, Unicode, escaped controls and NUL bytes. It is never reserialized before
authentication. Successfully returned snapshots own all fields; each parser
layer releases partial fields and arrays on refusal. Duplicate ID checks borrow
existing records instead of allocating identity-map storage.

`read_snapshots` releases source text, its path and wrapped decode errors. A
no-follow stack `lstat` treats only `ENOENT` as an initial empty cache, avoiding
the compiler's failed `os.is_link` stat-error lifetime. Aliases, FIFOs and
non-directory parents refuse. Present malformed files retain their exact bytes;
restoring valid metadata permits retry. The read never initializes package state.
The existing cached-metadata diagnostic prefix is preserved.

The pre-change unwarmed probe retained **806 bytes** across ten complete decodes
and **7,280 bytes** across ten truncated-document refusals, after retiring returned
records and caller-visible errors. Original source, fixture, executable, generated
C and failing output are retained and pinned. The initial bounded-parser probe
and expanded allocation fixture passed before the final focused checks.

Native tracking requires zero retained bytes across 1,000 complete/truncated
decodes, 1,000 empty and growing 64-record cycles, repeated schema/string/duplicate
refusals and 1,000 absent, valid, partial, alias, FIFO and non-directory-parent
file reads. Exact 8 MiB and limit-minus-one inputs preserve their full text with
zero retained parser scratch; limit-plus-one refuses before parsing. Functional
ownership checks retire the source buffer and one independent result before
using the second result, then compare exact canonical output.

Full 4,096-record success and 4,097-record refusal run outside the 16,384-live-record
heap tracker: their five owned strings per record legitimately exceed its table.
Those cases still run natively, under ASan/UBSan and in both guest architectures.
The maintained cache-preflight suite now includes the decoder and existing schema
fixtures alongside exact writer limits, signed maintenance, migration/replay
refusal and restored service recovery.

The signed CLI lifecycle and authenticated catalog sanitizer checks cover callers
whose wrapper scratch now retires earlier. These scoped decoder/file-reader
measurements do not qualify zero retention for every catalog, administrative
observation, transaction or publisher path. Roadmap 14 still requires production
publisher enrollment, catalog migration, graphical login/display integration and
broader foreign-runtime acceptance.

## Recorded results, 2026-10-16

All **32 focused compile/run checks** passed: ten core pairs, one native tracked-allocation pair, two ASan/UBSan pairs including authenticated catalog lifetimes, four signed CLI/driver checks and two guest-tool builds.

Fresh QEMU TCG guests passed with clean shutdown and seven verified artifact hashes each: AArch64 **63.1 seconds**, x86_64 **37.7 seconds**. These functional deadlines are not performance qualification.

- [baseline regression](results/2026-10-16/snapshot-decode-baseline.txt)
- [host results](results/2026-10-16/snapshot-decode-host.json)
- [host summary](results/2026-10-16/snapshot-decode-host.txt)
- [core assertions](results/2026-10-16/snapshot-decode-core.txt)
- [tracked complete snapshot allocations](results/2026-10-16/snapshot-decode-memory.txt)
- [sanitizers](results/2026-10-16/snapshot-decode-asan.txt)
- [signed CLI](results/2026-10-16/snapshot-decode-cli.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/snapshot-decode-toolchain.json)
- [aarch64 receipt](results/2026-10-16/snapshot-decode-aarch64.json)
- [aarch64 report](results/2026-10-16/snapshot-decode-aarch64.txt)
- [aarch64 serial](results/2026-10-16/snapshot-decode-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/snapshot-decode-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/snapshot-decode-x86_64.json)
- [x86_64 report](results/2026-10-16/snapshot-decode-x86_64.txt)
- [x86_64 serial](results/2026-10-16/snapshot-decode-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/snapshot-decode-x86_64.qmp.txt)
