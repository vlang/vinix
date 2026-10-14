# Pinned data checksum monitor qualification

`monitor-data-auto MANIFEST INTERVAL_SECONDS COUNT` scans complete plain-data
extents repeatedly against one retained reference, preserving changed status
after restoration. See [the contract](../../docs/storage-volumes.md#periodic-pinned-data-checksum-monitoring).

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-data-monitor --work /tmp/data-monitor-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --data-monitor --work /tmp/data-monitor-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --data-monitor --work /tmp/data-monitor-x86
```

The scoped host runs the unchanged plain-data IO model and native scrub suite,
plus the new encoder, syntax and actual monitor IO model under ASan/UBSan.
Eight native sector/identity/mode profiles exercise all 64 three-sample change
histories: 1536 exact complete outputs, independently constructed with standard
V SHA. Invalid observations and counters preserve the caller's output. A full
64-disk/64-row report, high signed geometry, empty sets and maximum unsigned
counters check buffer and counter bounds. Syntax tests cover invalid arities,
empty arguments, decimal overflow, interval bounds and zero-count/zero-interval
refusal; valid finite and continuous arguments reach ordinary input errors.

The actual IO model checks all 64 histories with ordinary transfers and again
with interrupted sector-sized physical reads and short reference reads. Each
three-sample stream is compared completely. Exactly one discovery per disk and
ten total status reads per disk establish the initial discovery and three full
pin checks per sample. Source/parent and both original physical pins stay open
at encoding, print, flush, stream-error and sleep observers; all returns balance
owners. Replacing the reference pathname after a sample preserves the original
session. Interrupted sleeps resume the remainder. Directory writer contention
does not block scans. A 512-sample session retains one discovery per participant.

Malformed references and all protected byte mutations fail before discovery.
Missing, symlink, directory and FIFO inputs, zero/EIO/oversized/trailing reads,
stat/size/mode faults and original physical reader faults cover cleanup. Later
physical read-only, identity, capacity, sector, saved native identity, offline
and read failures take precedence over an earlier changed sample. The later
read-error case also exercises continuous count 0. Encoder refusal and injected
print/flush/stream errors return 1; actual stdout EBADF does too. Diagnostics can
use stdout, but incomplete scans emit no successful monitor sample. The model
injects an encoder-boundary refusal, not an internal snprintf failure.

Each guest establishes the unchanged two-disk, three-row automatic plain-data
fixture, with RW and RO mappings and exact manual/automatic references/reports.
A single real monitor process runs at two-second intervals: clean, two changed
rows, then both restored. The parent changes and flushes physical bytes only
after observing each complete sample. Before the third scan it atomically
replaces the reference pathname with an invalid file; the original fingerprint
and reference still govern the session, which returns 2. A second process sees
a changed first sample, then a real native disk identity change, returning 1
without a second successful sample. All physical bytes and identities are
restored and flushed before further tests.

One/two/three-sample clean commands preserve every live mapping status field
and an already-held view under directory writer contention. A separate process
completes 512 samples, checking every complete sample and EOF. One hundred
warmup and one hundred measured three-command cycles run 600 new utility
lifetimes and 1200 complete samples per architecture, with 13-second grace
waits before heap snapshots. Automatic baseline checks and clean monitor
commands repeat after boot with reversed device order.

The independent oracle imports no production codec. It reconstructs 14 complete
persisted files per guest: the seven preceding bundle/reference/scrub artifacts,
the retained reference copy, three clean transcripts, the clean/changed/restored
sequence, the changed/late-error transcript and all 512 long-session samples.
Restored full extents, simulated corruption, native geometry/reserved fields,
CRCs and complete reference/digest fingerprints agree between standard V and
OpenSSL SHA. Complete utility and selected guest C receive allocation audits;
all new lifetimes receive independent review. Frozen isolated ALLOC_TRACK
kernels stay unchanged; this qualification concerns the utility increment.

## Qualification on 2026-10-14

`host-3`, `arm-1` and `x86-1` exit receipts are zero. All scoped ASan/UBSan
checks, both full target allocation audits and four guest boots passed.
Production and selected guest sources stayed unchanged through qualification.

| Guest | Warmup + measured cycles | New utility lifetimes / samples | Slab classes with zero delta | Large pages before → after |
| --- | --- | --- | --- | --- |
| ARM64 | 100 + 100 | 600 / 1200 | 18 | 72 → 72 |
| x86_64 | 100 + 100 | 600 / 1200 | 14 | 193 → 193 |

Both guests also passed the separate 512-sample process. Six assertion-enabled
artifact invocations passed: both current monitor fixtures and four preceding
ciphertext/plain reference-binding fixtures on unchanged retained media. Each
current guest matches all 14 independently constructed complete files.

Independent review corrected the short-read corruption coordinates and physical
pread wiring; the first host run failed on the unwired fixture scan. The second
run exposed a late sector-change fixture metadata assertion. The final fixture
constructs that changed metadata explicitly. Host 3 qualifies the corrected
model. These changes affect host fixture wiring; guest/production bodies stayed
unchanged. Helpers and oracles use ordinary builds with active assertions.

Final sources, native/model/target/guest C, build and boot logs, raw data and
configuration media, full oracle outputs, independent lifetime review and
unchanged isolated kernel/input receipts are retained under
`logs/storage-data-monitor-work/evidence/`, with source and complete run SHA-256
manifests. Compiler temporary files used an owned RAM volume released after
builds. Closed boot transports remain lossless gzip with original hash/length
and roundtrip receipts; data and configuration media remain raw. Repeated
checks against a trusted reference do not provide a concurrent snapshot,
authentication or repair.
