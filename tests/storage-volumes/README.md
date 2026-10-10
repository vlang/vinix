# Storage-volume qualification

Saved volume plans have a native V controller with no Python dependency:

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host --work /tmp/volume-plan-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --work /tmp/volume-plan-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --work /tmp/volume-plan-x86
```

Each work directory must be new. Host checks cover format bounds, every
truncated prefix and single-bit corruption, checksummed invalid records,
512/4096-byte identity parsing, GPT header CRC, changed identity/geometry and
atomic file publication with ASan/UBSan. Generated utility and guest C are
checked for unexpected heap or V runtime dependencies.

Guest runs need target musl compilers, QEMU, `mke2fs`, and the cached Limine
and firmware files from the image builders. ARM also needs mtools; AMD64 needs
`xorriso`. `VINIX_OVMF_CODE` and `VINIX_OVMF_CODE_AMD64` override firmware paths.
The controller boots QEMU directly with disposable disk files, drains serial
output, limits each boot to 360 seconds and terminates only its own process.
It preserves logs and a copy of the saved plan in the work directory.

The fixture boots from an ext2 system disk. A separate raw disk holds managed
views, and a third disk with different MBR identity tests wrong-target rejection.
The first boot saves writable/read-only mappings, rejects corrupt plans and
conflicting slots before creation, checks idempotence and restoration with an
already matching slot, and measures slab/large retention over 200 save/restore
cycles after 200 warmup cycles. A flushed phase marker and plan stay on ext2
across an abrupt VM stop. The second boot begins with no mappings and restores
the actual disk-resident plan, persisted view data and read-only mode. The host
does not inject the plan or phase marker between boots.

The fixture touches its readable ELF load pages before sampling. This keeps
cold faults in the long-lived test program's diagnostic code from appearing as
workload retention. Allocation tracking is started when available, and a
failed retention check dumps the remaining sites for diagnosis.

The older block-volume and controller qualification commands below remain
listed as historical tooling; the saved-plan checks above use V throughout.

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
not a claim of RAID, full-disk encryption, automatic mapping discovery, live
filesystem resizing, filesystem-aware free-space trimming or hardware SMART
qualification.
