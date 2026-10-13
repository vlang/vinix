# Encrypted block-volume qualification

The production mapper adds a 96-byte version-1 key import request at ioctl
`0x56560006`: the existing 32-byte volume request followed by 64 key bytes.
Status flag 64 identifies encrypted views. The public keyfile command and
format limits are documented in [storage volumes](../../docs/storage-volumes.md#keyfile-encrypted-block-volumes).

The host cipher suite uses the FIPS-197 AES-256 example and 60 aligned NIST CAVP
AES-256-XTS vectors (30 encrypt, 30 decrypt). The committed response fixture
records its official source and original SHA-256. Its complete-block prefixes
also match when a data unit is extended to 512 bytes without ciphertext stealing.
An independent oracle uses the standard-library AES block cipher and scalar
polynomial tweak advancement, comparing full two-sector ciphertext for native
512/4096-byte sectors at zero, one, a large 64-bit index and the final two valid
indices. Invalid lengths, unsupported sector sizes, index overflow, nil data,
cleared schedules and identical key halves reject before changing caller bytes.

The mapper model runs production encryption, volume ownership and extent policy
with host device/allocation boundaries. It covers allocation/budget refusal,
publication failure, read/write errors, short device completion, native 4096-byte
sectors, read-only mappings, growth and exact reopen data. Two hundred repeated
lifetimes check reference and resource-charge balance, workspace erasure before
free and cleared schedules while a removed descriptor remains alive.

CLI tests use real keyfiles and synchronous syscall fault boundaries. They
verify private mode/ownership, regular/exact-length requirements, symlink/FIFO
rejection, unequal key halves, short/interrupted reads, changed owner/length,
parent/ioctl failure, descriptor balance and erasure of the complete key import
request on every return. Plain-plan matching and growth reject encrypted status;
guests additionally preserve an existing plan when saving an encrypted disk fails.

Both isolated ALLOC_TRACK kernels build for ARM64 and x86_64. Guest qualification
runs positioned, vector and sendfile I/O, checks raw ciphertext and distinct
sector tweaks, and verifies growth, removal with an open descriptor, read-only
reopen and explicit keyfile reopen after physical device reordering. The existing
nine-boot storage controller, 200 warmup plus 200 measured forty-one-command
cycles, all prior storage assertions and the 1800-second boot deadline remain
enabled. Each warmup/measured cohort adds 200 encrypted import/write/read/remove
lifetimes before the ordinary deferred-reclamation wait.

ASan/UBSan runs disable the existing host harness's leak detector. Generated-C
inspection and guest slab/large-page measurements supply allocation evidence.
The repository allocation audit reports existing sites above `allowed.txt` on
both the unchanged kernel and this change; comparison with the same compiler
finds identical per-file/per-kind counts. It does not treat those baseline
allowance failures as a clean full-audit result.

The cipher avoids secret-indexed lookup tables and secret-dependent source
branches. Temporary schedules and sector state use explicit stack workspaces;
generated C is inspected for implicit heap promotion. Volatile V byte stores
erase secret arrays and key-bearing utility requests. The mapper serializes key
use and erasure with removal, and kernel scalar/positioned/gather/sendfile scratch
buffers erase their allocated capacity before release. Caches, ordinary user
buffers and persistent keyfiles remain their owners' responsibility.

This qualifies confidentiality for the documented headerless native-sector
format. AES-XTS does not authenticate data or detect a wrong key. Passwords,
key recovery/rotation, encrypted-root boot, filesystem conversion and TRIM remain
outside this increment. The x86 snapshot path refuses unencrypted hibernation
after a privileged import attempt for the rest of the boot; this does not
classify arbitrary userspace key material before import.

Qualification completed on 2026-10-13: all 30 ASan/UBSan utility suites and six
fault models passed, together with the separate cipher, mapper and health models.
Both architectures completed all nine storage boots. Each ran 400 encrypted
lifetimes plus all 400 existing forty-one-command cycles: ARM64's 18 slab classes
and x86_64's 14 classes had zero deltas, and large pages stayed at 84 and 217
respectively. Independent reconstruction matched every byte of persisted XTS
units 0, 1, 2, 3 and grown unit 8 on both backing disks. All earlier plan,
checksum, corruption-report and persistence artifact assertions also passed.

The saved-v6 desktop harness completed all 43 syscall/churn/cache/idle/apps/drag
measurements with the isolated ARM kernel and a validated completion transcript.
Its broader retention measurements include nonzero values; this is not a claim
that every system workload is flat. The encrypted mapper's strict measured
workload, source/generated-C allocation audit and independent lifetime review
all passed. No new allocation-site counts appeared against the unchanged kernel;
the full allowance audit's baseline failures remain documented above.

Local evidence is retained under `logs/storage-crypt-work/artifacts`, with
controller transcripts in `logs/storage-crypt-work/{host,arm,x86}-2.log`, exact
ciphertext assertions in `logs/storage-crypt-cipher-artifacts.log`, and the
independent review in `logs/storage-crypt-lifetime-review.md`. The passing
desktop measurements are in `logs/storage-crypt-perf-4-results.json`; allocation
comparison is in `logs/storage-crypt-alloc-compare.log`.
