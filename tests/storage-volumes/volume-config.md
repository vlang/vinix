# Authenticated encrypted-volume configuration qualification

`seal-volume`, `open-volume` and `unseal-volume-key` use the fixed 320-byte
`VINIXVC1` format documented in [storage volumes](../../docs/storage-volumes.md#authenticated-encrypted-volume-configurations).
It binds the whole physical disk's identity/geometry and one mapping's slot,
extent and mode to its wrapped volume key. The kernel mapper is unchanged.

The native ASan/UBSan cipher suite covers MBR/GPT identifiers, both 512/4096-byte
native sectors and both modes; exact keys and metadata roundtrip. An independent
HMAC implementation checks the complete transcript. All 2560 envelope bit
mutations and 512 wrapping-key bit mutations fail without changing any caller
disk/request/key sentinel. Unsupported work profiles, reserved bytes, invalid
authenticated geometry and invalid authenticated XTS keys fail closed. Geometry
tests include zero/unsupported sectors, alignment, overflowed starts/lengths and
out-of-range extents. Invalid CLI syntax rejects before input or device access.

The new syscall model runs the production authenticated load/codec and pinned
physical-disk probes. It covers all identifier/sector/mode combinations, optional
RO restriction and saved RO enforcement, private offline recovery, balanced
descriptors and full secret-workspace erasure. Wrong wrapping keys and hostile
headers never open the parent. Offline/partition/mapper/invalid-table probes,
short/interrupted reads, source identity/sector/capacity/runtime-id/readonly
changes on the final probe and failed imports reject before mutation. Publication
tests preserve file/directory locks, exclusive private temporaries, no-overwrite
links, exact outputs, cleanup and pre/post-publication error semantics. Existing
KDF allocation, all-vector erasure, release-error and EINTR tests stay enabled.

Guests create RW and saved-RO configurations for existing real ciphertext,
preserve existing outputs, reject changed authenticated fields and wrong
credentials, delete their raw keyfile, reject another physical disk and regular
file parents, then unlock without separate geometry. Forced RO and saved RO both
refuse writable access. Explicit private recovery restores the exact original
key. After physical device reordering and reboot, direct unlock still works
while the raw keyfile is absent. A later physical capacity change must reject the
old configuration without importing a mapper.

A separate cohort runs four warmup and four measured create/open/recover
lifetimes. Each lifetime uses three production-profile KDFs with 32 MiB vectors.
Both snapshot readers are warmed and ordinary deferred reclamation elapses
before comparing every slab class and large-page count for exact equality.
Earlier sealed-key and credential-rewrap cohorts, 400 encrypted mapper lifetimes,
400 key-recovery pairs, 400 forty-one-command storage cycles, nine boots and
the original 1800-second deadline all stay enabled. Frozen isolated ALLOC_TRACK
kernels are reused because this increment changes no kernel source.

An independent persisted-artifact oracle verifies exact canonical configuration
metadata and complete tags, derives wrapping keys with OpenSSL 3 and unwraps
the key ciphertext with OpenSSL ChaCha20. Both RW/RO configurations must recover
the exact post-reboot volume key. Source and actual native/model/target/guest
generated C are independently reviewed for hidden allocations and lifetimes.
Partition identifiers are not unique hardware authentication, and sampled
verification cannot stop privileged metadata changes after its final check.

Qualification on 2026-10-13 passes all 34 ASan/UBSan utility suites, nine syscall
models, both init policy cases and both target allocation audits. ARM64 and
x86_64 each complete all nine boots, the eight new full-cost configuration
lifetimes, sixteen earlier sealed-key lifetimes, eight credential-rewrap
lifetimes and the unchanged 400-cycle storage, encrypted-mapper and key-recovery
workloads.

| Target | Configuration lifetimes | Slab classes, all deltas zero | Configuration large pages | Existing workload large pages |
| --- | --- | --- | --- | --- |
| ARM64 | 4 warmup + 4 measured | 18 | 80 → 80 | 98 → 98 |
| x86_64 | 4 warmup + 4 measured | 14 | 201 → 201 | 219 → 219 |

The independent persisted-artifact oracle verifies both RW/RO configurations
on both architectures with OpenSSL 3 scrypt and ChaCha20, separate full HMAC
checks and exact post-reboot key recovery. Independent source and actual
native/model/target/guest generated-C lifetime/security review is clean. Both
production target C files match the reviewed SHA-256
`00f48f7849a1368a24d037ecc04d6172d69285066a26f12302f3400d84e2c7e7`.
The first x86 run ended without a verdict and a compilation retry hit host disk
exhaustion; the final fresh x86-3 run repeats every assertion, cycle and boot.
Its guest C is byte-identical to the independently reviewed initial x86 C.
Local records are retained in
`logs/storage-volume-seal-validation.md`,
`logs/storage-volume-seal-work/artifacts/SHA256SUMS`,
`logs/storage-volume-seal-work/{host-1,arm-1,x86-3}.log`,
`logs/storage-volume-seal-artifacts.log` and `logs/storage-volume-seal-review.md`.
