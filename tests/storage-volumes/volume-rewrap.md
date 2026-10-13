# Encrypted-volume configuration credential changes

`rewrap-volume` uses the existing authenticated 320-byte `VINIXVC1` format and
fixed scrypt profile. It preserves the exact volume key, whole-disk identity,
native geometry, slot, extent and readonly mode while publishing a separate
private configuration with new credential bytes and fresh salt/nonce. See
[commands and access-retirement limits](../../docs/storage-volumes.md#changing-encrypted-volume-configuration-credentials).

The native ASan/UBSan suite changes a 1024-byte binary credential to a short
credential containing NUL, newline and non-ASCII bytes. Every MBR/GPT identity,
512/4096-byte sector and RW/RO combination retains its exact metadata and key.
Real bounded scrypt derivations validate the new credentials. Tests check private
mode 0600, fresh salt/nonce, old-credential rejection for the new configuration,
continued original access, exact offline recovery, same-credential refresh,
preserved credential/source/destination bytes, existing files, hardlink aliases,
symlinks, FIFOs and directories. CLI syntax rejects before input access.

The extended configuration syscall model verifies old authentication before
new input/output access, complete old credential/derived-key erasure before
reuse, and a zeroed unused suffix during the new KDF. New input length, type,
permission, missing-file and symlink failures, old/new derivation failure,
invalid/reused wrapping keys and entropy failure publish nothing. Every
publication, cleanup, durability and reporting fault retains descriptor balance,
full workspace erasure, no parent/ioctl access and preserved inputs. Complete
outputs after publication remain authentic and recover the same metadata/key.
The earlier real-KDF mapping allocation/erasure/unmap/EINTR model stays enabled.

Both guests remove raw keys before changing credentials for RW and saved-RO
configurations. They verify fresh salt/nonce and exact metadata, preserved source
and existing output, old-credential rejection, binary new credentials, wrong-disk
refusal, direct writable/readonly access and continued original access. Unlock
creates no raw keyfile; explicit recovery restores the original key. Reordered
reboot repeats keyless access and saved readonly enforcement. Later physical
capacity changes must reject the rewrapped configuration before mapper import.

A separate cohort runs four warmup and four measured rewrap/open/recover
lifetimes, four production KDFs per lifetime. Both measurement readers warm and
ordinary deferred reclamation elapses before strict slab/large-page comparisons.
Earlier sixteen sealed-key, eight key-credential-rewrap and eight configuration
lifetimes, all 400 encrypted mapper/key-recovery/storage cycles, nine boots and
the 1800-second deadline remain. Frozen isolated ALLOC_TRACK kernels are reused
because no kernel source changes.

An independent persisted-artifact oracle derives old/new wrapping keys with
OpenSSL 3, checks full HMAC transcripts separately and unwraps both RW/RO pairs
with OpenSSL ChaCha20 into the exact post-reboot key. Metadata and salt/nonce
preservation/freshness are checked independently; old credentials fail the new
tag. Source and actual native/model/target/guest C receive an independent lifetime
review. Preserved old configurations retain access; rewrapping does not rotate
volume keys, validate present physical disks, revoke old copies or supply
encrypted-root boot.

Qualification on 2026-10-13 passes all 35 ASan/UBSan utility suites, nine syscall
models, both init policy cases and both target allocation audits. Both
architectures complete all nine boots, the eight new full-cost configuration
rewrap lifetimes, every earlier key/configuration cohort and the unchanged
400-cycle storage, encrypted-mapper and key-recovery workloads.

| Target | Rewrap lifetimes | Slab classes, all deltas zero | Rewrap large pages | Existing workload large pages |
| --- | --- | --- | --- | --- |
| ARM64 | 4 warmup + 4 measured | 18 | 80 → 80 | 98 → 98 |
| x86_64 | 4 warmup + 4 measured | 14 | 201 → 201 | 243 → 243 |

Independent OpenSSL 3 derivations and ChaCha20 unwraps, separate full HMAC
checks and exact post-reboot keys pass for both original/new RW/RO pairs on
both architectures. Old credentials fail the new configuration tags. Independent
source and actual native/model/target/guest lifetime review is clean. Both
production target C files match the reviewed SHA-256
`9549523236eac98fc66705055d3ad6ab40198d4a86fa68bd1e51a288a0d8483d`.
Initial guest strict builds caught a fixture C-string pointer mismatch, corrected
with explicit casts. Initial host compilation hit shared-disk ENOSPC. Fresh
run 2 repeats every assertion and original deadline; failed evidence is retained.
Local records: `logs/storage-volume-rewrap-validation.md`,
`logs/storage-volume-rewrap-work/artifacts/SHA256SUMS`,
`logs/storage-volume-rewrap-work/{host-2,arm-2,x86-2}.log`,
`logs/storage-volume-rewrap-artifacts.log` and `logs/storage-volume-rewrap-review.md`.
