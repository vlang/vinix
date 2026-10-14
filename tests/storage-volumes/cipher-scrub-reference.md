# Ciphertext scrub/reference binding qualification

`verify-volume-scrub-reference REFERENCE REPORT` binds a saved ciphertext scrub
to the complete supplied reference before displaying historical observations.
See [the contract](../../docs/storage-volumes.md#binding-ciphertext-scrubs-to-checksum-references).

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-cipher-scrub-reference --work /tmp/cipher-binding-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --cipher-scrub-reference --work /tmp/cipher-binding-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --cipher-scrub-reference --work /tmp/cipher-binding-x86
```

The scoped host runs the unchanged encrypted recovery IO model and preceding
ciphertext reference/scrub/history native suites, plus the new actual private
reader/binding/output model and syntax tests under ASan/UBSan. Eight native
sector/MBR-or-GPT/mode profiles exercise clean and changed observations at all
32 digest positions: 512 exact complete outputs checked with standard V SHA.
Every byte mutation of either CRC-protected input refuses binding and preserves
caller geometry and output. Valid unrelated native geometry, modes, identities
and expected digests fail; high signed offsets and explicit size-before-pointer
checks exercise bounds. The preceding CS1 codec tests also repair checksums
after mutations to verify nested reference/fingerprint/result validation.

The standalone actual CLI model covers clean and two changed observations,
private owned inputs, separate hard-linked aliases, held writer locks, exact
read-only/no-follow/nonblocking flags, short/EINTR and EOF EINTR reads,
zero/EIO/oversized/trailing reads, size/stat faults and second-input failures.
It checks ownership and permissions at initial stat and again after EOF, plus
late size/stat failures. Every truncation and protected byte mutation of both
files, appended NUL, missing/symlink/directory/FIFO paths, 0644 inputs and valid
unrelated references/reports refuse findings. All four descriptors remain
pinned at encoder, print, flush and stream-error observers; every return
balances owners. Encoder-boundary refusal, injected print/flush/stream faults
and actual stdout EBADF return operational status 1 even for changed reports.
The encoder refusal does not inject an internal snprintf failure. Established
diagnostics may use stdout; refusals emit no binding header or geometry row.

Each guest runs the unchanged real encrypted scrub setup: RW and RO references,
passphrase/recovery-produced clean/changed reports, a controlled physical
ciphertext corruption restored and flushed, and preceding real-KDF retention
checks. New offline binding verifies all eight report profiles with complete
independent output expectations and persists eight views. Wrong saved mode and
changed privacy refuse findings. Existing history comparisons repeat. Held
directory writer contention does not block binding; complete live RO mapping
status and held decrypted contents remain unchanged. One hundred warmup and
one hundred measured three-command cycles run 600 new utility lifetimes per
architecture without new KDF work; 13-second grace waits precede heap snapshots.
All new views and preceding historical checks repeat after device reordering
and recovery unlock confirms the original ciphertext still decrypts.

The independent oracle imports no production codec. It reconstructs 18 complete
files per guest: two CH1 references, eight CS1 reports and eight bound views.
Restored full ciphertext, simulated corruption, native geometry/reserved fields,
both record CRCs, nested reference equality, result consistency and complete
input fingerprints are independently checked with standard V and OpenSSL SHA.
Complete utility and selected guest C receive allocation audits, and all new
lifetimes receive independent review. Frozen isolated ALLOC_TRACK kernels are
unchanged; no kernel or full desktop matrix completion is claimed.

## Qualification on 2026-10-14

`host-1`, `arm-1` and `x86-1` exit receipts are zero. All selected ASan/UBSan
checks, both full target allocation audits and four guest boots passed. Final
production and selected guest sources stayed unchanged through qualification.

| Guest | Warmup + measured cycles | New utility lifetimes | Slab classes with zero delta | Large pages before → after |
| --- | --- | --- | --- | --- |
| ARM64 | 100 + 100 | 600 | 18 | 72 → 72 |
| x86_64 | 100 + 100 | 600 | 14 | 193 → 193 |

Six assertion-enabled artifact invocations passed: both current ciphertext
binding fixtures and four preceding plain-binding/ciphertext-reference fixtures
on unchanged retained media through unchanged oracles. Each current guest
matches all 18 independently constructed complete files. V and OpenSSL agree
on the complete reference and report fingerprints, including both RW/RO modes
and clean/changed reports produced through passphrase and recovery credentials.

The initial native compile rejected a raw pointer-to-fixed-array cast before
execution. The formatter uses the established checked byte-to-hex loop instead;
preliminary native ASan/UBSan checks passed. Independent review corrected a test
mutation that produced a zero MBR identity before the IO fixture was built.
All scoped runs used that corrected fixture. No scoped runtime retry was
needed. Helpers and oracles use ordinary builds with assertions enabled.

Final sources, native/model/target/guest C, build/boot logs, raw data and
configuration media, complete oracle outputs, independent lifetime review,
tooling/transport helpers and unchanged isolated kernel/input receipts are
retained under `logs/storage-cipher-scrub-reference-work/evidence/`, with source
and complete run SHA-256 manifests. Compiler temporary files used an owned RAM
volume released after builds. Closed boot transports are retained losslessly
as gzip with original SHA/length/roundtrip receipts; data/configuration media
remain raw. This scoped utility qualification verifies historical records
against trusted references and does not establish present disk integrity.
