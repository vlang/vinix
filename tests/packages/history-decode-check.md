# Bounded persistent history decoding

Consumer `trust-history.json` and publisher `.publisher/history.json` now use
the internal `StoredReader`. Both retain format 1, their separate `repositories`
and `indexes` envelopes, complete required floor fields and independently owned
results. Canonical writer bytes and input order are preserved. Reading history
does not authenticate a publisher: syntax-valid retired keys remain representable
for replay protection, while enrollment and signed indexes retain curve/signature
admission.

The reader bounds strings before accepting them, admits at most 4,096 identities
and rejects inputs above 8 MiB before parsing. Counters require canonical unsigned
integers within their declared range, including the full u64 sequence maximum.
Escaped keys are compared after decoding. Unknown, missing, duplicate and escaped
duplicate members, malformed UTF-8/Unicode escapes, trailing data, duplicate
ID/key identities and partial records refuse. Each parser layer retires its own
partial fields and arrays. Duplicate checks borrow existing fields rather than
allocating concatenated identity keys.

Both file readers retire their paths, decoded source text and wrapped decode
errors. A no-follow stack `lstat` treats only `ENOENT` as initial empty history;
other path errors proceed to ordinary-file refusal. Leaf aliases, FIFOs and
non-directory parents cannot silently become an empty history. Missing history
still permits initial publication or authenticated legacy-cache migration. A
malformed present file stays unchanged until trusted bytes are restored.

The pre-change, unwarmed ten-cycle probe retained **583 bytes** for complete
consumer decodes and **185 bytes** for publisher decodes, after retiring results.
Ten truncated-document refusals retained **7,030 bytes in each domain**, after
retiring caller-visible errors. Original source, fixture, generated C, executable
and failing output are retained and pinned.

Expanded probes exposed two additional file-reader lifetimes: 1,000 absent
consumer reads retained 176,000 bytes through this compiler's `os.is_link`
failed-stat error, and wrapped parse failures retained a 16-byte error-interface
box per call. Stack admission and explicit synchronous interface access/cleanup
retire these allocations. A small V reproduction and the raw intermediate
failures are retained. The fixture's transition from a removed alias to a FIFO
was corrected to restore an ordinary file between cases before final reruns.

Final tracking requires zero bytes over 1,000 complete and truncated decodes per
domain; 1,000 empty/growing 64-record cycles; repeated malformed schema, integer,
string and duplicate refusals; full 4,096-record success and 4,097-record refusal;
and 1,000 absent, valid, partial, alias, FIFO and non-directory-parent file reads
per domain. Functional checks also retire one result before reading an independent
second result, preserve canonical bytes and verify retry after restoration.

The maintained history guest suite includes the new decoder and existing schema
fixtures, authenticated legacy-cache migration and signed maintenance recovery.
Host checks also exercise publisher release reservations and malformed-history
CLI recovery. The decoder/file-reader measurements do not claim zero retention
for every service, catalog read, transaction or publisher operation. Production
publisher enrollment, catalog migration, graphical login/display integration and
broader foreign-runtime acceptance remain separate roadmap 14 requirements.

## Recorded results, 2026-10-16

All **32 focused compile/run checks** passed: ten core pairs, one native tracked-allocation pair, two ASan/UBSan pairs including publisher release, four signed CLI/driver checks and two guest-tool builds.

Fresh QEMU TCG guests passed with clean shutdown and seven verified artifact hashes each: AArch64 **86.9 seconds**, x86_64 **86.1 seconds**. These functional deadlines are not performance qualification.

- [baseline regression](results/2026-10-16/history-decode-baseline.txt)
- [host results](results/2026-10-16/history-decode-host.json)
- [host summary](results/2026-10-16/history-decode-host.txt)
- [core assertions](results/2026-10-16/history-decode-core.txt)
- [tracked complete history allocations](results/2026-10-16/history-decode-memory.txt)
- [sanitizers](results/2026-10-16/history-decode-asan.txt)
- [signed CLI](results/2026-10-16/history-decode-cli.txt)
- [initial fixture attempt](results/2026-10-16/history-decode-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/history-decode-toolchain.json)
- [aarch64 receipt](results/2026-10-16/history-decode-aarch64.json)
- [aarch64 report](results/2026-10-16/history-decode-aarch64.txt)
- [aarch64 serial](results/2026-10-16/history-decode-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/history-decode-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/history-decode-x86_64.json)
- [x86_64 report](results/2026-10-16/history-decode-x86_64.txt)
- [x86_64 serial](results/2026-10-16/history-decode-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/history-decode-x86_64.qmp.txt)
