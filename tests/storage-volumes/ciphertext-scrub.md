# Persistent ciphertext scrub qualification

`scrub-volume` and `scrub-recovery-volume` authenticate VC1/VR1 geometry, erase
secrets and read the complete ciphertext extent before privately publishing a
fixed `VINIXCS1` report. Clean/changed returns 0/2; operational errors override
the finding and return 1. `show-volume-scrub` validates complete historical
reports offline and returns 0 for either valid finding. Trusted references and
quiescent writes remain required; this is neither snapshot nor plaintext
authentication. See [the contract](../../docs/storage-volumes.md#persistent-encrypted-ciphertext-scrub-findings).

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-ciphertext-scrub --work /tmp/ciphertext-scrub-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --ciphertext-scrub --work /tmp/ciphertext-scrub-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --ciphertext-scrub --work /tmp/ciphertext-scrub-x86
```

The scoped host executes both independent authenticated codecs, the new native
codec/syntax and the combined prior/new actual private-reader, publisher and
physical-probe model under ASan/UBSan. Sixteen format/identity/native-sector/mode
profiles exercise clean/changed 73728-byte streams across both chunks, independent
digest/fingerprint/report text, all thirty physical modes, invalid transfers,
post-read/post-lock changes, complete operational error precedence and preserved
old files. Direct input sizes/permissions/symlinks, damaged envelopes, wrong
credentials/KDF outputs and reference geometry failures precede hardware access.
Offline cases check no hardware/KDF/publication, exact reports and private input
policy. Native cases check every byte, repaired CRCs, result/digest consistency,
reference SHA, signed/SHA bounds and transactional decode/output preservation.
Only the fixed KDF is mocked in the syscall model; parsing, authentication,
stream hashing, report codecs, publication and secret erasure execute unchanged.

Guests use the actual CLI and full-profile scrypt on disposable VirtIO/AHCI
media. Both saved modes/domains produce matching clean/changed reports, retain
all six envelope/reference inputs and refuse existing destinations, wrong disks,
wrong passphrases and invalid recovery-file lengths. Controlled physical
corruption is restored before held-mapping and plaintext checks. Four warmup
and four measured cycles each run VC1 scrub, VR1 scrub and offline viewing,
then remove reports and wait thirteen seconds for reclamation. Every warmed
slab class and large-page count must remain equal. All eight historical reports
persist across reordered reboot; a fresh recovery scrub still sees matching
data, followed by a separate explicit recovery unlock.

`volume_ciphertext_scrub_artifacts.v COMPLETED_GUEST_WORK NEW_OUTPUT` constructs
all bytes of both references and all eight reports independently, including
every reserved field and CRC, OpenSSL clean/corrupt extent digests and OpenSSL
reference fingerprints. Existing VC1/VR1 metadata/key/AES-XTS oracles remain
unchanged. Complete utility/guest C receive allocation audits and independent
lifetime review. Frozen isolated ALLOC_TRACK kernels remain unchanged; no
kernel implementation changes are part of this feature.

## Qualification on 2026-10-13

Final `host-2`, `arm-1` and `x86-1` receipts are zero. The scoped host passed
ASan/UBSan with no sanitizer or undefined-behavior error, and all four guest
boots passed. The initial `host-1` failure was an incorrect test expectation:
changing one observed digest byte in a changed report still leaves a valid
changed finding. The corrected case sets the entire observed digest equal to
the expected digest while retaining changed=1 and repairing CRC. Only the
model test changed; the failed receipt is retained. Production and guest
sources stayed unchanged during final qualification.

| Guest | Warmup + measured cycles | Slab classes with zero delta | Large pages before → after |
| --- | --- | --- | --- |
| ARM64 | 4 + 4 | 18 | 72 → 72 |
| x86_64 | 4 + 4 | 14 | 194 → 194 |

Each cycle runs one full-profile passphrase scrub, one recovery scrub and one
offline view: 24 utility lifetimes, eight 32-MiB KDF allocations, eight VR1
scrubs and eight offline views per architecture across both phases. Separate
report, refusal, corruption and held-mapping cases precede measurement.
Valid-size wrong recovery keys and injected KDF failures are host-model cases;
guests directly exercise a real wrong passphrase and invalid recovery-file
length.

Both persisted guests' two references and eight reports match independently
constructed exact bytes, including nested/whole CRCs and reference fingerprints.
V standard-library SHA and OpenSSL agree on the full clean ciphertext digest
`115d50809715a805656e2c32b2d84ce5b4df581c65e1ec9b4523df3f9e4a6748`
and controlled changed digest
`a45c3043d314e557b22fa0a7dc53957b2dd84154fedd0865703a1796c63bbc25`.
OpenSSL also verifies both reference fingerprints. Ten oracle invocations pass:
two new scrub checks, four VC1/VR1 checks on the new media, and retained
ciphertext, growth, credential rotation and sealed recovery checks. All six
preceding oracle modes and their source remain unchanged.

Independent source/generated-C and lifetime review found no unresolved issue.
It checks all ten workspace wipe/edit-close exits and five pinned-parent close
exits, secret erasure before reference/device/output access, bounded stack
streaming and unchanged KDF erase/release ordering. All 274 preceding production
bodies remain identical; shared production changes are dispatcher/usage additions
and the publisher's exact 224-byte size allowance. Actual fixture sources and
all seven merged test bodies match their documented transformations, and 39
normalized production/model C bodies match. Both complete utility targets and
actual selected guest programs pass allocation/runtime dependency audits.

Retained evidence is under `logs/storage-ciphertext-scrub-work`: successful and
initial failed receipts, complete generated C, persisted media, ten oracle
directories, final sources, frozen kernel/input receipts, independent review
and SHA-256 manifests. The V transport copy changes only its private
bootloader-cache path and established QEMU foreground/task-priority wrapper;
workload bodies match the public controller. Its owned temporary RAM compiler
volume is released before archiving evidence.

This qualifies the scoped host and disposable QEMU scenarios. Unrelated full
native, desktop, nine-boot saved-plan and physical hardware qualification remain
separate. Trusted-reference and quiescent-write requirements still apply;
reports are historical findings, without snapshot, plaintext authentication,
malicious-reference authentication or repair guarantees.
