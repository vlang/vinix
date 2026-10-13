# Authenticated encrypted-volume growth

`plan-grow-volume` authenticates a `VINIXVC1` configuration and publishes a
separate configuration retaining its key, identity, native sectors, slot, start
and readonly mode. Only nondecreasing physical capacity and extent length are
allowed. See [commands and limits](../../docs/storage-volumes.md#authenticated-encrypted-volume-growth).

The native ASan/UBSan suite covers MBR/GPT, 512/4096-byte sectors, RW/RO modes,
equal/growing lengths, unchanged/larger capacities and full-width bounds near
`u64` maximum. Wrong identities/kinds/sectors, shrinking capacity/length,
misalignment, overflow and out-of-bounds lengths reject. Encoded new geometry
authenticates into the exact original key and preserved metadata. A real bounded
KDF with binary credential bytes stays in this suite; syntax failures reject
before input access.

The extended configuration syscall model asserts authentication before parent
access, one retained read-only parent, exact credential length/bytes across both
derivations, zeroed derived-key buffer before reuse and erased credentials before
output-directory access. It exercises short binary and 1024-byte credentials,
unchanged/larger capacities, equal/growing/boundary extents, wrong authentication,
unsupported/offline/changed devices, short/EINTR/failed reads, parent/entropy/KDF
failures, invalid wrapping keys, pre-KDF and locked pre-publication rechecks,
every existing publication/cleanup/durability/reporting fault, tampering and
existing destination files, aliases, symlinks, FIFOs and directories. Failures
retain descriptor balance, full secret-state erasure, no import and preserved
inputs. Any complete output after a publication fault authenticates into the
same key and proposed geometry.

Both guests delete the raw key before planning RW/RO growth. Planning leaves a
live mapping's old length/generation intact; a separate live grow preserves its
held descriptor, old plaintext, extension plaintext and original ciphertext.
Import refuses an occupied extension, then succeeds after the blocker is
removed. New configurations reopen both modes, preserve source/existing output,
and recover the exact original key only on explicit request. Reordered reboot
repeats access. After physical expansion, a new configuration adopts the larger
capacity and a further extent extension; initialized extension bytes and saved
RO mode survive reboot. Subsequent physical contraction rejects that configuration.

A separate cohort performs four warmup and four measured plan/open/remove
lifetimes, three production KDFs per lifetime. Reader warmup and ordinary grace
reclamation precede strict slab/large-page equality. All previous key/configuration
cohorts, 400 storage/mapper/recovery lifetimes, nine boots and the 1800-second
deadline remain. Frozen isolated ALLOC_TRACK kernels are reused because no
kernel code changes. Both target allocation audits and independent source/actual
native/model/target/guest C review check all added lifetimes. Planning does not
initialize device bytes, reserve extents, resize filesystems, rotate volume keys,
authenticate data ciphertext or supply encrypted-root boot.

Qualification on 2026-10-13 passes all 37 ASan/UBSan suites, ten syscall
models, both init policy cases and both target allocation audits. Both
architectures finish all nine boots, the eight additional full-cost encrypted growth
plan/open/remove lifetimes and all earlier key/configuration and 400-cycle workloads.

| Target | Boots | Growth lifetimes | Slab classes, all deltas zero | Growth large pages | Existing workload large pages |
| --- | --- | --- | --- | --- | --- |
| ARM64 | 9 | 4 + 4 | 18 | 80 → 80 | 98 → 98 |
| x86_64 | 9 | 4 + 4 | 14 | 201 → 201 | 243 → 243 |

The complete target utility C is byte-identical on both architectures, SHA-256
`9cc3f99e45122d6e15244073320292abcf0406e3b51142ca2af4d2db6de7821a`, with no implicit heap/runtime
dependencies. Independent source and actual native/model/target/guest C
lifetime review reports no unresolved issues. Independent OpenSSL scrypt and
ChaCha20 plus separate full HMAC checks verify the persisted configurations
and exact recovered key on both architectures; an independent AES-XTS oracle
matches original and extended ciphertext sectors. Complete logs, C, persistent
guest disks, review and artifact manifests are retained locally under
`logs/storage-volume-growth-work`; the artifact manifest is
`logs/storage-volume-growth-work/artifacts/SHA256SUMS`. Rebuildable files
used owned RAM scratch to avoid shared-disk pressure; retained evidence is
copied back and verified before that scratch is detached.
