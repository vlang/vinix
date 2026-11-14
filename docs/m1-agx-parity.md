# M1 AGX parity with Omarchy

Status: **incomplete**. Reference: the Asahi driver in Omarchy's packaged
Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`. The source chain and
original comparison are in [the initial port report](omarchy-m1-gpu-port.md).
Same firmware protocol is the target; identical Linux/Rust source is not a
meaningful requirement for a V kernel with different memory and scheduler APIs.

## Additional logic implemented

- **Page and range TLBI.** Ported the reference's 16 KiB operand encoding,
  including scale changes and advancing BADDR between full chunks. Mapping
  edits now use range invalidation; global firmware mappings still use full
  invalidation. Both sides retain the full-system barriers.
- **Workqueue retirement.** Firmware `gpu_doneptr` and host `cpu_freeptr`
  have separate owners. Completed commands now publish their last occupied
  slot to `cpu_freeptr`. Logical command ordinals prevent reverse reaping
  from rolling it backwards when the modulo ring pointer wraps.
- **TVB growth.** GrowTVBAck carries the current firmware halt counter at
  offset `0x18`, rather than leaving those eight bytes zero.
- **Fault and timeout recovery.** Both firmware ABIs decode their pending
  stamp records, classify culprit/killed work, preserve completed jobs, wait
  for the halt handshake, and acknowledge resume. Cross-VM faults are reported
  as killed work. Resources remain owned until firmware completion stamps
  advance; notification alone never permits freeing a command.
- **Channel recovery.** A recoverable channel error locates its queue,
  records its error and sends RecoverChannel, waiting for consumption.
- **Error reporting.** Job results preserve fault diagnostics and timeout,
  killed and channel-error status. Fences distinguish timeout, cancellation,
  no-device and unknown errors. Shutdown retains stop-before-free ordering.
- **Generated offsets.** Pending-submission and pending-stamp offsets now
  come from the existing V layout generator at both firmware ABIs.
- **Event slot reuse.** Driver stamps start at `slot << 24`, as in the
  reference. Releasing and reacquiring a slot preserves both firmware counters;
  the next command advances from the last observed driver value. An explicit
  armed state distinguishes a newly owned slot from a command whose counter
  wrapped to zero.

Corrupt ring indices, failed recovery acknowledgments and unexplained halts
remain fatal. The worker drains a queued fault notification before treating
its halt as unexplained. No new kernel allocations or object lifetimes were
introduced by this change.

## Remaining differences

These are implementation gaps, not items certified by a passing source gate.

| Area | Vinix versus the packaged reference |
| --- | --- |
| Userspace ABI | Vinix exposes the Mesa 25.0.5 unstable ABI. The reference uses extensible ioctl structures, a flat command buffer, synthetic attachment commands and different ioctl numbering. They are incompatible. |
| Submission scheduling | Vinix accepts at most two commands in the compute-then-render form and waits on dependencies in the ioctl. The reference accepts general batches through DRM scheduling, with multiple in-flight jobs and per-subqueue barriers. |
| Render scenes | Vinix retains one active render scene per queue. The reference manages scene slots and shared TVB lifetime across overlapping work. |
| VM binding | Vinix uses individual contiguous bindings with strict overlap rejection. The reference has batched, extensible VM operations, mapping replacement/splitting, scatter backing and integration with DRM GPUVM/reservation fences. |
| GEM and memory accounting | Purgeable VM-private objects, eviction/madvise, device/client limits and the reference's full reservation-fence behavior are not implemented equivalently. |
| Timestamp UAPI | The reference's per-command timestamp objects and current compact command fields are not wired through Vinix's legacy command interface. |
| M1 family | The native path configures base M1/t8103. The reference also supports t6000/t6001/t6002 M1 Pro/Max/Ultra, including clustering and multiple dies. |
| Telemetry | Vinix drains auxiliary channels but does not expose the reference's full firmware statistics/debug interface. |
| Complete wire comparison | Existing tests cover selected InitData and work-command contracts. Every remaining field/default still needs independent comparison; a matching structure size is insufficient. |
| Userspace integration | Vinix's bundled Mesa is 25.0.5. Omarchy packages a newer matched Mesa/DRM stack. Driver ABI modernization and userspace migration must be verified together. |
| Hardware acceptance | No native Vinix boot, recovery, compute/render result, concurrent lifecycle or performance result was obtained for this change. |

This inventory does not certify unchecked behavior as equivalent. Closing the
ABI and scheduler rows is a substantial remaining port, not a rename or a
package-selection change.

## Validation and continuation

The host fixtures execute production page-table, publication, retirement and
recovery code with privileged services replaced. They cover both ABIs,
pending-array boundaries, fault isolation, timeout fallback, channel ACKs,
ring wrap, malformed indices and retained ownership. The source gate checks
the corresponding contracts against the pinned Asahi source. These are host
protocol checks, not GPU execution evidence.

Evidence for this continuation belongs in the fresh directory
`/Users/alex/.local/state/vinix/omarchy-m1-parity-20261114/`. The kernel source
snapshot starts at `e40d17a12a630e6e87d29f040322d1fee670e77d` plus this change.
Both kernels built successfully. The two sanitizer suites, firmware ABI and
work-command layout tests, OPP test, layout/reference unit tests and the expanded
Asahi source gate passed. Linked ARM disassembly contains page/range TLBI,
retirement and recovery paths.

The retained `parity-evidence.json` has SHA-256
`a8b532e32bee3406b065014ccd034f71b18765b67bea6eb5c5fa24618a6040bf`.
`v run tools/agx-re/check_m1_parity_evidence.v check STATE_DIR` verifies the
complete named receipt, source snapshots and artifacts; it explicitly does
not certify full parity. Kernel SHA-256 values:

- AArch64: `b318309d055de46dac51b3aaf661cd2bb245fd4b84fbe85329bd6fa28bc924e3`.
- x86_64: `aeed640beea5b93a3509de9f2dfbb7b4acbd445427d90f7e385ef5a3010b5c31`.

The configured hardware endpoint `sergey@macbook-air-sergej.local` failed DNS
resolution during the read-only SSH check. A reachable M1 and a way to boot
Vinix are needed to validate the new recovery/retirement foundation before
queue concurrency and ABI migration can be qualified.

### Event counter continuation

The event change was built separately from
`7442c64d0d78f3d1353ef4b8b6ed2d85fe48121d`, with only
`kernel/gpu/agx/event/event.v` changed in its isolated kernel worktree.
`v run tests/agx-event/run.v --sanitize` passed initialization of all 128
slots, 300 slot reuses, stale completion isolation, wrap through zero and
exactly-once fence signaling. The AArch64 kernel built successfully; its
SHA-256 is `c71cdeb14a19dcbc9ddfcc307616dc1c15dcef48ba50d2657c9ed27bc495ae46`.
The x86 kernel excludes the GPU modules and is unchanged by this continuation.

Sources, the reference `event.rs`, the kernel delta, native executable, ELF
and build/test logs are retained at
`/Users/alex/.local/state/vinix/omarchy-m1-event-20261114/bundle/`.
The sibling `inventory.json` pins the complete bundle and has SHA-256
`0e151a6fc637d12e4f7f806b1d82057b4f2f1af7a1ec62114b38e8d29fad2022`.
Verify with `v run tests/ios/evidence-delta-archive.v check-inventory BUNDLE RECEIPT`.
This integrity receipt does not certify native GPU execution or full parity.

## Earlier artifact retention incident

The continuation initially reused the earlier `omarchy-m1-20261114/kernel-build`
directory and replaced its linked AArch64 kernel. The original `evidence.json`
and source snapshots were preserved. Its receipt still has SHA-256
`90ec316389365996535dfbb98a101bff6b56315887d32ecd6602d34a89eae47a`, but the
kernel at that path no longer matches its recorded
`cfebef4ef9d87345e9e9a984d1ea526dd2f5ee5fc181dd282b23c7e831de3e0e`.
The original complete evidence bundle therefore cannot currently pass integrity
verification. This report does not replace that checksum, weaken its check, or
claim restoration of the missing binary. The new builds and receipt use a
separate directory.
