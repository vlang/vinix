# Opt-in encrypted boot unlock

`boot-restore` can restore one encrypted mapping from private root-owned fixed
configuration/credential files, alongside the plain saved set. `boot-unlock`
executes the same optional encrypted path alone. See
[commands, trust policy and limits](../../docs/storage-volumes.md#opt-in-encrypted-boot-unlock).

The native sanitizer suite checks empty sets, shared and different physical
identities, duplicate global slots, overlapping and touching extents, readonly
metadata, invalid cached slots/counts and geometry near the full `u64` bound.
Preflight preserves every caller field. Invalid command arity rejects before IO.

The discovery syscall model exercises the actual private descriptor reader,
canonical codec, boot loader/dispatcher, scanner, retained-fd rechecks and
import control flow. It checks root-only operation and directory/file trust;
absent directories/configuration; missing credentials; bad owner/permissions;
symlinks; malformed/tampered input; exact binary credential bytes; short/EINTR
or failed reads; ownership changes after EOF; directory changes after KDF or
plain restore; duplicate plain slots/extents; and renamed/replaced configuration
paths during derivation. It retains the earlier identity, clone/alias, native
sector, RW/RO, discovery/import/report fault and cleanup matrix. Credentials and
wrapping buffers erase before scanning, every opened descriptor balances, and
the full secret workspace erases on every return. Source files remain intact.

Both guests run four warmup and four measured full-cost boot-unlock/remove
lifetimes, with reader warmup and ordinary grace reclamation before exact
slab/large-page comparisons. No raw keyfile is used by the command. The first
boot saves a private readonly encrypted configuration after all earlier cohorts
and the unchanged 400-cycle regression. After device reordering, production init
must unlock it before the guest workload; the guest checks original and extended
plaintext, readonly enforcement and removes the live view before later tests.
Explicit boot unlock covers writable/saved-readonly data, bad credential/mode,
symlink/tamper refusal, occupied-slot preservation and disable semantics.

Old physical capacity refuses at boot. A deliberately installed larger-capacity
configuration unlocks on the next boot with its initialized extension intact.
Physical contraction refuses; the guest then disables that optional configuration
so the remaining plain boot regression keeps its original success expectations.
All previous cohorts, nine boots and the 1800-second deadline remain. Frozen
isolated ALLOC_TRACK kernels are reused; no kernel source changes are required.
Both target allocation audits and independent source/actual generated-C review
check the added lifetimes. Persisted configurations and raw ciphertext remain
available for independent crypto verification.

Plain restore and encrypted import are sequential; later failure can leave the
plain mappings live. Credentials need separately protected storage for offline
confidentiality. This supplies data-volume startup unlock after root is mounted;
encrypted-root boot, automatic mounts and interactive/hardware credential sources
remain separate work.

Qualification on 2026-10-13 passes all 38 ASan/UBSan suites, ten syscall
models, both init policy cases and both target allocation audits. Both
architectures finish all nine boots, the eight additional full-cost
boot-unlock/remove lifetimes and all earlier key/configuration and 400-cycle
workloads.

| Target | Boots | Boot unlock lifetimes | Slab classes, all deltas zero | Boot unlock large pages | Existing workload large pages |
| --- | --- | --- | --- | --- | --- |
| ARM64 | 9 | 4 + 4 | 18 | 80 → 80 | 98 → 98 |
| x86_64 | 9 | 4 + 4 | 14 | 201 → 201 | 243 → 243 |

The complete target utility C is byte-identical on both architectures, SHA-256
`5efc0892df5cdbdaef209722effb4d99b84426816ec0e90fdcb3442d247abd58`, with no implicit heap/runtime
dependencies. Independent source and actual native/model/target/guest C
lifetime review reports no unresolved issues. Independent OpenSSL scrypt and
ChaCha20 plus separate full HMAC checks verify the persisted configurations,
the exact boot configuration/credential pair and recovered key on both
architectures; an independent AES-XTS oracle matches original and extended
ciphertext sectors. Complete logs, C, persistent guest disks, review and
artifact manifests are retained locally under `logs/storage-volume-boot-work`;
the verified artifact manifest is
`logs/storage-volume-boot-work/artifacts/SHA256SUMS`. The first x86 attempt
timed out after 332 of 400 cycles and is retained as a failure. The second x86
attempt completed all 400 cycles but failed its strict heap
check at 219 to 243 large pages, with all slab deltas zero; that failure is
also retained. A fresh complete third x86 attempt used owned RAM scratch with
the unchanged source, workloads and
1800-second deadline. Its complete retained evidence and guest disks were
copied and checksummed on persistent storage before detaching the device.

Read-only snapshots in the passing run observe the frozen kernel deferred-free
queue at 2,048 entries of 96 bytes before the baseline, with capacity stable
throughout measurement. A 1,024-to-2,048 expansion would account for the earlier
24-page difference; the second attempt had no queue snapshots, so that
explanation remains an inference. All strict comparisons and workloads remain.
