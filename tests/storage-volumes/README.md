# Storage-volume qualification

Run the unchanged production volume, metrics and security code with mocked
host allocation/I/O boundaries:

```sh
V=/path/to/v python3 tests/storage-volumes/host.py
VINIX_HOST_SANITIZE=1 V=/path/to/v python3 tests/storage-volumes/host.py
V=/path/to/v python3 tests/block-storage/run.py
V=/path/to/v python3 tests/mounted-disk-policy/host.py
```

Build ordinary kernels in isolated worktrees and then run both disposable guest
fixtures. No qualification ioctl or fault-enabled kernel is required:

```sh
VINIX_KERNEL_DIR=/path/to/arm-worktree/kernel V=/path/to/v \
  python3 tests/storage-volumes/run.py --arch aarch64
VINIX_AMD64_KERNEL=/path/to/x86-worktree/kernel/bin/vinix V=/path/to/v \
  python3 tests/storage-volumes/run.py --arch amd64
```

The ARM runner uses the normal boot/package-store SDK environment documented
by `scripts/run-aarch64.sh`; set `VINIX_AARCH64_SYSROOT` for the static compiler.
AMD64 needs `x86_64-linux-musl-gcc`, QEMU and Limine/OVMF. `--state-dir` requires
an empty directory and preserves the generated initramfs and 16 MiB disk.
`VINIX_QEMU_TIMEOUT` defaults to 300 seconds. The runner never selects a host
physical device; it creates and attaches only its disposable disk.

The guest verifies actual physical translation with guard sectors, geometry,
read-only opens, rejection of overlap/shrink/overflow, management privilege,
invalid ioctl/read/write pointers, stable namespace rules, mknod aliases,
growth with open descriptors, active-swap exclusion, stale-descriptor removal,
generation reuse and the native CLI. Concurrent opens race 100 removals. After warming metadata and
graces, it checks that no slab class or large allocation count increases
across 200 more create/write/discard/grow/remove cycles using distinct extents.
AMD64 also checks real partition translation. Host tests cover bounded
discard batches, exec cancellation, securelevel changes, failure cleanup,
unsupported commands, protocol range encoding and DMA quarantine.

NVMe discard currently has host controller qualification only. Production
kernels disable NVMe initialization; an attempted development guest panicked
before the fixture started. Native NVMe qualification remains open.

Controller timeout/short-completion faults run separately in `block-storage`;
physical mounted/swap extent admission runs in `mounted-disk-policy`. These are
not a claim of RAID, full-disk encryption, persistent mapping tables, live
filesystem resizing, filesystem-aware free-space trimming or hardware SMART
qualification.
