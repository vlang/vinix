# Offline data monitor transcript verification qualification

`verify-data-monitor MANIFEST TRANSCRIPT` checks all saved monitor frames,
complete reference binding, canonical sample/counter/latch consistency and
per-mapping adjacent transitions before printing a summary. See
[the contract](../../docs/storage-volumes.md#offline-data-monitor-transcript-verification).

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-data-monitor-verify --work /tmp/data-monitor-verify-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --data-monitor-verify --work /tmp/data-monitor-verify-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --data-monitor-verify --work /tmp/data-monitor-verify-x86
```

The scoped host runs the unchanged ordinary scrub/reference IO model and
native monitor encoder, plus the new complete history encoder, CLI and actual
buffered input model under ASan/UBSan. Native tests enumerate all 729
three-sample histories for two mappings in clean/corruption-A/corruption-B
states across eight sector/identity/mode profiles: 5832 independently expected
complete summaries and 17496 accepted frames. An independent transition table
and standard V SHA verify all fields and both complete input fingerprints.
Duplicate/gapped/leading-zero/overflowing sample counters, inconsistent changed
counts or latch, unrelated references, later row changes, every partial frame
and invalid digest mutations preserve prior caller history. A maximum 64-disk,
64-row summary checks full-width counters and high signed geometry, subtractive
overflow refusal, the 49152-byte bound and empty mapping sets. CLI tests cover
invalid arity, empty paths and valid syntax reaching missing-input refusal.

The standalone model executes the real CLI, ordinary DH1 reader, buffered
transcript parser, exact binding, summary encoder and final output. All 27
three-sample histories of one changed-capable row run with ordinary transfers,
short/EINTR reads and injected initial/later/EOF/stat/encoder/stdout failures.
Observers assert both original input/parent pairs stay live at sample acceptance,
encoding, print, flush and stream-error boundaries; all returns balance acquired
owners. Hard-linked aliases and directory writer contention work without locks.
Each exact-frame truncation produces the independently expected shorter history;
every other truncation, diagnostics, NUL, extra line or unfinished next prefix
refuses without a successful summary. Protected reference-byte mutations,
unrelated geometry, symlink/directory/FIFO/missing paths and same-file inputs
also refuse. A 512-frame stream checks the complete standard SHA and buffered
read count; a failure after the first buffer takes precedence over earlier
changed observations. Oversized sparse input fails at stat before reading.
Real stdout EBADF returns 1 with balanced owners. Output failures may leave a
partial write; no internal snprintf failure is injected.

Each guest establishes the unchanged real plain-data monitor fixture with two
physical disks, three saved mappings and both mapping modes. Producer tests
retain their original clean/changed/restored and late-error transcripts, every
one of 512 long-session samples and preceding retention checks. The new verifier
matches complete independently expected clean one/two/three-sample summaries,
the changed/restored session's status 2 and transition counts, and the 512-frame
summary. Late diagnostics and a non-transcript binary reference return 1.
Checks run under directory writer contention while preserving complete live
mapping status and an already-held view. One hundred warmup and one hundred
measured cycles each verify clean-one, clean-two and changed/restored-three
histories: 600 new utility lifetimes and 1200 examined frames per architecture,
with 13-second grace waits before snapshots. The matrix repeats after a boot
with physical devices reordered. The new offline verifier opens no disks and
performs no KDF; no continuous monitor session is claimed.

The independent oracle imports no production codec. It reconstructs 19 complete
persisted files per guest: the original 14 bundle/reference/scrub/monitor files
and five verified-history summaries. Original raw disk geometry, full restored
extents, controlled corruption, reserved fields and CRCs are checked; standard
V and OpenSSL agree on complete extent/reference hashes. All 512 input frames
are independently constructed before checking the history's whole transcript
hash. Complete utility and selected guest C receive allocation audits and an
independent lifetime review. Frozen isolated ALLOC_TRACK kernels remain unchanged;
this is utility qualification.

An exact-frame transcript prefix can be a valid shorter session. The format
records neither planned count nor originating command completion. Verification
binds historical evidence to a trusted reference; it does not authenticate the
inputs or prove current disk integrity, repair or a concurrent snapshot.

## Qualification on 2026-10-14

`host-5`, `arm-2` and `x86-2` exit receipts are zero. Scoped ASan/UBSan tests,
both complete target allocation audits and four guest boots passed. Final
production and selected guest bodies stayed unchanged through qualification.

| Guest | Warmup + measured cycles | New lifetimes / examined frames | Slab classes with zero delta | Large pages before → after |
| --- | --- | --- | --- | --- |
| ARM64 | 100 + 100 | 600 / 1200 | 18 | 72 → 72 |
| x86_64 | 100 + 100 | 600 / 1200 | 14 | 193 → 193 |

Both guests passed the separate 512-frame verification. Six assertion-enabled
artifact invocations passed: both current 19-file fixtures and four preceding
plain/cipher-monitor fixtures through unchanged oracles on retained media.
The complete current transcripts and their summaries match independently
constructed bytes and full SHA-256 fingerprints.

Host 1/2 rejected native test Result propagation. Host 3 rejected an Option
error variable; an explicit nonpropagating helper handles the prefix lookup.
Host 4 measured a 32194-byte summary in the short-offset fixture. The final
fixture uses a valid full-width signed offset with its large extent to exercise
a summary greater than 32 KiB within the 49152-byte bound. ARM 1/x86 1 rejected
a borrowed guest fixed-array pointer outside unsafe; its explicit stack borrow
qualifies in ARM 2/x86 2. These were fixture corrections; production stayed
unchanged. All helpers, oracles and review tooling retain active assertions.

Closed boot images and ARM firmware are retained losslessly as gzip with original
hash/length and readback receipts. Raw data/configuration media remain intact.
Final sources, native/model/target/guest C, build/boot logs, media, complete
oracle outputs, independent lifetime review, tooling and unchanged isolated
kernel/input receipts are retained under
`logs/storage-data-monitor-verify-work/evidence/` with complete source/run
SHA-256 manifests.
