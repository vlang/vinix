# Automatic ciphertext scrub qualification

`scrub-volume-auto` and `scrub-recovery-volume-auto` authenticate and erase
secrets, validate an exact reference, then retain the existing read-only
identity-discovery pin for a complete scrub and private report. Reports,
clean/changed/operational statuses and publication semantics match explicit
device scrubs. See [the contract](../../docs/storage-volumes.md#identity-based-automatic-ciphertext-scrubbing).

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-auto-scrub --work /tmp/auto-scrub-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --auto-scrub --work /tmp/auto-scrub-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --auto-scrub --work /tmp/auto-scrub-x86
```

The scoped host runs existing authenticated and public report codecs, syntax,
and the complete RecoveryIO/discovery models under ASan/UBSan. The new scrub
integration model injects only the discovery boundary and fixed KDF: real
authentication, private input reading, streaming SHA, pinned rechecks, report
encoding, publication and erasure run unchanged. Sixteen VC1/VR1, MBR/GPT,
512/4096-sector and saved-mode profiles require erased secrets before discovery,
zero discovery after credential/reference failures, exactly one retained pin,
complete 73728-byte scans across both chunks, identical report output, operational
error precedence, balanced descriptors and wiped workspaces. Discovery-selected
physical ID/mode changes fail the first recheck. The separate unchanged discovery
model executes the actual bounded enumeration, alias/clone ambiguity, candidate
identity/probe, enumeration/type/read faults and descriptor ownership paths.
This distinction keeps the integration and actual discovery coverage explicit.

The selected guest executes the unchanged explicit scrub workload first to
create eight genuine historical findings. It then uses the actual automatic
CLI and full-profile KDF for both domains/modes, requires byte-identical
manual/automatic clean and controlled-corruption reports, refuses existing
outputs, restores physical ciphertext and preserves a held mapping's complete
status and plaintext reads. Four warmup and four measured cycles each execute
automatic VC1 scrub, automatic VR1 scrub and offline viewing, reclaim reports,
and wait thirteen seconds before comparing all warmed heap classes and retained
large pages. These are 24 new utility lifetimes and eight new full-cost KDFs per
architecture, in addition to the preceding explicit scrub cycles. A second boot
reorders physical devices; all four automatic combinations find the same disk,
followed by a separate explicit recovery unlock.

The automatic artifact oracle independently constructs exact reference/report
bytes and uses V standard-library SHA and OpenSSL for complete clean/changed
ciphertext digests and reference fingerprints. It checks eight manual and eight
automatic reports on each persisted guest. Existing scrub/ciphertext/VC1/VR1
oracles remain unchanged. Complete utility and actual selected guest C receive
allocation audits and independent lifetime review. Frozen isolated ALLOC_TRACK
kernels stay unchanged; no kernel implementation changes are part of this work.

## Qualification on 2026-10-13

`host-1`, `arm-1` and `x86-1` receipts are zero. The scoped host passed ASan/UBSan
without sanitizer or undefined-behavior errors; all four guest boots passed.
Production and guest sources stayed unchanged during successful qualification.

| Guest | New warmup + measured cycles | New utility lifetimes | Slab classes with zero delta | Large pages before → after |
| --- | --- | --- | --- | --- |
| ARM64 | 4 + 4 | 24 | 18 | 72 → 72 |
| x86_64 | 4 + 4 | 24 | 14 | 193 → 193 |

The automatic cycles include eight real 32-MiB passphrase KDF allocations,
eight recovery scrubs and eight offline views per architecture. The preceding
explicit-device cycles also pass: another 24 lifetimes/eight KDFs each. Separate
clean/changed, report-preservation and held-descriptor scenarios precede these
measurements. Both reordered second boots run all four automatic domain/mode
combinations without receiving a physical device name, then explicitly unlock
the preserved data. Alias/clone ambiguity and candidate/enumeration fault
coverage comes from the actual discovery host model; the new scrub integration
model independently checks authentication/reference ordering and pin continuity.

Twelve selected independent artifact oracle invocations pass. The new automatic
oracle checks exact bytes of all sixteen manual/automatic reports and both
references on each guest, with independent CRC, V/OpenSSL ciphertext digests and
reference fingerprints. All seven preceding artifact modes also pass, including
scrub, ciphertext references, VC1, VR1, growth, credential rotation and sealed
recovery. Their three oracle sources remain unchanged.

Initial artifact extraction attempts hit ENOSPC when the shared host disk filled.
Partial owned outputs and an explanation remain retained. Completed owned
`boot.img` and `test.iso` transport images were compressed losslessly to `.gz`,
with original SHA-256/length receipts and verified decompression before removing
the originals. Physical guest disks, generated C and implementation sources
remain unchanged. Identical oracle binaries and inputs then passed in fresh
directories; no guest or host rerun was needed.

Independent source/generated-C and lifetime review checks both complete utility
targets, the two parent helpers, retained discovery ID/mode, secret erasure and
reference validation before discovery, unchanged scan/publication/output order,
all ten workspace wipe/edit-close exits and five pinned-parent close exits.
All 285 other production bodies/constants remain identical. The shared scrub
body matches its predecessor after only the two documented helper substitutions;
manual helper branches reproduce its original opener/initial probe. The nine
RecoveryIO and four discovery test bodies match their public sources after
explicit fixture transformations. Forty-four RecoveryIO and eight actual
discovery model C bodies match their normalized production counterparts.
Complete utility and selected guest programs pass allocation audits. The review
found no unresolved correctness or lifetime issue.

The shared failure path retains an extra `perror` after a logical discovery
refusal; discovery prints the precise refusal first, and the extra system-error
text can be uninformative. This affects diagnostics only, with status 1 and no
successful finding or publication.

Retained evidence is under `logs/storage-auto-scrub-work`: receipts, full
generated C, physical media, compressed boot images/original hashes, successful
and earlier partial oracle outputs, final sources, frozen kernel/input receipts,
independent review and SHA-256 manifests. The V transport copy changes only its
private bootloader-cache path and established QEMU foreground/task-priority
wrapper; workload bodies match the public controller. Its owned temporary RAM
compiler volume is released before archiving evidence.

This is a scoped host and disposable QEMU matrix; full native, desktop,
saved-plan and physical hardware qualification remains separate. Trusted
references and quiescent writes remain required; scans provide no snapshot,
plaintext or malicious-reference authentication, or repair guarantee.
