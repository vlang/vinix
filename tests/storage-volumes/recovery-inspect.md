# Authenticated recovery inspection qualification

The production `show-recovery-volume` and `discover-recovery-volume` commands
authenticate the existing private VR1 backup and report saved metadata. Offline
inspection requires no disk. Online discovery pins candidates read-only,
establishes physical uniqueness and rechecks the retained descriptor twice.
Neither command imports or reserves a mapping. Credentials and the decoded
volume key erase before discovery/reporting, and the entire workspace erases on
every exit. See [the command contract](../../docs/storage-volumes.md#authenticated-recovery-inspection-and-discovery).

Run the scoped host and disposable guest qualification with V:

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-recovery-inspect --work /tmp/recovery-inspect-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --recovery-inspect --work /tmp/recovery-inspect-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --recovery-inspect --work /tmp/recovery-inspect-x86
```

The host runs the independent recovery codec tests, the actual private reader,
authenticated report/discovery syscall model and CLI syntax under ASan/UBSan.
The existing passphrase discovery, boot sets and direct recovery unlock model
tests run alongside the new tests. Mocked boundaries are explicit in
`plan_run.v`; production parsing, authentication, identity checks, report
formatting, flushing and erasure execute unchanged. The new model captures real
stdout for exact MBR/GPT, 512/4096-byte and RW/RO reports, including full-width
unsigned metadata. It injects private-file ownership/mode/length/read/EOF
changes, failed authentication, discovery enumeration/type/status/read faults,
capacity/runtime-identity/mode changes at both final probes, physical aliases,
matching clones and report/flush/stream-error failures. Observer hooks assert
zero secrets before `/dev`, every probe and reports, no writable device open or
import, a live selected descriptor through reporting and balanced cleanup.

Both guests invoke the real staged CLI on disposable ext2/VirtIO or AHCI media.
They delete original credentials/configurations, reject damaged backups and
wrong recovery inputs, capture exact RW/RO reports, prove the mapper stays
absent, query an occupied mapper while preserving its status/generation/held
descriptor and raw ciphertext, and measure 200 warmup plus 200 measured paired
offline/online lifetimes. Every slab class and large-page count must remain
equal after the existing reclamation grace period. The second boot reorders
the physical disks, checks their current names and exact metadata, and unlocks
both saved modes to verify persisted ciphertext remains readable. The unchanged
independent artifact oracle can check these media with `--recovery-unlock`.

Both complete generated target modules and guest fixtures are audited for
implicit allocation or V runtime dependencies. Kernel inputs use the existing
isolated ALLOC_TRACK builds; this feature changes no kernel code. Full unrelated
native suites, the general nine-boot saved-plan sequence and physical hardware
qualification are separate.

Qualification on 2026-10-13:

| Run | Result | Repeated paired lifetimes | Retained heap |
| --- | --- | --- | --- |
| Scoped host `host-2` | ASan/UBSan codec, extended reader/discovery/report model and syntax pass; both target audits pass | All input/report/discovery fault profiles | Balanced descriptors, complete workspace erasure and zero imports |
| ARM64 `arm-4` | Both boots pass, exact RW/RO reports and reordered names | 200 warmup + 200 measured | All 18 slab classes: delta 0; large pages 72 → 72 |
| x86_64 `x86-4` | Both boots pass, exact RW/RO reports and reordered names | 200 warmup + 200 measured | All 14 slab classes: delta 0; large pages 191 → 191 |

Each paired lifetime executes both commands, so each architecture runs 800
queries across warmup and measurement. Both independent persisted-media oracles
verify complete canonical RW/RO headers, the exact recovered key, HMAC/ChaCha20
and unchanged AES-XTS ciphertext. The native data unit SHA-256 on both disks is
`58d4a23c8dc7380e7069da904b7be35a5a844a9d6d1c744d531c960258cbbd22`.

Independent lifetime review found no unresolved issue. It checks all six
workspace-cleanup returns, both post-discovery descriptor-cleanup returns,
exact fixture transformations and normalized modeled C, complete target/guest
allocation audits, actual guest selection and all run receipts. The 263 prior
production function bodies are unchanged apart from dispatch/usage additions.
Model normalization includes two host-only `stat` locals promoted by V when
passed to mock functions; the corresponding target locals remain on the stack.

Initial attempts exposed test-harness declaration, diagnostic-output assertion
and fixed-array annotation issues, corrected before final runtime qualification.
Guest attempt 3 stopped during staging when the shared host disk filled. The
identical final sources passed attempt 4 with compiler temporary files on a
dedicated anonymous RAM volume; no earlier evidence or other session's files
were removed. The private controller retains only the established owned
bootloader paths and host QEMU scheduling adjustments. Test workload, utility
and frozen kernel inputs use the public sources.

Sources, generated C, build/boot logs, media, oracle outputs, failed-attempt
diagnostics, review receipts and SHA-256 manifests remain under
`logs/storage-recovery-inspect-work`, with a final source/transport archive in
its `evidence` directory. This qualification applies to these recovery queries;
the storage umbrella, live unlock admission, full-disk boot encryption and
physical hardware qualification remain separate.
