# Automatic encrypted-volume discovery

`open-volume-auto` authenticates a `VINIXVC1` configuration before scanning
`/dev`, then imports through the retained descriptor for its unique matching
physical disk. See [commands and limits](../../docs/storage-volumes.md#automatic-encrypted-volume-discovery).

The native syntax suite rejects missing/extra arguments, empty paths and invalid
mode overrides before input access. The new ASan/UBSan syscall model covers
MBR/GPT identities, 512/4096-byte sectors, RW/RO saved modes and forced readonly.
It asserts authentication before the device directory opens, full credential
and wrapping-key erasure before scanning, exact authenticated key/geometry at
import, descriptor balance and full workspace erasure on every return.

Tests accept physical aliases sharing runtime identity and skip symlinks,
regular files, partitions, mapper parents and unmanaged devices. Distinct
matching clones and no matching disk reject. KDF/tag failures, directory open,
fdopendir/readdir/fstatat/openat/fstat errors, status failures, offline disks,
wrong capacity, short reads, EINTR, writable reopen failure/identity change,
post-scan identity/geometry/readonly changes, import failure and reporting
failure are exercised. A directory exceeding 4096 entries rejects. Header,
metadata, ciphertext and tag tampering never start discovery, and input bytes
remain unchanged. Existing real-KDF and private-input tests remain enabled.

Both guest fixtures unlock RW and saved-RO configurations without a raw key,
accept physical aliases, reject a duplicated MBR identity and read the original
encrypted data from the expected physical disk. They repeat automatic unlock
after reboot with reordered devices and reject the saved configuration after
physical capacity changes. A separate cohort measures four warmup and four
full-cost automatic unlock/remove lifetimes, with reader warmup and deferred
reclamation before strict slab/large-page comparisons. Every previous workload,
all nine boots and the 1800-second deadline remain unchanged.

No kernel source changes are required; the frozen isolated ALLOC_TRACK kernels
are reused. Independent source/generated-C lifetime review and both target
allocation audits check descriptor ownership, secret erasure and hidden V
allocations. Explicit automatic discovery does not supply encrypted-root boot,
unattended credentials, key rotation or ciphertext authentication. Disk-table
identifiers can be cloned and uniqueness is sampled during discovery.

Qualification on 2026-10-13 passes all 36 ASan/UBSan suites, ten syscall
models, both init policy cases and both target allocation audits. Both
architectures finish all nine boots, the eight additional full-cost automatic
unlock lifetimes and all earlier key/configuration and 400-cycle workloads.

| Target | Boots | Unlock lifetimes | Slab classes, all deltas zero | Unlock large pages | Existing workload large pages |
| --- | --- | --- | --- | --- | --- |
| ARM64 | 9 | 4 + 4 | 18 | 80 → 80 | 98 → 98 |
| x86_64 | 9 | 4 + 4 | 14 | 207 → 207 | 243 → 243 |

The complete target utility C is byte-identical on both architectures, SHA-256
`1d45d7dc7f1a718ac24e583ee596ffe6cb53e6904ae3fc774809423732227a12`, with no implicit heap/runtime
dependencies. Independent source and actual native/model/target/guest C
lifetime review reports no unresolved issues. Independent OpenSSL scrypt and
ChaCha20 plus separate full HMAC checks verify the persisted configurations
and exact recovered key on both architectures. Complete logs, C, persistent
guest disks, review and artifact manifests are retained locally under
`logs/storage-volume-discovery-work`; the artifact manifest is
`logs/storage-volume-discovery-work/artifacts/SHA256SUMS`. Rebuildable files
used owned RAM scratch to avoid shared-disk pressure; retained evidence is
copied back and verified before that scratch is detached.
