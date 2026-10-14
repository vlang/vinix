# Safe unpublished-generation recovery

The previous transaction recovery loop passed each `.stage-*` pathname to
recursive deletion. A root symlink could therefore delete outside files before
returning an error. The baseline records `refused=true preserved=false`.

Transactions and garbage collection now capture and validate every stage root
before removing any stage. Root aliases, special files, foreign ownership or
filesystems and roots writable by other accounts refuse admission. A stage need
not contain a completed state document or lease. The captured generation parent
and stage directory identities bound removal; in-progress transaction failure
cleanup uses the identity captured before creating the generation contents.

Cleanup first inventories ordinary directories without following aliases. It
reopens each component relative to the captured stage, compares directory
identities and removes children before parents. Leaf names are enumerated before
unlinking so directory cursor changes cannot skip files. Relative `unlinkat`
removes leaf aliases, hard links and FIFOs without opening their targets or
changing outside contents/modes. Directory removal checks its captured parent
and named identity. Streams, paths, arrays and captured descriptors are retired
on success and refusal. The number of open descriptors does not grow with depth
or the number of stages.

Invalid roots preserve all other stages, published generations and cache.
Unreadable or changed directories refuse cleanup; an in-progress transaction
prints the retained stage path. Restore trusted entries under the writer lock
or stop package workers before retrying. A later I/O failure or directory change
can leave a partially retired unpublished tree; recovery can resume after the
cause is corrected. Active and rollback generations are outside stage removal.

Assertions cover twelve malformed-root transaction/collection refusals; five
captured-root replacements; ten nested/ancestor replacements; and ten replacements
during prepared/staged transaction cleanup. Restoring the original entries
permits retry. Deep and repeated cases cover a 64-level tree, 128 stages in one
batch, 128 mixed-tree retirements and 128 refusals under a 32-descriptor limit.
A wide directory contains 1024 long-name files spanning directory buffers.
An optional heap probe measures repeated successful cleanup and refusal.

The target controller runs these assertions and the existing signed repository
lifecycle on AArch64 and x86_64 using retained committed kernels. Receipts bind
the kernel, init, both assertion programs and serial output. Stable administrative
inputs, controlled ancestors and mount topology remain required; arbitrary
concurrent administrator moves/mount changes and physical-media power loss are
not qualified. This does not claim zero heap retention for complete transactions
or collection. Inventory and component reopening add work; large-tree throughput
is not qualified. Broader roadmap release gates remain open.

## Recorded results, 2026-10-15

Baseline `1f257f4d4` deleted outside data through an abandoned stage alias before
returning an error. Final assertions refused that root with its outside data
preserved. Twelve transaction/collection cases preserved all other stages,
published generations and cache before restored roots retried successfully.
Five captured-root, ten nested/ancestor and ten in-flight replacements preserved
saved and replacement data; restoring the original entries permitted cleanup.

All 31 host compile/run checks passed: ten core runners, the cleanup heap probe,
stage recovery and complete generation admission under clang ASan/UBSan, and
signed real CLI lifecycle/maintenance. Leak detection was disabled and undefined
behavior was fatal. The heap probe measured zero retained cleanup allocations
across 128 successful mixed-tree removals and 128 refusals. This does not qualify
whole-service heap retention. Generated C was reviewed for stack stat records,
borrowed directory names, owned node/leaf strings and cleanup on error paths.

Fresh QEMU TCG runs passed on AArch64 (56.0 seconds) and x86_64 (65.7 seconds),
with all recovery markers, signed repository lifecycle and guest-initiated shutdown
within the 600-second budget. Both architectures retired a 64-level tree and
128-stage batch, then completed 128 mixed-tree retirements and 128 refusals under
a 32-descriptor limit. A directory containing 1024 long-name files was completely
retired in one pass. Five-artifact receipts bind each committed kernel, init,
both programs and serial output. Compiler, source, generated C and logs are pinned.
Broader publisher/catalog rollout, graphical, device and runtime gates remain open.

Evidence:

- [before regression](results/2026-10-15/stage-recovery-baseline.txt)
- [host results](results/2026-10-15/stage-recovery-host.json)
- [host summary](results/2026-10-15/stage-recovery-host.txt)
- [recovery assertions and lifecycle](results/2026-10-15/stage-recovery-core.txt)
- [sanitizers](results/2026-10-15/stage-recovery-asan.txt)
- [signed CLI](results/2026-10-15/stage-recovery-cli.txt)
- [source/artifact ledger](results/2026-10-15/stage-recovery-toolchain.json)
- [aarch64 receipt](results/2026-10-15/stage-recovery-aarch64.json)
- [aarch64 report](results/2026-10-15/stage-recovery-aarch64.txt)
- [aarch64 serial](results/2026-10-15/stage-recovery-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/stage-recovery-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/stage-recovery-x86_64.json)
- [x86_64 report](results/2026-10-15/stage-recovery-x86_64.txt)
- [x86_64 serial](results/2026-10-15/stage-recovery-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/stage-recovery-x86_64.qmp.txt)
