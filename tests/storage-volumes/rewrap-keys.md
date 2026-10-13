# Sealed-key credential rewrap qualification

`rewrap-key` uses the existing authenticated `VINIXKP1` envelope and fixed scrypt
profile. It preserves the volume key and publishes a separate envelope using new
private credential bytes, fresh salt and nonce. See [commands, ordering and
access-retirement limits](../../docs/storage-volumes.md#changing-sealed-key-credentials).

The native ASan/UBSan suite rewraps a 1024-byte binary credential to a short input
containing NUL, newline and non-ASCII bytes, with the raw volume keyfile removed.
It checks private mode 0600, fresh salt/nonce, exact 64-byte recovered keys, wrong
old credentials, continued original-envelope access, same-credential refresh,
existing files, hardlink aliases, dangling symlinks, FIFOs and directories. Both
credential files and source/destination envelopes retain their exact bytes.
CLI arity and empty paths reject before input I/O.

The extended sealed-key syscall model checks old authentication before opening
the new credential, erasure of old passphrase/derived-key bytes, zeroed unused
suffixes before a short new credential's KDF, new input access/ownership/mode/EOF
faults, second-stage derivation failure, invalid wrapping-key rejection and
entropy failure. It retains the existing publication, cleanup, durability and
stdout fault matrix, descriptor balance, no parent/ioctl access, complete normal
return workspace erasure and unrelated temporary-name preservation. Real-KDF
allocation, full 32 MiB erasure, unmap refusal and EINTR coverage stay enabled.

Each guest deletes the raw keyfile before rewrapping. It checks wrong old
credentials, binary new credentials, fresh salt/nonce, private publication,
preserved source/existing output, same-key direct RW/RO access and old-credential
rejection against the new envelope. Explicit unsealing recovers the original
volume key. After reboot and physical device reordering, the raw key is deleted
again before direct unlock with the new credentials.

A separate cohort runs four warmup and four measured rewrap/unlock/unseal
lifetimes. Each lifetime runs four production-profile KDFs: old-key load,
new-key derivation, direct unlock and explicit unseal. Both snapshot readers are
warmed and ordinary reclamation grace periods elapse before comparing every
slab class and large-page count for exact equality. The earlier sixteen full-cost
sealed-key cycles, 400 encrypted mapper lifetimes, 400 recovery pairs, 400
forty-one-command storage cycles, nine boots and 1800-second deadline remain.
Frozen isolated ALLOC_TRACK kernels are reused because no kernel code changes.

Source and actual native/target/guest generated C are reviewed for secret
lifetime and hidden allocations. An independent persisted-artifact oracle
compares original and rewrapped envelopes, derives their wrapping keys with
OpenSSL 3, verifies full tags using a separate HMAC implementation and unwraps
both ciphertexts using OpenSSL ChaCha20 into the exact same post-reboot volume
key. Retained old-envelope access is intentional; this changes credentials,
while volume-key rotation and encrypted-root boot remain separate work.

Qualification on 2026-10-13 passes all 33 ASan/UBSan utility suites, eight syscall
models, both init policy cases and both target allocation audits. ARM64 and
x86_64 each complete all nine boots, sixteen sealed-key cycles, and the unchanged
400-cycle storage, encrypted-mapper and key-recovery workloads.

| Target | Rewrap lifetimes | Slab classes, all deltas zero | Rewrap large pages | Existing workload large pages |
| --- | --- | --- | --- | --- |
| ARM64 | 4 warmup + 4 measured | 18 | 80 → 80 | 98 → 98 |
| x86_64 | 4 warmup + 4 measured | 14 | 201 → 201 | 243 → 243 |

The independent persisted-artifact oracle verifies both original/new canonical
envelopes and fresh salt/nonce, derives their keys with OpenSSL 3, checks complete
HMAC tags separately, and unwraps both into the exact post-reboot volume key.
An independent old-passphrase derivation fails authentication for the new
envelope. Source and actual native/model/target/guest generated-C lifetime/security
review reports no unresolved issue. Both production target C files match the
reviewed SHA-256
`97a67317ebc3738600c9e9612fabd164c967d46cb8200901aa2c007afc88ec13`.
Local records are retained in
`logs/storage-rewrap-validation.md`,
`logs/storage-rewrap-work/artifacts/SHA256SUMS`,
`logs/storage-rewrap-work/{host-2,arm-3,x86-2}.log`,
`logs/storage-rewrap-artifacts.log` and `logs/storage-rewrap-review.md`.
