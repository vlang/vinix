# Recovery-backup credential changes

See [commands, publication behavior and limits](../../docs/storage-volumes.md#changing-recovery-backup-credentials).

Run the scoped native qualification and disposable architecture guests:

```sh
sh build-support/run-v-tool.sh tests/storage-volumes/plan_run.v --host-recovery-rewrap --work /tmp/recovery-rewrap-host
sh build-support/run-v-tool.sh tests/storage-volumes/plan_run.v --arch aarch64 --kernel /path/to/arm/kernel/bin/vinix --recovery-rewrap --work /tmp/recovery-rewrap-arm
sh build-support/run-v-tool.sh tests/storage-volumes/plan_run.v --arch amd64 --kernel /path/to/x86/kernel/bin/vinix --recovery-rewrap --work /tmp/recovery-rewrap-x86
```

The host run checks the independent recovery codec, the extended real
reader/publisher model and command syntax under ASan/UBSan, then emits both
complete target utilities for the allocation/runtime audit. The selected model
test includes the new body explicitly. Rewrap cases invoke the command across
MBR/GPT identities, 512/4096-byte sectors and RW/RO modes, checking exact metadata
and keys, fresh nonce, old-key refusal, preserved source bytes, same-key refresh
and balanced descriptors/locks. Whole workspaces erase on every return.

The model observes old-credential erasure before replacement access and
replacement/volume-key erasure before directory acquisition. Tampering and
wrong old-key halves reject before replacement-credential access. Private
ownership/permissions, exact lengths, EOF/EINTR/short reads, changed metadata,
symlinks/directories/missing files, nonce-source failures and new-key policy
failures are exercised. Writer locks, private temporary files, short writes,
flush/close/link/unlink/output failures and input/destination aliases retain
the publisher's documented pre/post-publication behavior. No KDF executes.

Production guest utilities create known ciphertext and recovery backups, then
remove raw keys, passphrases and ordinary configurations before rewrap. New
RW/RO backups preserve metadata and reopen exact data; old credentials reject
the new backups while original backups remain usable. Destinations never
replace originals, outputs or credentials. Two hundred warmup and two hundred
measured rewrap/unlock/remove lifetimes require exact equality in large pages
and every slab class after snapshot-reader warmup and thirteen-second
reclamation. The old credential is deleted before a reordered second boot;
only the new credential can unlock the rewrapped RW/RO backups, with optional
forced RO and no recreated raw key or ordinary configuration.

`volume_recovery_artifacts.v COMPLETED_GUEST_WORK NEW_OUTPUT --recovery-rewrap`
independently extracts original and rewrapped backups and the actual replacement
key. It checks canonical metadata, complete HMAC, fresh nonce, exact ChaCha20 key
recovery under both credentials and rejection of the old credential for new
backups. Standard V AES-XTS reconstructs persisted ciphertext. Existing oracle
modes remain available. Frozen isolated ALLOC_TRACK kernels are reused; kernel
source and ABI are unchanged.

Qualification on 2026-10-13 passes the scoped independent codec/syntax suites
and extended reader/publisher model under ASan/UBSan, both complete target
allocation audits and both two-boot guests using production tools/init and the
default per-boot timeout. The unrelated full native suite and nine-boot storage
workload were not rerun for this utility addition.

| Target | Boots | Warmup + measured lifetimes | Slab classes, all deltas zero | Large pages |
| --- | --- | --- | --- | --- |
| ARM64 | 2 | 200 + 200 | 18 | 84 → 84 |
| x86_64 | 2 | 200 + 200 | 14 | 199 → 199 |

Independent persisted original/rewrapped backup oracles pass on both targets,
including exact metadata/key preservation, fresh nonce and old-credential
refusal for new backups. Standard V AES-XTS reproduces the retained ciphertext,
SHA-256 `58d4a23c8dc7380e7069da904b7be35a5a844a9d6d1c744d531c960258cbbd22`.
The oracle's existing unlock and sealed recovery modes pass retained prior
ARM64 media as well.

Host-1 passes on its first attempt and actually selects the new rewrap test.
ARM-1/x86-1 stopped before C generation because a deferred fixture wipe needed
an explicit unsafe scope. Corrected ARM-2/x86-2 pass; all failed logs remain
retained. Independent source/generated-C review verifies authentication and
erasure order, private publication, descriptor ownership and unchanged prior
production bodies before commit.

Persistent media, native/model/target/guest C, oracle outputs and final
source/review SHA-256 manifests are retained under
`logs/storage-recovery-rewrap-work`, with manifests in its `evidence` directory.
