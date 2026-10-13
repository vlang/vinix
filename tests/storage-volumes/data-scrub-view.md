# Offline plain multi-disk scrub inspection qualification

`show-data-scrub REPORT` displays complete historical `VINIXSR1` findings only
after validating every field and row. Valid changed reports return 0; invalid
input or stdout failure returns 1. See
[the contract](../../docs/storage-volumes.md#offline-multi-disk-scrub-report-inspection).

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-data-scrub-view --work /tmp/data-scrub-view-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --data-scrub-view --work /tmp/data-scrub-view-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --data-scrub-view --work /tmp/data-scrub-view-x86
```

The scoped host checks run existing manifest, scrub, automatic-data and reference
tests, unchanged actual DataIO and discovery models, and new parser/syntax and
reader/output tests under ASan/UBSan. Parser tests cover all eight three-row
change masks, every truncation and embedded NUL, trailing bytes, label/number/hex
grammar, unsigned overflow, count/result inconsistency, late duplicate slots,
disk ordering, same-disk overlaps, signed extent ends, SHA length limits and
read-only flags. Sixty-four-disk/row full-width reports and every empty disk-count
profile test bounds; 4096 twelve-row producer change masks test compatibility.

The new standalone model transforms only the actual new reader/printf call and
shared ordinary-input/output-finalizer boundaries. It exercises exact read-only
flags, short/EINTR reads, EOF EINTR, zero/EIO/oversized/trailing reads, stat/size
faults, every file truncation, missing paths, directories, final symlinks and
nonblocking FIFOs. Ordinary 0644 files, hard links and a held writer lock work.
Observers retain both descriptors through printf/fflush/ferror; every tested
exit balances ownership. Injected print, flush and stream-error faults, plus
actual stdout write failure, return 1 for clean and changed reports. Validation
failures emit no SR1 header or row; existing diagnostics may use stdout.

Each guest creates the existing two-disk/three-row checksum fixture, persists
manual/automatic clean and changed reports after controlled corruption of both
RW extents, then restores and flushes both pages. Inspection is byte-identical
for automatic clean/changed and manual clean reports. An invalid last digest
emits no report. Inspection under writer contention preserves all three complete
live mapping statuses, including the RO mapping, and held mapping content.
One hundred warmup and one hundred measured cycles each launch three inspection
processes, giving 600 new utility lifetimes per architecture without a KDF.
Both phases wait thirteen seconds before measuring every warmed slab class
and retained large pages. Production init restores the bundle on the reordered
second boot; inspections and current manual/automatic clean scrubs repeat.

The independent V artifact oracle imports no producer codec and reconstructs
ten complete persisted files per guest: the 288-byte bundle, two 472-byte
references, four producer reports and three inspection captures. It checks
all bytes, geometry/reserved fields/CRC, restored extents, controlled corruption,
reference fingerprints and clean/changed text with independent V SHA/OpenSSL.
Complete target and selected guest C are audited for allocation dependencies;
the new borrowed cursor and descriptor lifetimes receive independent review.
Frozen isolated ALLOC_TRACK kernels remain unchanged.

## Qualification on 2026-10-14

`host-3`, `arm-2` and `x86-2` exit receipts are zero. All scoped ASan/UBSan
checks and four guest boots passed. Complete target and selected guest C pass
allocation audits; final implementation and selected guest bodies stayed
unchanged across the successful runs.

| Guest | Warmup + measured cycles | New utility lifetimes | Slab classes with zero delta | Large pages before → after |
| --- | --- | --- | --- | --- |
| ARM64 | 100 + 100 | 600 | 18 | 72 → 72 |
| x86_64 | 100 + 100 | 600 | 14 | 193 → 193 |

Six independent artifact oracle invocations passed: two current inspection
fixtures and four preceding plain-reference/ciphertext-reference fixtures on
unchanged retained media through their unchanged oracles. Each current guest
matches ten independently reconstructed complete artifacts. Clean and changed
producer/inspection reports have SHA-256 respectively
`0da36733d67b9e64dddad6f1b8616d206a34aebbc955d033f8b8dc7b07862017`
and `3da5f47799ff79b6e409d2a0d20563b1baaf86b122e6fb068cbc09f15bcdc990`.

Host attempt 1 caught a native fixture's `mkfifo` declaration. Host attempt 2
and both first guest attempts caught an overstrict fixture assertion: the
existing validation diagnostics use stdout, while the report contract requires
no SR1 header or row on invalid input. Corrected fixtures passed with the
production implementation unchanged. Failed logs, generated C and media remain
retained and are excluded from successful qualification.

Final sources, generated C, build/boot logs, media, oracle outputs, independent
lifetime review, toolchain/transport helpers and frozen kernel/input receipts
are retained under `logs/storage-data-scrub-view-work/evidence/`, with source and
complete run SHA-256 manifests. Compiler temporary files used an owned RAM
volume released after builds; closed boot transports are retained losslessly
as gzip with original SHA/length/roundtrip receipts. Physical data media remain
raw. This scoped utility qualification inspects historical structural
consistency; it does not authenticate reports, bind them to current disks,
establish concurrent snapshots or replace full desktop/kernel/native hardware
matrices.
