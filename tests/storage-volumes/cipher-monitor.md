# Authenticated ciphertext monitor qualification

`monitor-volume-auto CONFIG PASSPHRASE_FILE REFERENCE INTERVAL_SECONDS COUNT`
and `monitor-recovery-volume-auto BACKUP RECOVERY_KEYFILE REFERENCE
INTERVAL_SECONDS COUNT` authenticate once, erase secrets and repeatedly check
physical ciphertext with retained original reference/device owners. See
[the contract](../../docs/storage-volumes.md#periodic-authenticated-ciphertext-monitoring).

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-cipher-monitor --work /tmp/cipher-monitor-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --cipher-monitor --work /tmp/cipher-monitor-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --cipher-monitor --work /tmp/cipher-monitor-x86
```

The scoped host runs the unchanged recovery IO model and native ciphertext
scrub suite, plus the new complete encoder, CLI and actual session model under
ASan/UBSan. Eight native sector/identity/mapping-mode profiles, both domains,
all eight three-sample histories and every sample produce 384 independently
constructed complete outputs. Every protected reference-byte mutation refuses
encoding without changing caller output. Invalid counters, maximum unsigned
counters and high signed geometry check buffer/range bounds. Both CLI commands
cover invalid arity, empty arguments, decimal overflow, interval bounds and
continuous zero-interval refusal; valid argument limits reach input failures.

The actual session model executes the real CLI, private input readers,
configuration/recovery authentication, erasure, CH1 checks, physical probes,
complete streaming SHA and final output paths. Passphrase tests use a counted
deterministic wrapping-key KDF substitute to make exhaustive histories fast;
real bounded scrypt is exercised in both guests. All eight histories repeat in
both domains and eight profiles with ordinary transfers and again with reference
short/EINTR reads and sector-sized interrupted physical transfers. Entire
three-sample streams match independent standard V SHA expectations. Successful
sessions have one discovery, one modeled derive call for sealed inputs and zero
for recovery, ten physical status reads and three complete extent reads.

Observers verify all password/wrapping/volume-key bytes are zero before reference
reads/discovery and at encoding, print, flush, stream-error and sleep boundaries.
Original reference/parent and physical owners remain live at each boundary;
every return closes acquired owners and clears the complete session workspace.
Replacing all three input pathnames between samples does not reauthenticate,
reload the reference or rediscover. Interrupted sleeps retry the remainder.
Directory writer contention permits scans. A 512-sample recovery model retains
one original discovery and no KDF calls.

Wrong credentials, authenticated input corruption, malformed or unrelated CH1
geometry and every protected reference-byte mutation fail before discovery.
Initial/private EOF ownership and permission failures, 0644 inputs, malformed
lengths, zero/EIO/oversized/trailing reads, missing/directory/symlink/FIFO paths,
discovery refusal and physical transfer failures balance owners. Later selected
physical ID/read-only bit, capacity, native sector/identity, offline and read
failures take precedence over a changed first sample; the later read failure
also exercises count 0. Final-pin refusal emits no successful sample. Encoder
boundary refusal, print/flush/stream-error faults and real stdout EBADF return 1,
including after changed findings. Diagnostics can use stdout; output failure may
leave a partial write. No internal snprintf failure is injected.

Each guest establishes the unchanged real encrypted scrub fixture, both mapping
modes and credential domains, controlled restored physical corruption, existing
input-preservation checks and preceding real-KDF retention. Existing offline
reference binding persists its eight complete views. New one/two/three-sample
commands check both domains/modes with complete independently expected streams.
A real sealed RO session at two-second intervals produces clean, changed and
restored samples. The parent changes and flushes physical ciphertext only after
each complete frame, then replaces configuration, passphrase and reference paths
before sample 3; the child retains its initial authenticated/reference geometry
and returns 2. A recovery RW session sees a changed first sample, then a real
native disk identity change, printing only that complete sample and the exact
operational diagnostic before returning 1. All original ciphertext/identity
and the reference copy are restored and flushed.

Complete live mapping status and already-held decrypted contents stay unchanged
under writer contention. A separate sealed RO process checks all 512 samples and
EOF after one real authentication. Four warmup and four measured cycles each run
one sealed three-sample session, one recovery three-sample session and 25 recovery
one/two/three-sample trios. This totals 616 utility lifetimes/1248 complete samples,
including 8 real scrypt calls and 608 recovery sessions per architecture; 13-second
grace waits precede snapshots. The whole matrix, historical binding and recovery
unlock repeat after device-reordered boot. No real continuous count-0 guest
session is claimed.

The independent oracle imports no production codec. It reconstructs 34 complete
persisted files per guest: two CH1 references, eight CS1 reports, eight bound
views, twelve clean monitor transcripts, the retained reference copy,
clean/changed/restored and changed/late-error streams, and every one of the 512
long-session frames. Restored full ciphertext, simulated corruption, all native
geometry/reserved fields/CRCs and complete expected/observed/reference hashes
agree between standard V and OpenSSL. Complete utility/selected guest C receive
allocation audits and independent lifetime review. Frozen isolated ALLOC_TRACK
kernels are unchanged; this qualification concerns a utility increment.

## Qualification on 2026-10-14

`host-3`, `arm-1` and `x86-1` exit receipts are zero. Scoped ASan/UBSan checks,
both full target allocation audits and four guest boots passed. Final production
and selected guest bodies stayed unchanged through qualification.

| Guest | Warmup + measured cycles | New lifetimes / samples / real KDFs | Slab classes with zero delta | Large pages before → after |
| --- | --- | --- | --- | --- |
| ARM64 | 4 + 4 | 616 / 1248 / 8 | 18 | 72 → 72 |
| x86_64 | 4 + 4 | 616 / 1248 / 8 | 14 | 193 → 193 |

Both guests passed the separate authenticated 512-sample process. Six
assertion-enabled artifact invocations passed: both current ciphertext monitor
fixtures and four preceding plain-monitor/ciphertext-binding fixtures through
unchanged oracles on retained media. Each current guest matches all 34 complete
independently constructed files and every long-session sample.

Host 1 rejected a reserved `lock` fixture local before model execution. Host 2
rejected an unnamed mkfifo pointer declaration against libc's const parameter.
The final fixture uses the existing named declaration form; host 3 qualifies
those fixture corrections. Production and guest bodies stayed unchanged.
All orchestration, oracle and review helpers use ordinary assertion-enabled
builds. Initial transport archiving hit transient shared-disk ENOSPC; closed
transports were staged and verified on the owned compiler RAM volume, then
retained losslessly on disk with original SHA/length/readback receipts before
releasing that volume. Raw data/configuration media remain unchanged.

Final sources, native/model/target/guest C, build/boot logs, raw media, complete
oracle outputs, independent lifetime review, tooling and unchanged isolated
kernel/input receipts are retained under `logs/storage-cipher-monitor-work/evidence/`
with source and complete-run SHA-256 manifests. Repeated ciphertext observations
against a trusted reference provide neither plaintext authentication, repair
nor a concurrent snapshot.
