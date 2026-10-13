# Read-only encrypted growth preview qualification

`plan-preview-grow-volume` and `plan-preview-grow-recovery-volume` authenticate
VC1 or VR1 inputs and check explicit proposed capacity/extent against a pinned
read-only whole physical parent. They erase all decoded secrets before probes,
recheck the disk twice, then report original/candidate metadata with independent
`keep`/`grow` actions. They publish/apply nothing. See
[the contract](../../docs/storage-volumes.md#read-only-encrypted-growth-previews).

Run the scoped V host and disposable guest qualification:

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-growth-preview --work /tmp/growth-preview-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --growth-preview --work /tmp/growth-preview-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --growth-preview --work /tmp/growth-preview-x86
```

The scoped host runs both independent authenticated codecs, syntax and the
extended actual private-reader/physical-probe/report model under ASan/UBSan.
The model checks all 16 format/MBR-or-GPT/512-or-4096-byte/RW-or-RO profiles,
three candidate capacities including full-width unsigned bounds, equal/grown
and maximum valid lengths, signed mapping limits, explicit mismatched capacities,
shrinking and invalid alignment/bounds. Existing publication/recovery tests run
alongside the new preview cases. Derivation is explicitly mocked only in this
host syscall model; parsing, authentication, input policy, identity/geometry,
report formatting/finalization and secret erasure execute unchanged.

All 30 existing physical probe modes and both retained-recheck mutation
stages are exercised. Input read/EOF/ownership/mode/fstat failures, lengths,
symlinks, failed/wrong/degenerate KDF results and report/flush/stream-error faults
must balance descriptors, wipe workspaces, preserve inputs and produce no
successful report before full validation. Observers require erased passwords,
wrapping keys and volume keys before every physical access/report; parents remain
read-only and pinned through reporting. No directory/entropy/publication/import
operation is allowed. Saved mode is checked independently of physical mode.

Both guests stage the real CLI on disposable ext2 and VirtIO/AHCI media. They
capture exact reports for both formats and saved modes; reject wrong disk,
unobserved capacity, invalid extent and wrong credential; preserve all four
input envelopes byte-for-byte and retain a live mapping's complete status,
generation/counters/descriptor and raw ciphertext. Four warmup and four measured
pairs use actual full-profile scrypt for VC1 and direct VR1 authentication, with
warmed snapshot reads and the existing 13-second reclamation wait. Every slab
class and large-page count must remain equal.

The host actually expands the retained data backing file from 16 to 32 MiB
between boots and reorders devices. Both formats/modes preview explicit capacity
adoption with unchanged/elevated extent lengths; declaring the old physical
capacity fails. Previews still create no mapper node. A separate explicit
recovery publication and readonly unlock prove persisted data remains readable.
The unchanged independent oracles check original VC1 configurations (OpenSSL
scrypt/HMAC/ChaCha20/key) and VR1 backups plus physical AES-XTS ciphertext.

Complete target and guest C are audited for allocation/runtime dependencies.
Existing isolated ALLOC_TRACK kernels and input receipts remain unchanged; no
kernel source changes are part of this feature. Unrelated full native suites,
the general nine-boot saved-plan sequence, desktop and physical hardware
qualification are separate.

## Qualification on 2026-10-13

The scoped host, ARM64 and x86_64 guest runs passed on their first attempts.
Both guests completed the initial qualification and the second boot with real
16-to-32-MiB expansion and device reordering. Every saved envelope and the held
mapping's status, descriptor, plaintext and physical ciphertext stayed intact.
In capacity adoption reports, `current_disk_bytes` remains the authenticated
saved 16-MiB value; `planned_disk_bytes` is the observed 32-MiB physical capacity.

| Guest | Warmup + measured pairs | Slab classes with zero delta | Large pages before → after |
| --- | --- | --- | --- |
| ARM64 | 4 + 4 | 18 | 72 → 72 |
| x86_64 | 4 + 4 | 14 | 191 → 191 |

Each pair executes one actual full-profile scrypt VC1 preview and one direct
VR1 preview: 16 command lifetimes, eight real KDF allocations and eight recovery
queries per architecture across warmup and measurement. These measured cycles
follow the separate report, refusal and live-descriptor checks.

Both independent authenticated codecs, the combined old/new private-reader and
physical-probe models, and new command syntax passed ASan/UBSan. Complete target
C on both architectures and both guest C files passed allocation/runtime
dependency audits. Seven persisted-artifact oracle runs passed across all five
unchanged oracle modes: VC1 and VR1 from each new guest, plus preceding recovery
growth, credential rewrap and sealed recovery artifacts. The new guests' first
encrypted native unit has SHA-256
`58d4a23c8dc7380e7069da904b7be35a5a844a9d6d1c744d531c960258cbbd22`.

Independent source/generated-C and lifetime review checked all eight workspace
wipe exits, all three pinned-parent close exits, secret erasure before hardware
and output, KDF release ordering, exact model transformations and the selected
guest entry. All 267 preceding production function bodies are unchanged,
excluding the separately reviewed dispatcher and usage additions. The reviewer
found no unresolved correctness or lifetime issue after checking completed
runtime and oracle evidence.

Retained local evidence is under `logs/storage-growth-preview-work`: host and
guest logs, full generated C, persisted media, oracle artifacts, final sources,
frozen kernel/input receipts, independent review and SHA-256 manifests. The V
transport copy changes only the private bootloader-cache path and established
QEMU foreground/task-priority wrapper; qualified workload bodies match the
public controller. This qualifies the scoped host and disposable QEMU scenarios;
the separate suites and physical-hardware limits above still apply.
