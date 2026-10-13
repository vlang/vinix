# Direct recovery-key volume unlock

See [commands and behavior](../../docs/storage-volumes.md#direct-recovery-key-unlock).

Run the scoped native qualification and disposable architecture guests:

```sh
sh build-support/run-v-tool.sh tests/storage-volumes/plan_run.v --host-recovery-unlock --work /tmp/recovery-unlock-host
sh build-support/run-v-tool.sh tests/storage-volumes/plan_run.v --arch aarch64 --kernel /path/to/arm/kernel/bin/vinix --recovery-unlock --work /tmp/recovery-unlock-arm
sh build-support/run-v-tool.sh tests/storage-volumes/plan_run.v --arch amd64 --kernel /path/to/x86/kernel/bin/vinix --recovery-unlock --work /tmp/recovery-unlock-x86
```

The scoped host run includes the independent recovery codec suite, existing
recovery reader/publisher fault model, extended discovery/boot-set model and
command syntax suite under ASan/UBSan. New discovery cases invoke the actual
command across MBR/GPT, 512/4096-byte sectors, saved RW/RO and forced RO.
They assert authentication before discovery, no KDF use, recovery-key erasure
before scanning/import, complete workspace erasure and balanced descriptors.
Faults include permissions, wrong lengths, symlinks/directories/missing files,
key reads/EOF/EINTR and post-read ownership/size/mode changes, malformed and
tampered backups, wrong key halves, disk aliases/duplicates, enumeration and
geometry/recheck/import/report failures. Enumeration remains bounded.

Both guests use production utilities/init and frozen isolated ALLOC_TRACK
kernels on persistent disposable media. Fixtures create known AES-XTS data and
RW/RO recovery backups, then delete raw keys, original/new passphrases and
ordinary configurations before direct unlock. RW writes, forced RO, saved RO,
tamper refusal and occupied-slot preservation are checked. Two hundred warmup
and two hundred measured unlock/remove lifetimes precede exact equality of
large pages and every slab class after thirteen-second reclamation and snapshot
reader warmup. A second boot reorders disks and must recover identical data in
all three modes without recreating deleted credentials/configurations.
Complete target utility and guest C must pass the no-allocation/runtime audit.

`volume_recovery_artifacts.v COMPLETED_GUEST_WORK NEW_OUTPUT --recovery-unlock`
independently extracts persisted RW/RO backups and the recovery key, checks
canonical metadata and full HMAC with standard V SHA-256, recovers exact keys
with OpenSSL ChaCha20 and reconstructs actual ciphertext with standard V AES-XTS.
The output includes a hash manifest. Existing configuration recovery oracle
behavior remains available without the option.

Qualification on 2026-10-13 passes the scoped native codec/syntax suites and
both syscall models under ASan/UBSan, both complete target allocation audits,
and both two-boot guests using production utilities/init and the default boot
timeout. The full unrelated native suite and nine-boot storage workload were
not rerun for this utility addition; kernel source and ABI are unchanged.

| Target | Boots | Warmup + measured lifetimes | Slab classes, all deltas zero | Large pages |
| --- | --- | --- | --- | --- |
| ARM64 | 2 | 200 + 200 | 18 | 78 → 78 |
| x86_64 | 2 | 200 + 200 | 14 | 199 → 199 |

Independent persisted backup/key/ciphertext oracles pass on both new guests.
AES-XTS ciphertext SHA-256 is
`58d4a23c8dc7380e7069da904b7be35a5a844a9d6d1c744d531c960258cbbd22`.
The oracle's existing configuration recovery mode also passes retained prior
ARM64 media; its AES calls now propagate the maintained V library's results.

The first host checkpoint passed older discovery coverage but skipped the
separate new model file. The runner now merges both test bodies into the selected
fixture. Host-1 then stopped on test-only array concatenation syntax; host-2
stopped on a slot tamper expectation that still described a canonical slot.
Corrected host-3 runs the actual new command and passes. All checkpoint logs
and generated C remain retained. Both architecture guests pass on their first
attempt. Independent source/generated-C review covers secret erasure and
descriptor lifetimes before commit.

Evidence, persistent media, native/model/target/guest C, independent oracle
outputs and final source/review hash manifests are retained under
`logs/storage-recovery-unlock-work`, with manifests in its `evidence` directory.
