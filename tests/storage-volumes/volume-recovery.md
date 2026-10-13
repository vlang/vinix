# Encrypted-volume configuration recovery

See [commands, private formats and limits](../../docs/storage-volumes.md#encrypted-volume-configuration-recovery).

The native codec suite independently checks ChaCha20 with OpenSSL and HMAC with
V's standard library across both native sector sizes, MBR/GPT identities and
RW/RO modes, including full-width geometry. Every bit of every backup byte and
every byte of both recovery-key halves must reject without changing caller
metadata or plaintext. Format domains, key separation and invalid bounds are
checked explicitly.

The existing recovery syscall model also runs the actual new commands, readers,
codec and publisher with a deterministic KDF substitute. Faults cover exact
private inputs, short/EINTR/EOF reads, nonce failures, KDF failures, invalid
wrapping keys, locks, permissions, short writes, close/link/unlink/flush/report
failures and no-overwrite input aliases/dangling outputs. It asserts balanced
descriptors, complete workspace erasure, and credential/wrapping erasure before
reuse and destination acquisition. Tamper refusal precedes new credential/KDF
access. Publication failures retain the documented pre/post-publication behavior.

Run the complete host suite and targeted architecture guests using V tooling:

```sh
sh build-support/run-v-tool.sh tests/storage-volumes/plan_run.v --host --work /tmp/volume-recovery-host
sh build-support/run-v-tool.sh tests/storage-volumes/plan_run.v --arch aarch64 --kernel /path/to/arm/kernel/bin/vinix --volume-recovery --work /tmp/volume-recovery-arm
sh build-support/run-v-tool.sh tests/storage-volumes/plan_run.v --arch amd64 --kernel /path/to/x86/kernel/bin/vinix --volume-recovery --work /tmp/volume-recovery-x86
```

Both guests use production tools and init on disposable persistent disks. A
known independently encrypted extent must reopen after backup/recovery in both
RW/RO modes. Original keyfiles are deleted before recovery; old credentials,
original configurations and the recovered RW configuration are deleted before
reboot. Production init restores the recovered RO configuration after device
reordering. Recovery material and a new binary credential must then rebuild the
missing RW configuration and reopen the same ciphertext, with no raw keyfile.

Four warmup and four measured backup/recover/unlock lifetimes each run three
full-cost production scrypt KDFs. Snapshot-reader warmup and thirteen-second
reclamation precede exact large-page and all-slab equality checks. Complete
target utility and guest C must pass the allocation/runtime dependency audit.
The existing nine-boot comprehensive workload remains available unchanged.

`volume_recovery_artifacts.v COMPLETED_GUEST_WORK NEW_OUTPUT` independently
extracts persisted backups, restored configurations and the actual boot pair;
checks canonical headers, full HMAC and exact known keys with OpenSSL ChaCha20
and production scrypt; and reconstructs native AES-XTS ciphertext with standard
V AES. Its output directory includes an artifact hash manifest. The oracle uses
`VINIX_OPENSSL` and `VINIX_DEBUGFS` overrides when those tools are outside their
Homebrew locations.

Qualification on 2026-10-13 passes all 40 ASan/UBSan native suites, ten
syscall models (including the extended configuration recovery model), both init
policy cases and both complete target allocation audits. The targeted guests
finish both boots using the default 1800-second per-boot budget.

| Target | Boots | Warmup + measured lifetimes | Production KDFs | Slab classes, all deltas zero | Large pages |
| --- | --- | --- | --- | --- | --- |
| ARM64 | 2 | 4 + 4 | 24 | 18 | 72 → 72 |
| x86_64 | 2 | 4 + 4 | 24 | 14 | 191 → 191 |

Complete target utility C is byte-identical on both architectures, SHA-256
`a128009e16d4959cb26d6a10b3e46e0c1fb5794c578af4b5228e6dd82f433de6`. Independent
source and actual native/model/target/guest C review found no unresolved
issues; 255 prior production function bodies are unchanged. New utility and
guest paths introduce no implicit V allocation/runtime dependency.

Independent checks of exact persisted RW/RO backups, restored configurations
and boot pairs recover the known key with separate HMAC, OpenSSL ChaCha20 and
production scrypt. Standard V AES-XTS reproduces the actual persisted ciphertext,
SHA-256 `58d4a23c8dc7380e7069da904b7be35a5a844a9d6d1c744d531c960258cbbd22`.
Original credentials/configurations and raw keys are absent during the second
boot; production init and explicit recovery still reopen the original data.

The first codec/model checkpoint stopped on a test diagnostic type; the corrected
second checkpoint passes. ARM-1 and x86-1 stopped before boot on a fixture pointer
signedness warning. ARM-2 stopped before boot because the current V compiler
emitted unused stdio printer helpers into freestanding init. The maintained
generator now removes only the exact known unreferenced block; unit cases
preserve live, unknown and duplicate blocks. ARM-3 and x86-2 pass. All failed
logs remain retained. No generated init policy body was changed.

Frozen isolated ALLOC_TRACK kernels were reused with no kernel source changes.
Complete persistent media, native/model/target/guest C, oracle manifests and
review records are retained under `logs/storage-volume-recovery-work`; final
source/review and retained-file manifests are in its `evidence` directory.
