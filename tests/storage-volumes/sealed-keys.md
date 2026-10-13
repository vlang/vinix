# Passphrase-sealed key qualification

The `seal-key`, `unseal-key` and `open-sealed` commands implement the separate
192-byte `VINIXKP1` format and fixed scrypt N=32768,r=8,p=3 profile documented in
[storage volumes](../../docs/storage-volumes.md#passphrase-sealed-volume-keys).
Production code is V with fixed stack workspaces and one bounded private 32 MiB
anonymous vector. The existing encrypted mapper and on-disk XTS format stay exact.

The host cipher suite checks two complete [RFC 7914](https://www.rfc-editor.org/rfc/rfc7914)
scrypt vectors, including empty inputs and sixteen independently mixed lanes.
Thirty-five OpenSSL comparisons cover N/r/p combinations, binary passwords and
lengths 1,32,63,64,65,127,1024. Another OpenSSL comparison verifies the actual
production profile and all 64 derived bytes. The HMAC transcript is checked with
an independent standard-library implementation. All 1536 single-bit envelope
mutations and 512 wrapping-key mutations reject with untouched output sentinels,
as do truncated/extra input, authenticated invalid XTS plaintext and noncanonical
metadata. Parameter limits reject before core workspace writes.

Real files check private ownership/mode, binary input length bounds, symlinks,
FIFOs, fresh salt/nonce values, wrong credentials, exact recovered key bytes and
mode 0600, input preservation and destination refusal. The synchronous syscall
model exercises interrupted/short reads and writes, source owner/mode changes,
entropy failure, destination policy/locks, publication and reporting faults,
temporary-name exhaustion and complete secret erasure on every normal return.
An isolated actual-KDF boundary checks mmap refusal, all vector bytes erased
before munmap, interrupted unmap retry and withheld output after release error.
Wrong credentials and hostile work-profile metadata never reach physical parent
opening or key import. RW/RO import requests, parent/ioctl failure and descriptor
balance are checked with the production authenticated load/import pipeline.

Each guest creates a sealed key, rejects wrong credentials without publishing or
importing, restores exact private bytes, deletes its original raw key, and
unlocks/read-writes the existing ciphertext directly in RW and RO modes. A
separate full-cost retention cohort runs eight warmup and eight measured
unlock/unseal pairs, reusing both snapshot readers and waiting for ordinary
deferred reclamation before comparison. That is sixteen direct encrypted imports
and sixteen private key publications using the real scrypt profile. Every slab
class and large-page count must stay equal. The existing 400 encrypted mapper
lifetimes, 400 recovery pairs, forty-one-command storage cycles, all nine boots
and the 1800-second boot deadline remain enabled. After reboot and physical
reordering, the raw key is deleted again before direct passphrase unlock.

ASan/UBSan retains the host harness's existing disabled leak detector. Source and
generated-C review check allocation/lifetime behavior, and guest counters measure
retention. Frozen isolated ALLOC_TRACK ARM64/x86_64 kernels are reused because
this feature adds no kernel code. KDF vectors are borrowed anonymous memory;
other production secret workspaces contain no hidden heap allocation or V runtime
dependency. The passphrase keyfile is authenticated; volume data, root unlock and
volume-key rotation retain their existing scope and limits.

Qualification on 2026-10-13 passes all 32 ASan/UBSan utility suites, eight syscall
models, both init policy cases and both target allocation audits. The final
expanded native suite also passes. Both architectures complete all nine boots
and the unchanged 400-cycle storage, encrypted-mapper and recovery workloads.

| Target | Full-cost unlock/unseal pairs | Slab classes, all deltas zero | Sealed large pages | Existing workload large pages |
| --- | --- | --- | --- | --- |
| ARM64 | 8 warmup + 8 measured | 18 | 78 → 78 | 98 → 98 |
| x86_64 | 8 warmup + 8 measured | 14 | 199 → 199 | 243 → 243 |

An independent persisted-artifact check derives each wrapping key with OpenSSL
3, verifies the complete envelope tag using a separate standard-library HMAC
implementation, and decrypts the ciphertext using OpenSSL ChaCha20. The result
matches the exact private key recovered after reboot on both guests. Independent
source and actual native/target/guest generated-C lifetime/security review finds
no unresolved issue. Both production target C artifacts are byte-identical and
match the reviewed SHA-256
`6510023f23a7e4efa9ae1d33eca766fd5998d292854899a2171dd65be1037de4`.
Local evidence is retained in `logs/storage-sealed-validation.md`,
`logs/storage-sealed-work/artifacts/SHA256SUMS`,
`logs/storage-sealed-work/{host-1,arm-2,x86-2}.log`,
`logs/storage-sealed-final-test.log`, `logs/storage-sealed-artifacts.log` and
`logs/storage-sealed-review.md`.
