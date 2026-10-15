# Offline ciphertext monitor transcript qualification

`verify-volume-monitor REFERENCE TRANSCRIPT` checks every saved ciphertext
frame against its complete private CH1 reference before reporting historical
observations and adjacent transitions. See
[the contract](../../docs/storage-volumes.md#offline-ciphertext-monitor-transcript-verification).

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-cipher-monitor-verify --work /tmp/cipher-monitor-verify-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --cipher-monitor-verify --work /tmp/cipher-monitor-verify-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --cipher-monitor-verify --work /tmp/cipher-monitor-verify-x86
```

The scoped host runs the unchanged private ciphertext scrub/reference IO model
and native monitor encoder, plus the new frame/history suite and actual buffered
CLI model under ASan/UBSan. Native tests enumerate all 27 three-sample histories
of clean/corruption-A/corruption-B across eight sector/identity/mode profiles
and both source domains: 432 independently expected summaries and 1296 frames.
An independent transition table and standard V SHA verify every summary field.
Every byte changed to a noncanonical character, every frame truncation, protected
CH1 mutation, unrelated valid CH1, mixed source, duplicate/gapped/leading-zero/
overflowing sample, inconsistent changed/latch count and altered native geometry
preserves prior caller history. Full-width geometry/counters, subtractive overflow
guards, the 2048-byte summary bound and CLI syntax checks exercise limits.

The standalone model invokes the real CLI, private CH1 reader, shared buffered
line reader, complete frame validator, summary encoder and stdout finalization.
Both domains repeat all 27 histories with ordinary and short/EINTR reads and
initial/later/EOF/stat/encoder/output faults. All four original file/directory
owners remain observed at transcript reads, frame acceptance, encoding, print,
flush and stream-error checks. All returns balance acquired owners. Hard links
and directory writer contention work without locks. Private CH1 ownership,
permissions and post-EOF changes refuse; a 0644 public transcript works.

Every complete-frame prefix returns its exact independently expected shorter
history; every partial frame and appended NUL/diagnostic/blank/unfinished prefix
refuses without successful findings. Protected CH1 mutations, later frame fields,
mixed source labels, same-file inputs, symlink/directory/FIFO/missing paths and
wrong geometry also refuse. A 512-frame stream checks the complete standard SHA
and fewer than 16 transcript reads; failure after the first buffer overrides
prior changed observations. Oversized sparse input fails before reading; EOF
interruption and final transcript size/type/stat faults are exercised. Real
stdout EBADF returns 1 with balanced owners. Output errors may leave a partial
write; no internal snprintf failure is injected.

Both guests establish the unchanged real encrypted scrub/reference/monitor
fixture, including both modes, both authenticated producer domains, controlled
physical corruption/restoration, late identity failure, source pathname
replacement and the separate 512-sample monitor. Original producer and recovery
retention checks remain. New offline child processes match 12 complete clean
one/two/three-sample summaries across both modes/domains, the restored session's
status 2 and transition counts, and the 512-frame summary. A late diagnostic and
an unrelated read-only mode reference return 1. Complete live mapping status
and held plaintext remain unchanged under directory writer contention.

One hundred warmup and one hundred measured verifier cycles each run a clean
volume/RW single frame, clean recovery/RO two frames and changed/restored
volume/RO three frames: 600 new utility lifetimes/1200 examined frames per
architecture, with 13-second grace waits. These are separate from inherited
producer lifetimes/KDFs. The new verifier performs no KDF or disk access. The
matrix repeats after reordered boot; no continuous producer session is claimed.

The independent oracle imports no production codec and reconstructs 48 complete
persisted files per guest: the original 34 ciphertext/reference/scrub/binding/
monitor artifacts and 14 verified-history summaries. It checks raw restored
ciphertext, controlled corruption, exact geometry/reserved fields/CRCs, V/OpenSSL
full extent/reference hashes and every original 512-frame transcript before
checking its summary hash. Complete utility and selected guest C receive
allocation audits and independent lifetime review. Frozen isolated ALLOC_TRACK
kernels remain unchanged; this is utility qualification.

An exact-frame prefix remains valid shorter history; planned sample count and
originating command completion are absent from the format. Source labels and
historical hashes do not authenticate the inputs or establish present data
integrity, a concurrent snapshot or repair.

Qualification completed on 2026-10-15. The scoped host ASan/UBSan suites and
both complete utility target C allocation audits passed. Both architectures
passed first and reordered boots, the 512-frame verifier, and 100 warmup plus
100 measured cycles (600 new verifier processes/1200 frames per architecture).
All 18 ARM64 slab classes stayed flat with large allocations 74→74; all 14
x86_64 classes stayed flat with large allocations 195→195. Each independent
persisted oracle checked all 48 exact files and its SHA-256 manifest, including
every original long-transcript frame and each new whole-input summary hash.

Final runs and review evidence are retained under
`.cipher-monitor-qualification/` in the checkout. Shared log cleanup removed
earlier run evidence; the final qualification was rerun in this separate
directory. Both frozen ALLOC_TRACK kernels were recovered from older retained
media and matched their original SHA-256 hashes exactly. No missing earlier
run or plain-data fixture is counted as final evidence.
