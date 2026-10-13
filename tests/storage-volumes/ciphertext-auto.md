# Automatic ciphertext checksum qualification

`hash-volume-auto`/`verify-volume-auto` and
`hash-recovery-volume-auto`/`verify-recovery-volume-auto` authenticate and erase
secrets before retaining the existing read-only identity-discovery pin.
Verification validates its complete private reference before discovery. Exact
`VINIXCH1` bytes, complete extent hashing, output and no-overwrite publication
match explicit-device commands. See [the contract](../../docs/storage-volumes.md#identity-based-automatic-ciphertext-checksums).

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-ciphertext-auto --work /tmp/ciphertext-auto-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --ciphertext-auto --work /tmp/ciphertext-auto-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --ciphertext-auto --work /tmp/ciphertext-auto-x86
```

The scoped host runs existing authenticated/reference/scrub codecs and syntax,
the extended RecoveryIO integration model and the unchanged actual discovery
model under ASan/UBSan. The new integration model substitutes the discovery
boundary and fixed KDF, while executing actual authentication, private readers,
erasure, streaming SHA, pinned rechecks, publication and output finalization.
Sixteen VC1/VR1, MBR/GPT, 512/4096-sector and saved-mode profiles check zero
discovery after credential/reference failures, erased secrets before discovery,
one returned parent pin with no reopening, and complete 73728-byte two-chunk
reads. Exact output/reference bytes, independently hashed changed bytes, all
thirty physical modes, twelve streaming modes, publication/output faults,
descriptor balance and complete workspace wipes are checked. Discovery-selected
physical ID/mode changes fail the first recheck. A CRC-repaired geometry mismatch
fails before discovery; a CRC-repaired digest mismatch requires the complete
scan before failure. Verification creates no directory, lock or output file.

The separately executed discovery model uses the complete real bounded scan,
candidate identity/type/probe paths, physical-alias acceptance, distinct-disk
ambiguity refusal, enumeration/read faults and pin/directory cleanup. This
component coverage is separate from the injected integration boundary. Both
actual guests run real discovery and authentication together.

Each selected guest first runs the unchanged explicit-device checksum workload.
Automatic creation then produces four references for both credential domains
and saved modes, each identical in all 128 bytes to its manual counterpart.
Own- and cross-domain verification, existing-output refusal, opposite-mode
references, wrong credentials and controlled physical corruption are checked.
Corruption is restored and flushed. A held live mapping keeps its complete
status, generation/counters and plaintext reads while automatic verification
uses the physical parent. No mapper import or raw key output occurs.

Four warmup and four measured pairs run automatic VC1 creation and automatic
VR1 verification, remove each reference, and wait thirteen seconds before
comparing every warmed heap class and retained large pages. These add sixteen
utility lifetimes and eight real full-profile 32-MiB passphrase KDFs per
architecture, alongside the original manual cycles' sixteen lifetimes/eight
KDFs. Both reordered second boots run all domain/mode combinations without a
physical pathname, then separately unlock preserved data.

The new artifact oracle imports no producer codec. It independently constructs
eight exact manual/automatic CH1 references per persisted guest, including
geometry, reserved bytes and bitwise CRC. V standard-library SHA and OpenSSL
verify the full physical extent digest and established AES-XTS fingerprint.
All prior artifact oracle sources remain unchanged. Complete utility and actual
selected guest C receive allocation audits and independent lifetime review.
Frozen isolated ALLOC_TRACK kernels remain unchanged; this feature changes no
kernel implementation.

## Qualification on 2026-10-13

`host-2`, `arm-2` and `x86-2` exit receipts are zero. The scoped host passed
ASan/UBSan without sanitizer or undefined-behavior errors; all four guest boots
passed. Production and guest sources stayed unchanged across retries and final
qualification.

| Guest | New warmup + measured pairs | New utility lifetimes | Slab classes with zero delta | Large pages before → after |
| --- | --- | --- | --- | --- |
| ARM64 | 4 + 4 | 16 | 18 | 72 → 72 |
| x86_64 | 4 + 4 | 16 | 14 | 191 → 191 |

Each architecture completed eight new real 32-MiB passphrase KDF allocations
and eight new recovery verifications in these pairs. The unchanged preceding
explicit-device cycles also passed, with another sixteen lifetimes/eight KDFs
and the same flat retention counts. Both reordered second boots rediscovered
the correct physical disk for all domain/mode combinations and reopened the
preserved plaintext through a separate recovery unlock.

Thirteen independent persisted artifact oracle invocations passed. The two new
oracles checked eight manual/automatic references on each guest against exact
independently constructed bytes and full-extent V/OpenSSL SHA-256. All eight
preceding artifact modes passed through unchanged oracle sources: automatic
scrubbing, manual scrub findings, ciphertext references, ordinary VC1, recovery
VR1, recovery growth, recovery credential rotation and sealed recovery. Guest
physical corruption was restored; the complete 4096-byte ciphertext digest is
`115d50809715a805656e2c32b2d84ce5b4df581c65e1ec9b4523df3f9e4a6748`.

The first host build encountered linker ENOSPC on the shared host disk, and
ARM serial capture stopped mid-line during the same disk exhaustion. Their
runners could not publish exit receipts. The owned first x86 QEMU was stopped
after its serial log remained empty through that incident. No first attempt
counts as qualification; partial media, logs and generated C are retained.
Identical sources, controller and toolchains were retried in fresh directories
after space returned. Closed owned boot transport images are retained as `.gz`
with SHA-256/length receipts and verified decompression before removing originals;
physical media and generated C remain unchanged.

Independent source/generated-C and lifetime review checks the four dispatcher
branches, secret/reference ordering, selected pin ownership, complete scan and
publication/output cleanup. All 287 other prior production bodies remain
unchanged. The shared hash/verify body matches its predecessor after only its
two documented parent-opener/initial-check substitutions. The existing helper
bodies remain unchanged and their manual branches reproduce the old behavior.
All ten workspace-wipe and four pinned-parent-close exits remain complete.
Ten RecoveryIO and four actual discovery fixture source bodies match their
public sources after explicit transformations; forty-four RecoveryIO and eight
discovery C bodies match normalized production. Both architecture targets are
identical and allocation-free; selected guest programs pass allocation audits.
The review found no unresolved correctness or lifetime issue.

The inherited extra `perror` following a logical discovery refusal may append
uninformative system-error text after the precise refusal. Status remains 1,
with no successful checksum output or publication.

Retained evidence is under `logs/storage-ciphertext-auto-work`: successful
receipts, earlier partial attempts, full generated C, physical media, compressed
boot images/original hashes, oracle outputs, final sources, frozen kernel/input
receipts, independent review and SHA-256 manifests. The V transport copy changes
only its private bootloader-cache path and established QEMU foreground/worker
priority wrapper; workload bodies match the public controller. Its owned RAM
compiler volume is released before evidence is archived.

This is a scoped host and disposable QEMU matrix; full native, desktop,
saved-plan and physical hardware qualification remains separate. Trusted
references and quiescent writes remain required; scans provide no snapshot,
plaintext or malicious-reference authentication, or repair guarantee.
