# Offline plain multi-disk scrub history qualification

`compare-data-scrubs BEFORE_REPORT AFTER_REPORT` compares every observed digest
after complete strict validation and exact reference/row/expected-digest binding.
See [the contract](../../docs/storage-volumes.md#comparing-multi-disk-data-scrub-history).

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-data-scrub-history --work /tmp/data-scrub-history-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --data-scrub-history --work /tmp/data-scrub-history-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --data-scrub-history --work /tmp/data-scrub-history-x86
```

The scoped host runs unchanged actual DataIO and scrub-inspection models, the
prior strict parser/syntax suite, and new native history/model/syntax checks
under ASan/UBSan. All 729 three-row histories independently check stable,
new-change, restored and changed-again counts/masks and exact complete output
with V standard SHA-256 fingerprints. Strict private decoding round-trips all
27 three-row snapshots, both full-width 64-row snapshots and every empty saved
disk-count profile. Every three-row truncation and embedded NUL, trailing bytes,
every expected/observed digest byte, invalid later rows and valid differing
reference/count/slot/extent/mode/order metadata preserve caller state on failure.
The maximum comparison verifies row index 63, the full difference mask and
bounded output length. The inherited parser's complete syntax/bounds suite also
passes unchanged.

The new standalone actual reader/codec/CLI/output model exercises all nine
two-row state pairs, ordinary 0644 input, same-file and hard-linked inputs,
held writer locks, exact read-only/no-follow/nonblocking flags, short/EINTR and
EOF EINTR reads, zero/EIO/oversized/trailing reads, stat/size faults and second
input read/stat failures. Every truncation on either side, missing files,
symlinks, directories, FIFOs, malformed later rows, and valid incompatible
metadata/expected digests refuse comparison reports. Four descriptors stay
open at encoding, printing and final fflush/ferror observers; every outcome
balances ownership. Injected encoder-boundary refusal, print/flush/stream faults
and actual stdout EBADF return operational status 1 across all state pairs.
The encoder refusal does not inject an internal snprintf failure. Existing
diagnostics may use stdout; invalid inputs emit no SR1 comparison header or row.

Each guest uses the existing two-disk/three-row fixture with an RO middle row.
Two distinct real corruption patterns affect both RW extents, producing
independent changed reports; both pages are restored and flushed. All nine
clean/first-change/second-change pairs verify exact transitions, every row and
both full report fingerprints, including persistent mismatches returning 0.
A malformed last digest and a valid incompatible reference following a changed
input return 1 without a comparison. A held writer lock does not block reads;
all three complete live statuses and held mapping contents remain unchanged.
One hundred warmup and one hundred measured cycles each run new-change,
restored and changed-again comparisons: 600 new utility lifetimes per
architecture with no KDF work. Thirteen-second grace waits precede slab/large
measurements. Production init restores the bundle with reordered disks on the
second boot; all comparisons and manual/automatic current clean checks repeat.

The independent V artifact oracle imports no producer codec. It reconstructs
21 complete persisted artifacts per guest: the preceding ten bundle/reference/
producer/inspection files, two changed-history inputs and nine comparison
reports. Independent full raw extents, restored bytes, both simulated corruption
patterns, metadata/reserved bytes/CRC and V/OpenSSL SHA verify all input and
output bytes. Complete utility and selected guest C receive allocation audits;
the new candidate/cursor/descriptor lifetimes receive independent review.
Frozen isolated ALLOC_TRACK kernels remain unchanged.

## Qualification on 2026-10-14

`host-2`, `arm-2` and `x86-2` exit receipts are zero. All scoped ASan/UBSan
checks, complete target allocation audits and four guest boots passed. Final
implementation and selected guest sources stayed unchanged across these runs.

| Guest | Warmup + measured cycles | New utility lifetimes | Slab classes with zero delta | Large pages before → after |
| --- | --- | --- | --- | --- |
| ARM64 | 100 + 100 | 600 | 18 | 72 → 72 |
| x86_64 | 100 + 100 | 600 | 14 | 193 → 193 |

Six independent artifact oracle invocations passed: two current history
fixtures and four preceding inspection/ciphertext-reference fixtures on
unchanged retained media through their unchanged oracles. Each current guest
matches 21 independently reconstructed complete files. The clean, first changed
and second changed SR1 report SHA-256 values are respectively
`0da36733d67b9e64dddad6f1b8616d206a34aebbc955d033f8b8dc7b07862017`,
`3da5f47799ff79b6e409d2a0d20563b1baaf86b122e6fb068cbc09f15bcdc990`
and `4a75ee35dfb64875994b0fe04a01db4f0579937b450e7935e20676d02081e3db`.

The preliminary native matrix passed. First scoped host checks also passed,
but were superseded after both first guest cross-builds caught conditional
C-string temporaries inferred as unsigned pointers by the target generator.
Explicit character-pointer casts correct the new production encoders and guest
formatter. Final host/ARM/x86 runs qualify that correction. Earlier logs and C
are retained; neither failed first guest compilation has a runtime claim.

Final sources, generated C, build/boot logs, media, oracle outputs, independent
lifetime review, toolchain/transport helpers and frozen kernel/input receipts
are retained under `logs/storage-data-scrub-history-work/evidence/`, with source
and complete run SHA-256 manifests. Compiler temporary files used an owned RAM
volume released after builds; closed boot transports are retained losslessly
as gzip with original SHA/length/roundtrip receipts. Physical data media remain
raw. This scoped utility qualification compares trusted historical records; it
does not authenticate reports, establish current disk integrity, supply a
concurrent snapshot or replace full desktop/kernel/native hardware matrices.
