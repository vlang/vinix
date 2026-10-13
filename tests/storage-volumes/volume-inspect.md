# Authenticated encrypted-volume inspection qualification

`show-volume` and `discover-volume` authenticate existing VC1 configurations
through the production bounded passphrase/KDF loader. They erase passphrase,
wrapping key and decoded volume key before reporting or discovering the disk.
Offline reports need no disk. Discovery pins candidates read-only, rejects
ambiguous physical clones and rechecks the selected disk twice before reporting;
it imports no mapping. See [the command contract](../../docs/storage-volumes.md#authenticated-encrypted-volume-inspection-and-discovery).

Run the scoped qualification with V and private disposable work directories:

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-volume-inspect --work /tmp/volume-inspect-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --volume-inspect --work /tmp/volume-inspect-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --volume-inspect --work /tmp/volume-inspect-x86
```

The host runs the independent VC1 codec and command syntax under ASan/UBSan,
then the extended actual private-reader/discovery/report model alongside all
previous discovery, boot-set, recovery-unlock and recovery-inspection cases.
It captures exact MBR/GPT, 512/4096-byte and RW/RO reports, including full-width
unsigned metadata. Password boundaries 1/1024, empty/oversized refusal and exact
embedded NUL/newline bytes are checked. Explicit derivation mocks inject wrong
wrapping credentials and failed KDF while real parsing, authentication, private
input reads, disk identification, reporting and erasure execute unchanged.
Input policy/length/read/EOF mutations, enumeration/type/status/read failures,
both retained-probe mutations, physical aliases/clones, read-only parents and
formatter/flush/stream-error faults must preserve inputs and balance descriptors.
Observers check erased passwords/keys before every device access/report and
forbid writable opens and imports.

The guests execute the real staged CLI, with its unchanged full-cost scrypt
profile, on disposable ext2/VirtIO or AHCI media. Raw keyfiles are removed before
queries. Wrong credentials and damaged tags produce no successful metadata;
exact saved RW/RO reports create no mapper node. Queries against an occupied
mapping preserve its entire status/generation/counters, held descriptor and raw
ciphertext. Four warmup and four measured paired offline/online lifetimes run
with actual KDF allocation/erasure/release, warmed snapshot reads and the
existing 13-second reclamation wait. Every slab class and large-page count must
remain equal. Reordered reboot checks the current device names, report metadata
and successful ciphertext unlock through both saved modes.

The independent artifact oracle's `--volume-inspect` mode extracts the persisted
configurations and exact binary password, checks complete canonical VC1 headers,
derives wrapping keys using OpenSSL scrypt, checks complete HMAC/ChaCha20 and the
expected volume key, and compares physical ciphertext against independent
AES-XTS. Earlier oracle modes remain separate regression checks.

Both complete target and guest C modules are audited for allocation/runtime
dependencies. Existing isolated ALLOC_TRACK kernels and input receipts are
retained unchanged; this feature changes no kernel source. The unrelated full
native suite, general nine-boot plan workload, desktop and physical hardware
qualification are separate.

Qualification on 2026-10-13:

| Run | Result | Full-cost paired lifetimes | Retained heap |
| --- | --- | --- | --- |
| Scoped host `host-1` | Independent VC1 codec, actual extended model and syntax pass ASan/UBSan; both target audits pass | KDF mocked only in the host syscall model | Balanced descriptors, erased workspaces, zero imports/writable device opens |
| ARM64 `arm-1` | Both boots and exact saved RW/RO reports pass | 4 warmup + 4 measured, real scrypt | All 18 slab classes: delta 0; large pages 72 → 72 |
| x86_64 `x86-1` | Both boots and reordered device-name reports pass | 4 warmup + 4 measured, real scrypt | All 14 slab classes: delta 0; large pages 191 → 191 |

Each paired lifetime invokes both queries, for 16 actual scrypt query executions
per architecture across warmup and measurement. The unchanged 32 MiB KDF vector
is erased and released for each query. Both new persisted-media oracles pass
exact canonical metadata/modes and binary passwords, independent OpenSSL scrypt,
complete HMAC/ChaCha20, exact volume keys and unchanged AES-XTS ciphertext. Both
physical data units have SHA-256
`58d4a23c8dc7380e7069da904b7be35a5a844a9d6d1c744d531c960258cbbd22`.
All four earlier oracle modes also pass retained prior media.

Independent lifetime review finds no unresolved issue. It verifies five complete
caller-workspace cleanup returns, both retained-parent cleanup returns, the
unchanged bounded KDF allocation/volatile erase/release/output ordering, exact
public fixture source and normalized modeled C, actual selected tests/guest
entries, both complete C allocation audits, all run receipts and both boot
phases. The 265 preceding production function bodies are unchanged apart from
dispatch/usage additions. Host normalization preserves the established explicit
mock/observer changes, guarded arithmetic and two host-only `stat` promotions;
the target locals remain on the stack.

The scoped host and both architecture runs passed on their first attempts.
Review corrected an extra argument accidentally introduced into the older
recovery-inspection guest selector; that inactive branch did not affect these
runs. Both restored old selections independently generate the correct old entry
and pass complete allocation audits. The private controller was refreshed and
rebuilt after that correction; its active tested workload bodies are unchanged.
Its only final transport differences are the established owned bootloader
paths and host QEMU scheduling adjustment. No kernel or production crypto/KDF
code was changed.

Final sources, generated C, build/boot logs, media, all six oracle outputs,
review receipts and SHA-256 manifests remain under
`logs/storage-volume-inspect-work`, including a final source/transport archive
in its `evidence` directory. This qualifies ordinary configuration queries;
the storage umbrella, full-disk boot encryption, live unlock admission and
physical hardware qualification remain separate.
