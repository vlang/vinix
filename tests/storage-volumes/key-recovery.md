# Authenticated key recovery qualification

The `backup-key` and `recover-key` commands implement the exact 160-byte version-1
`VINIXKR1` format documented in [storage volumes](../../docs/storage-volumes.md#authenticated-volume-key-recovery).
Production cryptography, file validation and publication use V with fixed stack
workspaces. The existing kernel encrypted mapper and disk format are unchanged.

The host suite checks the [RFC 8439](https://www.rfc-editor.org/rfc/rfc8439)
ChaCha20 block vector, sixteen independent OpenSSL one-block comparisons, and
four [RFC 4231](https://www.rfc-editor.org/rfc/rfc4231) HMAC-SHA256 vectors. Another
1024 message lengths compare HMAC against the standard-library implementation,
and a separate full-envelope transcript verifies its tag. All 1280 single-bit
envelope changes and 512 single-bit recovery-key changes reject before changing
caller output. Every truncated/extra-length input, canonical reserved/header
field, reused key and identical-half key is rejected. Existing streaming SHA
boundary and million-byte vectors remain enabled with the new erasure paths.

Real-filesystem tests check private exact inputs, final symlinks, FIFOs, random
nonce uniqueness, exact restored bytes, output permissions, every existing
destination kind and preservation of both inputs. The synchronous syscall model
runs production code with short/interrupted reads and writes, failed/changed
source metadata, failed nonce devices, directory ownership/mode and writer-lock
refusal, create/chmod/write/flush/close/link/unlink faults, directory flush and
stdout errors. Every path balances descriptors and erases its complete key
workspace. Publication failures preserve preexisting outputs and never unlink
another invocation's temporary collision. After-publication faults retain the
complete private destination and fail the command.

Both guest architectures remove the original key, authenticate recovery, verify
all 64 bytes and mode 0600, then reopen and read the existing encrypted volume.
Wrong keys and changed backups never publish a keyfile or replace a prior one.
Each target adds 200 warmup and 200 measured backup/recovery lifetimes to the
unchanged 400 encrypted mapper lifetimes and forty-one-command storage cycles.
The original key is deleted again before shutdown; the next boot recovers it
from the persistent backup before reopening ciphertext after device reordering.
All nine storage boots and the 1800-second boot deadline remain enabled.

ASan/UBSan retains the host harness's existing disabled leak detector. Source
and generated-C review inspect explicit secret lifetime and hidden allocations;
guest slab/large-page comparisons measure retention. Frozen isolated ALLOC_TRACK
ARM64 and x86_64 kernels are reused because this change modifies no kernel code.
This validates authenticated key backup/recovery; passwords, key rotation,
authenticated disk data and encrypted-root boot remain separate work.

Qualification completed on 2026-10-13: all 31 ASan/UBSan utility suites, seven
syscall fault models and init policy cases passed. The final expanded recovery
suite also passed after adding existing-directory destinations and authenticated
invalid-XTS payloads; the fault model preserves all 64 unrelated temporary-name
collisions. Independent lifetime/security review passed for source and actual
native/target generated C after resolving three hidden metadata allocations.

Both targets completed all nine boots, 400 new backup/recovery lifetimes, 400
encrypted mapper lifetimes and all existing storage cycles. ARM64's 18 slab
classes and x86_64's 14 classes had zero deltas; large pages stayed at 96 and 241
respectively. After key deletion and reboot, a separate standard-library HMAC
implementation verified each persisted complete envelope and OpenSSL recovered
exactly the private key that reopened the volume. Both production target C
artifacts contain no heap or V runtime dependency.

Local evidence is retained under `logs/storage-recovery-work/artifacts`, with
its `SHA256SUMS` manifest, controller transcripts in
`logs/storage-recovery-work/{host-2,arm-4,x86-4}.log`, independent envelope checks
in `logs/storage-recovery-artifacts.log` and the review in
`logs/storage-recovery-review.md`. Earlier failed attempts remain available;
the final checks retain the original workload counts and boot deadline.
