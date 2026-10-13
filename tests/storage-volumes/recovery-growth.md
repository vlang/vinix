# Recovery volume growth and capacity adoption

See [commands and behavior](../../docs/storage-volumes.md#recovery-volume-growth-and-capacity-adoption).

```sh
sh build-support/run-v-tool.sh tests/storage-volumes/plan_run.v --host-recovery-growth --work /tmp/recovery-growth-host
sh build-support/run-v-tool.sh tests/storage-volumes/plan_run.v --arch aarch64 --kernel /path/to/arm/kernel/bin/vinix --recovery-growth --work /tmp/recovery-growth-arm
sh build-support/run-v-tool.sh tests/storage-volumes/plan_run.v --arch amd64 --kernel /path/to/x86/kernel/bin/vinix --recovery-growth --work /tmp/recovery-growth-x86
```

The scoped host run includes independent recovery codec checks, the extended
real recovery reader/publisher/device model and CLI syntax under ASan/UBSan.
New tests enter command dispatch across 512/4096-byte MBR/GPT geometry and RW/RO,
including high unsigned capacities with native-aligned signed mapping lengths.
Aligned lengths at 2^63 reject before device access. Shrinking, misalignment,
overflow and capacity bounds reject without publication. Successful outputs
preserve exact keys and all metadata except requested capacity/length, with
fresh nonces and untouched inputs.

The model observes wrapping/volume-key erasure before physical/directory opens
and every status/read probe. Authentication failures never open the physical
parent. The parent is read-only and pinned through all three probes; both final
identity, capacity, sectors, runtime identity, offline and physical-mode changes
reject. Faults also cover private readers, EOF/EINTR/short reads, entropy, locks,
temporary ownership, permissions, writes, flush/close/link/unlink/reporting and
no-overwrite input aliases. Every call balances descriptors/locks and erases the
whole workspace. No mapping import or KDF enters the growth operation.

Production guests create known ciphertext and RW/RO recovery backups, delete
raw keys, passphrases and ordinary configurations, then grow recovery extents
from 4096 to 8192 bytes. A live original mapping and retained descriptor remain
unchanged; planning preserves raw ciphertext. Reopening writes and checks the
new encrypted tail, saved RO and forced RO. Two hundred warmup and two hundred
measured plan/unlock/remove lifetimes require exact large-page and all-slab
equality after snapshot-reader warmup and thirteen-second reclamation.

The controller preserves the backing disk prefix while expanding it from
16 to 32 MiB between boots, then reorders physical devices. Old-capacity unlock
refuses. Explicit capacity adoption publishes 12288-byte RW/RO backups; the
same recovery credential reopens original data and both newly exposed tails.
Complete utility/guest C passes the allocation audit. Frozen isolated
ALLOC_TRACK kernels are reused, with no kernel source or ABI change.

`volume_recovery_artifacts.v COMPLETED_GUEST_WORK NEW_OUTPUT --recovery-growth`
independently checks persisted original, grown and capacity-adopted backups:
canonical full metadata, exact preserved key/mode, changed geometry, fresh nonce
and full HMAC/ChaCha20. Standard V AES-XTS checks actual ciphertext for native
units 0, 8 and 16, covering original data and both new tails. Existing oracle
modes remain available.

Qualification on 2026-10-13 passes the scoped independent codec/syntax suites,
extended real recovery/device model under ASan/UBSan, both complete target
allocation audits and both two-boot guests using production tools/init and the
default boot timeout. All runs pass on their first attempt. The unrelated full
native suite and nine-boot storage workload were not rerun for this addition.

| Target | Boots | Warmup + measured lifetimes | Slab classes, all deltas zero | Large pages |
| --- | --- | --- | --- | --- |
| ARM64 | 2 | 200 + 200 | 18 | 84 → 84 |
| x86_64 | 2 | 200 + 200 | 14 | 199 → 199 |

Both persisted backup and ciphertext oracles pass, including all three native
data units. Their AES-XTS SHA-256 values are:

| Native unit | Plaintext byte | Ciphertext SHA-256 |
| --- | --- | --- |
| 0 | `73` | `58d4a23c8dc7380e7069da904b7be35a5a844a9d6d1c744d531c960258cbbd22` |
| 8 | `a6` | `525711a8963ee94e79df14b506760586556b51ddde5b853ae984267d65e0c7d3` |
| 16 | `c2` | `b8fc6cfd42d21e6a3f12cd6232739d3c050a27eaa8539eab0db294f0b294342f` |

Existing unlock, credential-rewrap and sealed-recovery oracle modes pass
retained prior ARM64 media. Independent source/generated-C lifetime review
checks erasure before device access, all return cleanup, both final probes and
unchanged prior production bodies. The new producer enforces the kernel's
signed mapping-length bound; shared prior producers and codecs remain unchanged.

Persistent media, native/model/target/guest C, oracle outputs and final
source/review SHA-256 manifests are retained under
`logs/storage-recovery-growth-work`, with manifests in its `evidence` directory.
