# Automatic plain multi-disk checksum and scrub qualification

`hash-bundle-auto`, `verify-data-auto` and `scrub-data-auto` validate the complete
saved input, discover all physical participants read-only and retain their
original descriptors through streaming, rechecks, publication and output.
They share the existing plain-data codecs and atomic replacement publisher.
See [the contract](../../docs/storage-volumes.md#identity-based-automatic-data-checksums-and-scrubbing).

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-data-auto --work /tmp/data-auto-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --data-auto --work /tmp/data-auto-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --data-auto --work /tmp/data-auto-x86
```

The scoped ASan/UBSan host runs existing manifest/scrub codecs, the extended
actual DataIO model, the unchanged actual discovery model and new native
validation/syntax tests. Canonical input validation covers 1–64 unique disks,
all global slots, later signed-range/alignment failures, bad arity and empty
paths. An absent explicit-device list selects discovery; an empty manual list
remains invalid. Existing real discovery tests cover aliases, cloned-disk
ambiguity, entry bounds, candidate/enumeration faults and descriptor cleanup.

The DataIO discovery boundary is injected while the real checksum CLI, codecs,
scanner, rechecks and publisher execute. MBR512/GPT4096 participants stream
73728 bytes each through the 64-KiB boundary. Normal and interrupted/aligned
short transfers succeed. Nonphysical/offline disks, bad identities, missing
later disks, duplicate physical IDs, selected-ID/mode discontinuity, invalid
transfers and publication faults fail with balanced descriptors. Late mode,
ID and geometry changes occur at the fourth probe for hash/scrub and third
for verification; both full extents have been delivered, no write or rename
occurs, and old reference/report bytes remain exact. Existing explicit-device
test bodies and their mock remain unchanged.

Later-disk-only and simultaneous two-disk changes produce independently
computed complete scrub reports. A later I/O failure after an earlier mismatch
returns operational failure and preserves the old report. Verification retains
its existing fail-fast mismatch behavior. Invalid source bytes, aliases and
special destinations reject before discovery. Short/EINTR publication and
file-fsync/close/rename/directory-fsync failures retain the existing before/after
rename guarantees. Existing output-finalization failure tests also run.

Each guest uses two physical MBR512 disks with three saved mappings: two RW
8192-byte extents and one RO 12288-byte extent. Manual and automatic creation,
verification and scrub outputs/artifacts match exactly. Simultaneous physical
corruption on both disks reports two changed rows and one match; both original
pages are restored and flushed. A later saved-identity mismatch refuses
automatic operations while preserving the changed report; retry passes after
restoration. Held view data, full verification status and mapping generations
remain valid. Hash/scrub respect writer contention while verification proceeds.
GPT4096 and later-disk-only corruption are host-model coverage, not guest cases.

One hundred warmup and one hundred measured cycles each execute automatic hash,
verification and scrub: 600 new utility process lifetimes per architecture,
with no KDF. Both phases wait thirteen seconds before comparing every warmed
slab class and retained large pages. Production init restores the saved bundle
on the reordered second boot; automatic argv contains no device paths and
manual/automatic outputs remain exact.

The independent V artifact oracle imports no producer codec. It constructs the
exact 288-byte bundle, both 472-byte `VINIXDH1` files, clean and changed complete
ASCII `VINIXSR1` reports, reserved fields, bitwise CRC, identity, geometry and
canonical row order. V standard-library SHA and OpenSSL independently check
every restored/changed full physical extent and the reference fingerprint.
Complete utility and selected guest generated C receive allocation audits and
independent lifetime review. Frozen isolated ALLOC_TRACK kernels are unchanged;
this increment changes no kernel implementation.

## Qualification on 2026-10-14

`host-2`, `arm-3` and `x86-3` exit receipts are zero. The scoped host passed
ASan/UBSan without sanitizer or undefined-behavior errors; all four guest boots
passed. Production sources stayed unchanged across these successful runs.

| Guest | Warmup + measured cycles | New utility lifetimes | Slab classes with zero delta | Large pages before → after |
| --- | --- | --- | --- | --- |
| ARM64 | 100 + 100 | 600 | 18 | 78 → 78 |
| x86_64 | 100 + 100 | 600 | 14 | 199 → 199 |

Fifteen independent persisted artifact oracle invocations passed: two current
plain-data runs and thirteen retained preceding modes for reference inspection,
automatic ciphertext checksums, ordinary/recovery envelopes, automatic/manual
ciphertext scrub reports, recovery growth/rotation and sealed recovery. Those
preceding oracle sources and media remain unchanged; they are separate checks
on older fixtures, not encrypted workloads in the new plain-data guest.

Both current references have SHA-256
`a54001cd53e073d1214f5c2ed19a0d4f14c18f6408ac69a4c65a6cf75f4d3d0a`.
Clean and simultaneous-change report SHA-256 values are
`0da36733d67b9e64dddad6f1b8616d206a34aebbc955d033f8b8dc7b07862017`
and `3da5f47799ff79b6e409d2a0d20563b1baaf86b122e6fb068cbc09f15bcdc990`.

Initial compile attempts caught a test helper's Result propagation and a guest
fixed-array indexing annotation, corrected before qualification. Attempt-two
first boots passed, but reordered boots exposed a missing fixture phase marker
and boot-plan publication; corrected first-boot teardown is qualified by both
attempt-three runs. All failed receipts and media remain retained and do not
count as successful qualification. A shared-host ENOSPC helper build preceded
the tests; this run used an owned 4-GiB RAM volume for compiler temporary files
and work artifacts, then verified every copied result on disk before releasing
that volume. Closed boot transport images are retained losslessly as gzip with
original SHA/length and roundtrip receipts. Physical data media stay raw.

Final sources, generated C, all run/build/boot logs, raw media, oracle outputs,
independent review, toolchain/transport helpers and kernel/input receipts are
retained under `logs/storage-data-auto-work/evidence/`, with source and complete
run SHA-256 manifests. This scoped host/QEMU qualification covers quiescent
data and the existing publisher; it does not establish authentication, coherent
snapshots, repair, native hardware or a full desktop/kernel test matrix.
