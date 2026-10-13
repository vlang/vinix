# Offline plain multi-disk reference comparison qualification

`compare-data-references` compares every recorded digest only after both complete
manifests and their exact saved bundle metadata agree. It constructs the entire
report with both full reference fingerprints before stdout output. Input owners
remain alive through output finalization; there is no physical I/O, credential,
writer lock or publication. See
[the contract](../../docs/storage-volumes.md#offline-multi-disk-data-reference-comparison).

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-data-reference --work /tmp/data-reference-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --data-reference --work /tmp/data-reference-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --data-reference --work /tmp/data-reference-x86
```

The scoped ASan/UBSan host runs unchanged manifest/scrub/automatic validation
tests, the extended actual DataIO fixture, unchanged complete discovery tests
and new native comparison/syntax tests. Eight MBR/GPT, 512/4096-sector and saved
mode profiles cover every digest byte and both comparison directions with all
two-row change masks. Different valid disk/extent/mode/pool metadata and invalid
later records preserve caller findings. A full 64-disk/row/pool reference tests
high unsigned capacities, signed extent bounds and maximum report length;
pool order/windows and zero-row sets receive separate checks.

The real CLI/reader/codec/report path executes with explicit syscall adapters.
The reader model covers exact no-follow/nonblocking read-only flags, normal and
short/EINTR reads, zero/failed/oversized/trailing reads, metadata-size faults,
every unrepaired input byte corruption on either side, missing files,
directories, final symlinks and nonblocking FIFOs. Same-path/hard-linked inputs
and ordinary 0644 files work; held writer locks do not block comparisons.
Complete reports and both fingerprints match V standard-library SHA and
independent expected text. Counters prove no physical discovery/probe/read or
publication. Both owners stay open at encoding and final flush/error observers,
and all descriptor counts balance. An injected encoder refusal, flush/error
faults and actual buffered stdout failure return 1 even with changed findings.
The encoder refusal is a boundary injection, not an internal snprintf fault.

Each guest reuses the unchanged two-disk/three-row plain checksum fixture and
manual/automatic clean equality. Controlled physical changes on both RW
extents create a real changed reference; both pages are restored and flushed.
Exact stable, changed, reverse and changed-stable comparisons verify every row
and full fingerprint against independently constructed constants. A malformed
later reference following a changed input refuses findings. Comparisons work
under writer contention and preserve full live status and held mapping content.
One hundred warmup and one hundred measured cycles each run stable, changed and
reverse comparisons, giving 600 new utility lifetimes per architecture with no
KDF. Both phases wait thirteen seconds before checking every warmed slab class
and retained large pages. Production init restores the persisted bundle on the
reordered second boot; comparisons and manual/automatic clean checks repeat.

The independent artifact oracle imports no producer codec. It constructs the
exact 288-byte bundle, three 472-byte original/automatic/changed references,
three clean scrub reports and four complete comparison reports: eleven exact
persisted artifacts per guest. Reserved bytes, all geometry, canonical row
order, bitwise CRC, restored/changed full extents and both reference fingerprints
are verified independently with V SHA and OpenSSL. Complete target and selected
guest C are audited for allocations and reviewed for source/model equivalence
and every new lifetime. Frozen isolated ALLOC_TRACK kernels remain unchanged;
this increment changes no kernel implementation.

## Qualification on 2026-10-14

`host-3`, `arm-3` and `x86-3` exit receipts are zero. ASan/UBSan passed without
sanitizer or undefined-behavior errors; all four guest boots passed. The final
implementation and selected guest bodies stayed unchanged across these runs.

| Guest | Warmup + measured cycles | New utility lifetimes | Slab classes with zero delta | Large pages before → after |
| --- | --- | --- | --- | --- |
| ARM64 | 100 + 100 | 600 | 18 | 72 → 72 |
| x86_64 | 100 + 100 | 600 | 14 | 191 → 191 |

Six independent artifact oracle invocations passed: two current comparison
fixtures and four retained preceding plain-data and ciphertext-reference
fixtures. The preceding oracle sources/media remain unchanged and are separate
regressions, not encrypted workloads in the new plain-data guest. Current
original and changed reference fingerprints are respectively
`a54001cd53e073d1214f5c2ed19a0d4f14c18f6408ac69a4c65a6cf75f4d3d0a`
and `c464c0c5d2f2fc71c03efb0e88385d4c39b2f85b8743286bacd07d7d8db057a1`.

First attempts caught a native immutable-window test mutation and a guest
fixed-array annotation. Corrected attempts then caught V promoting the new SHA
context to `memdup`; that context now uses the established explicit stack
allocation. Final host/ARM/x86 runs qualify that correction. Earlier failed
build logs and generated C remain retained and do not count as successful
qualification. Compiler temporary files used an owned RAM volume; its device
was released after builds completed. All run artifacts remain on disk. Closed
boot transport images are retained losslessly as gzip, with original SHA/length
and roundtrip receipts; physical data media remain raw.

Final sources, generated C, build/boot logs, raw media, oracle outputs,
independent review, toolchain/transport helpers and kernel/input receipts are
retained under `logs/storage-data-reference-work/evidence/`, with source and
complete run SHA-256 manifests. This scoped host/QEMU qualification compares
recorded references; it does not establish current data, authenticate input
replacement, infer time order, provide simultaneous snapshots or replace full
desktop/kernel/native hardware matrices.
