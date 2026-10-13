# Encrypted ciphertext checksum qualification

The four `hash-volume`/`verify-volume` and recovery variants authenticate VC1/VR1
geometry, erase every secret, then stream SHA-256 from the entire pinned physical
extent. Private fixed `VINIXCH1` references bind exact public metadata, survive
credential changes and can be verified through either domain. They require a
trusted reference and quiescent data writes; they provide no snapshot or
plaintext authentication. See [the contract](../../docs/storage-volumes.md#encrypted-ciphertext-checksum-references).

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-ciphertext --work /tmp/ciphertext-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --ciphertext --work /tmp/ciphertext-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --ciphertext --work /tmp/ciphertext-x86
```

The scoped host runs both independent authenticated codecs, reference
syntax/codec and the combined existing/new actual reader/publisher/probe model
under ASan/UBSan. Sixteen format/identity/native-sector/saved-mode profiles test
exact reports and independent SHA-256 over 73728 bytes spanning two chunks.
EINTR/aligned short transfers, EOF/I/O/oversized/misaligned reads, corruption in
either chunk, all prior physical probe faults, post-read and post-lock identity,
geometry/mode changes, malformed/private/length/symlink inputs, credential/KDF
failures, repaired-CRC geometry/digest tampering, all no-overwrite publication
faults and report/flush/stream errors must preserve inputs and balance
descriptors. Observers require erased secrets before physical and report access.
Only the existing fixed KDF is mocked in this syscall model; parsing, crypto,
hashing, publication and erasure run unchanged. Native cases include full-width
capacities, SHA length boundaries and signed offset/end overflow.

Disposable ARM64 VirtIO and x86_64 AHCI guests execute the real CLI with real
scrypt. Both modes/domains produce byte-identical references, preserve existing
references on attempted replacement, reject wrong disks, saved modes, wrong
passphrases and invalid recovery-credential lengths,
detect and restore controlled physical corruption, and preserve a held live
mapping. Four warm and four measured pairs record through real VC1 KDF then
verify through VR1, remove the reference and wait thirteen seconds for
reclamation. Every warmed slab class and large-page count must stay equal.
References and credential envelopes persist across a reordered second boot;
verification creates no mapper, followed by a separate explicit recovery rescue.

`volume_ciphertext_artifacts.v COMPLETED_GUEST_WORK NEW_OUTPUT` independently
constructs every byte of the four persisted references, including CRC, and
compares the entire ciphertext extent with OpenSSL SHA-256. The unchanged
VC1/VR1 artifact oracle separately checks credentials, metadata, recovered keys
and native AES-XTS ciphertext. Complete target and guest C receive allocation
audits and an independent lifetime review. Frozen isolated ALLOC_TRACK kernels
remain unchanged; no kernel implementation changes are part of this feature.

## Qualification on 2026-10-13

Final `host-2`, `arm-2` and `x86-2` receipts are zero. Initial `-1` attempts
stopped during compilation of the new test helpers; those receipts are retained.
After correcting helper syntax and fixed-array references, the final scoped
host and all four guest boots passed without further implementation/test changes.
No sanitizer or undefined-behavior error appears in the final host run.

| Guest | Warmup + measured pairs | Slab classes with zero delta | Large pages before → after |
| --- | --- | --- | --- |
| ARM64 | 4 + 4 | 18 | 72 → 72 |
| x86_64 | 4 + 4 | 14 | 191 → 191 |

Each pair executes one real full-profile scrypt recording/publication and one
direct recovery verification, then removes the temporary reference: sixteen
utility lifetimes, eight 32-MiB KDF allocations and eight VR1 verifications per
architecture across warmup and measurement. The separate report, refusal,
corruption and held-descriptor scenarios precede these measured cycles.
Valid-size wrong recovery credentials and injected KDF failure/wrong/degenerate
outputs are host-model checks; guests exercise a real wrong passphrase and an
invalid recovery-credential length through direct CLI calls.

All four reference files from each persisted guest match the independent
byte-for-byte format/CRC oracle and OpenSSL full-extent digest:
`115d50809715a805656e2c32b2d84ce5b4df581c65e1ec9b4523df3f9e4a6748`.
The independent VC1 and VR1 oracles also authenticate both modes' metadata and
exact keys and verify original native-sector AES-XTS bytes. All five preceding
oracle modes run unchanged, including earlier growth, credential rotation and
sealed recovery media. Nine oracle invocations pass in total.

Independent source/generated-C and lifetime review checks all ten command
workspace wipe/edit-close exits and all four pinned-parent close exits, secret
erasure before device/reference/output access, bounded stack streaming and
KDF erase/release ordering. All 268 preceding production bodies remain identical.
Changes to shared production bodies are limited to dispatcher/usage additions
and the publisher's new fixed 128-byte size allowance, reviewed separately.
Exact fixture transformations and 31 normalized
model bodies match, and both actual guest entries execute the new scenario.
Complete target and guest C pass allocation/runtime dependency audits.

Retained evidence is under `logs/storage-ciphertext-work`: successful and early
failed receipts, full generated C, persisted media, nine oracle directories,
final sources, frozen kernel/input receipts, independent review and SHA-256
manifests. The V transport copy changes only the private bootloader-cache path
and established QEMU foreground/task-priority wrapper; workload bodies match
the public controller. The independent review found no unresolved correctness
or lifetime defect after final runtime and oracle checks.

This qualifies the scoped host and disposable QEMU scenarios. Unrelated full
native, desktop, nine-boot saved-plan and physical hardware qualification remain
separate; trusted-reference and quiescent-write requirements still apply.
