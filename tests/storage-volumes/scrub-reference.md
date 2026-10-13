# Historical plain-data scrub/reference binding qualification

`verify-data-scrub-reference MANIFEST REPORT` verifies complete reference and
row binding before displaying historical findings. See
[the contract](../../docs/storage-volumes.md#binding-data-scrub-reports-to-checksum-references).

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-scrub-reference --work /tmp/scrub-reference-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --scrub-reference --work /tmp/scrub-reference-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --scrub-reference --work /tmp/scrub-reference-x86
```

The scoped host runs unchanged DataIO and prior reference/history native
regressions, plus the new binding model and syntax suite under ASan/UBSan.
Eight native-sector/MBR-or-GPT/mode profiles exercise four change masks at
every observed digest byte: 1,024 exact output and strict decoder roundtrips.
Independent standard V SHA-256 checks both complete fingerprints. Valid
different identities, capacities, sectors, pool windows/order/IDs, row
metadata and expected digests fail binding; a report claiming the correct
fingerprint still must match every row. Maximum 64-disk/64-row/64-pool and
64-empty-disk cases exercise bounded output and high signed offsets.

The standalone actual reader/codec/CLI/output model checks clean and two
changed observations, ordinary 0644 and hard-linked inputs, held writer locks,
exact read-only/no-follow/nonblocking flags, short/EINTR and EOF EINTR reads,
zero/EIO/oversized/trailing reads, stat/size faults and later read/stat failures.
Every truncation on either input, every CRC-protected reference byte mutation,
NUL/trailing data, missing files, symlinks, directories, FIFOs, and valid
incompatible metadata or expectations refuse findings. All four descriptors
remain pinned at encoder/print/flush/error observers and balance on every exit.
Encoder-boundary refusal, injected print/flush/stream faults and actual stdout
EBADF return 1 even for changed reports. The encoder injection does not simulate
an internal snprintf failure. Diagnostics may use stdout; refusals emit no
binding header or rows.

Each guest uses two disks and three rows, with an RO middle row. Two distinct
real corruption patterns affect both RW extents; pages are restored and flushed.
Both manual and automatic references bind all three saved reports with exact
full output, geometry and fingerprints. A malformed last digest and a valid
incompatible reference refuse findings. Held directory writer contention does
not block binding; all three full mapping statuses and held mapping contents
remain unchanged. One hundred warmup and one hundred measured cycles each
verify clean/first-change/second-change reports: 600 new utility lifetimes per
architecture, with 13-second grace waits before slab/large-page measurements.
Production init restores the bundle after reordered reboot and every bound
view and preceding current-data/inspection/history check repeats.

The independent V artifact oracle imports no producer codec. It reconstructs
24 complete files per guest: the preceding 21 bundle/reference/producer/view/
history artifacts plus three bound views. Independent native disk identities,
full raw extents, restored bytes, both corruption patterns, metadata/reserved
bytes/CRC and V/OpenSSL SHA-256 verify the complete artifacts. Full utility and
selected guest generated C receive allocation audits; new lifetimes receive
independent review. The isolated ALLOC_TRACK kernels remain unchanged.

## Qualification on 2026-10-14

`host-2`, `arm-2` and `x86-2` exit receipts are zero. Scoped ASan/UBSan checks,
both complete target allocation audits and four guest boots passed. Final
production and selected guest sources stayed unchanged throughout these runs.

| Guest | Warmup + measured cycles | New utility lifetimes | Slab classes with zero delta | Large pages before → after |
| --- | --- | --- | --- | --- |
| ARM64 | 100 + 100 | 600 | 18 | 72 → 72 |
| x86_64 | 100 + 100 | 600 | 14 | 193 → 193 |

Six independent artifact invocations passed: both current binding fixtures and
four preceding history/ciphertext-reference fixtures on unchanged retained
media, using unchanged preceding oracle sources rebuilt with assertions active.
Each current guest matches 24 independently reconstructed complete files.
The clean, first changed and second changed bound-view SHA-256 values are
`f993af2235e1680f9c89323126119c06cc7597e7cb7e110b095b456606516515`,
`f35ba7c051a60c53101d12f8041210a6118aed6d57b4cf78e148b574190e12b8`
and `a0d589487ff474cad3259f7e7f5f552b3576b0190a4431ea8d8a353987d4f771`.

The first host run caught a test fixture that changed native sector size to
4096 while retaining a 512-byte pool alignment. Updating the fixture alignment
makes that alternate reference valid; production did not change. Corrected
preliminary native checks passed. The first run wrappers used fallback V
`-prod`, which strips assertions and skipped asserted log-capture calls. Both
first guests passed their explicit checks, but all first runs were superseded
by captured final runs with wrapper and oracle assertions enabled. Earlier
generated C, media and exit receipts remain retained; first outer logs were
not captured.

Final sources, generated C, build/boot logs, raw media, artifact outputs,
independent lifetime review, tooling/transport helpers and frozen kernel/input
receipts are retained under `logs/storage-scrub-reference-work/evidence/`, with
source and complete run SHA-256 manifests. Compiler temporary files used an
owned RAM volume released after builds. Closed boot transports are retained
losslessly as gzip with original SHA/length/roundtrip receipts; physical data
media remain raw. This scoped utility qualification verifies historical
evidence against trusted references and does not replace full desktop/kernel
or native hardware matrices.
