# Obsolete generation retirement

Collection previously admitted obsolete roots writable by other accounts and
passed their paths to recursive removal. The baseline records acceptance and
removal of generations, interrupted stages and cache. Collection now validates
every eligible root and lease before any removal, requiring an ordinary root
owned by the administrator on the captured generation filesystem with no write
access for other accounts. It captures the parent device/inode too: a generation
and lease moved unchanged into a replacement parent refuse removal.

Under the writer lock and an exclusive generation lease, removal inventories
directories before mutation, reopens components relative to captured descriptors
without following aliases and checks directory identities. Leaf names are
enumerated before unlinking, avoiding directory-cursor skips. Symlinks, hard
links and FIFOs are unlinked without opening targets or changing outside modes.
The lease stays named until all other entries are removed; failures before its
final unlink remain retryable after restoring trusted entries. If the final
empty-directory removal fails, inspect storage and restore an empty regular
lease under the writer lock before retrying. No obsolete manifest is required.
Active and rollback generations and busy leases remain outside removal.

Assertions cover all-root preflight preservation, a replacement parent with
unchanged generation/lease inodes, ten nested/ancestor replacements and ten
root/lease replacements after inventory. Restoration permits retry, and failed
child retirement preserves its named lease. Descriptor stress retires a batch
of 128 obsolete generations, a 64-level tree, 1024 long-name files and 128
successful/refused iterations under a 32-descriptor limit. The optional heap
probe measures removal-helper scratch on 128 successful and 128 refused calls.

The target controller runs these assertions and the signed repository lifecycle
on AArch64 and x86_64 with retained committed kernels. Receipts bind kernel,
init, both programs and serial output. Stable administrative inputs, controlled
ancestors and mount topology remain required; arbitrary concurrent administrator
moves/mount changes and power loss during collection are not qualified. I/O
failures can leave partial cleanup, including the narrow final lease-unlink /
empty-directory-removal interval. This does not claim zero whole-collection heap
retention or qualify large-tree throughput. Broader release gates remain open.

## Recorded results, 2026-10-15

Baseline `02ff97233` accepted a root writable by other accounts and removed
obsolete generations, interrupted stages and cache. Final assertions refuse
before removal and succeed after restoring administrator-only write access.
Replacing the generation parent refuses even when generation/lease inodes are
unchanged. Ten nested/ancestor and ten post-inventory root/lease replacements
preserve captured/replacement/outside data; restored entries permit retry.

All 33 host compile/run checks passed: eleven core runners, the removal-helper
heap probe, collection retirement and stage recovery under clang ASan/UBSan,
and signed real CLI lifecycle/maintenance. Leak detection was disabled and
undefined behavior was fatal. The heap probe measured zero retained removal-helper
allocations across 128 successful removals and 128 refusals. This does not qualify
whole-collection heap retention. Generated C was reviewed for stack stat records,
owned paths/inventories, borrowed directory names and cleanup on error paths.

Fresh QEMU TCG runs passed on AArch64 (72.7 seconds) and x86_64 (84.9 seconds),
including all retirement markers, signed lifecycle and guest shutdown within
600 seconds. Both retired 128 obsolete generations, a 64-level tree and 1024
long-name files, then completed 128 successful/refused iterations under a
32-descriptor limit while protecting a live lease. Five-artifact receipts bind
each committed kernel, init, both programs and serial output. Compiler, sources,
generated C and logs are pinned. Broader publisher/catalog rollout, graphical,
device and runtime gates remain open.

Evidence:

- [before regression](results/2026-10-15/collection-retirement-baseline.txt)
- [host results](results/2026-10-15/collection-retirement-host.json)
- [host summary](results/2026-10-15/collection-retirement-host.txt)
- [recovery assertions and lifecycle](results/2026-10-15/collection-retirement-core.txt)
- [sanitizers](results/2026-10-15/collection-retirement-asan.txt)
- [signed CLI](results/2026-10-15/collection-retirement-cli.txt)
- [source/artifact ledger](results/2026-10-15/collection-retirement-toolchain.json)
- [aarch64 receipt](results/2026-10-15/collection-retirement-aarch64.json)
- [aarch64 report](results/2026-10-15/collection-retirement-aarch64.txt)
- [aarch64 serial](results/2026-10-15/collection-retirement-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/collection-retirement-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/collection-retirement-x86_64.json)
- [x86_64 report](results/2026-10-15/collection-retirement-x86_64.txt)
- [x86_64 serial](results/2026-10-15/collection-retirement-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/collection-retirement-x86_64.qmp.txt)
