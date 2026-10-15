# Regular-file backup qualification

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-file-backup --work /tmp/file-backup-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/kernel/bin/vinix \
  --file-backup --work /tmp/file-backup-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/kernel/bin/vinix \
  --file-backup --work /tmp/file-backup-x86
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/file_backup_artifacts.v \
  /tmp/file-backup-arm /tmp/file-backup-arm-artifacts
```

The native suite independently constructs complete archives with standard V
SHA-256. Seven source sizes cover empty, single byte, full/partial chunk
boundaries and multiple chunks. Five versions per size cover unchanged chunks,
changed data, growth, empty truncation and partial truncation. Restores preserve
bytes, mode, UID/GID and the source filesystem's observed mtime precision.
Every byte mutation and every truncation of a small full archive refuses,
including self-consistent invalid header fields. Wrong full bases, delta bases,
missing bases, trailing bytes, special mode bits, symlink/directory inputs,
directory contention and existing/hardlink/symlink/directory destinations refuse.

The actual-IO model copies the production functions with direct syscall
observers. It fails each reached read, write, stat, file/directory sync,
publication, cleanup and permission/time call in all four operations. It also
forces the otherwise unreached ownership-change failure, observes held owners
at output, injects post-read size changes and output failure, and retries
short/interrupted reads and writes. Descriptor acquisitions/releases balance.
Complete publication may precede a late failure, but prior destinations are
never replaced. A reused temporary-name sentinel survives both success and a
late directory-sync failure. Close faults consume the underlying FD first.
The host mode runs these with ASan/UBSan, two preceding native regressions and
both complete target C allocation audits.

Both selected guests use real processes and persistent EXT2 files. They save a
131089-byte file, alter its first byte and metadata, save a one-chunk delta,
restore both versions, reject a valid unrelated base and preserve an existing
destination. Twenty warmup and twenty measured cycles each run all four
operations: 160 new utility lifetimes per architecture. Slab classes and large
allocations are compared after grace waits. After device-reordered reboot,
both persisted restored files and fresh restores are checked again.

The independent persisted oracle reconstructs all seven full/delta/source/
restored files, including exact archive headers and record streams. Standard
V and OpenSSL verify every whole-file SHA. The final utility and selected guest
C receive allocation audits and an independent lifetime review. These are
utility tests with frozen qualification kernels; no new filesystem snapshot,
kernel, desktop, ACL/xattr or power-loss qualification is claimed.

## Recorded result: 2026-10-15

The scoped host mode passed its native suites, actual I/O fault model and
preceding regressions under ASan/UBSan. Both complete utility target C audits
passed; the ARM64 and x86_64 targets were identical before their four ABI
assertions, and both compiled as static musl executables with warnings as errors.

Both architectures passed both boots and their independent seven-file persisted
oracles. The 40-cycle workloads ran 160 utility processes per architecture.
ARM64 retained zero objects in all 18 measured slab classes, with large
allocations unchanged at 77; x86_64 retained zero in all 14 measured classes,
with large allocations unchanged at 209. The independent generated-code and
lifetime review passed, including every cleanup exit and temporary-name reuse.

The host compiler compatibility adapters covered Darwin declarations and
harness command-output capture. The guests ran the generated production
utility with only the established ABI assertions appended. Frozen ALLOC_TRACK
kernels from the preceding qualification were reused. Failed fixture/staging
attempts were retained separately and excluded from these results.
