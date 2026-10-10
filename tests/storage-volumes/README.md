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
atomic file publication and discovery's regular-file/symlink rejection with
ASan/UBSan. Plan-set checks cover duplicate disks/slots, 64 plans and all global
slots, directory ordering, ignored names, selected nonregular files, descriptor
ownership and the 4096-entry limit. The same controller runs both native init
policy variants, including
missing utility, synchronous reaping, fork/exec failure and failed restore.
Generated utility, init and guest C are checked for unexpected heap or V
runtime dependencies.

Guest runs need target musl compilers, Clang/LLD, QEMU, `mke2fs`/`debugfs`, and
the cached Limine and firmware files from the image builders. ARM also needs
mtools; AMD64 needs `xorriso`. `VINIX_OVMF_CODE` and `VINIX_OVMF_CODE_AMD64`
override firmware paths.
AMD64 uses the cached Alpine BusyBox and musl loader from
`build-amd64-userland/staging`; `VINIX_AMD64_USERLAND_ROOT` overrides that root.
On AMD64 a V console adapter redirects init's output to serial and execs the
unchanged packaged desktop init as PID 1.
The controller boots QEMU directly with disposable disk files, drains serial
output into retained logs, limits each boot to 600 seconds and terminates only
its own process. The longer allowance includes 800 utility processes and disk
discovery on x86 TCG; the strict retention checks are unchanged.
Serial output is streamed to disk, with a fixed marker window for read boundaries;
pipe buffers are freed after writing, and the completed transcript is read once.
This bounds capture memory during verbose development-kernel NVMe qualification.
It preserves logs and a copy of the saved plan in the work directory.

On AMD64, `--nvme` adds two disposable NVMe disks, one with an injected critical
warning. Use a `PROD=false` kernel because the driver retains development-only
probing. The fixture checks actual controller-wide health, CLI exit 0/3, bad
output pointers, descriptor/partition policy, unchanged I/O counters, 200 successful
and 200 bad-pointer queries per disk inside the retention measurement, and health
after reboot.
Bounded monitor sessions on both controllers exercise standard thermal/wear
fields and full-width counter deltas, retaining exit 0/3; their separate result
marker is required on the first boot.
See [health qualification](../storage-health/README.md).

The fixture boots from an ext2 system disk. A separate raw disk holds managed
views, and a third disk with different MBR identity first tests wrong-target
rejection, then holds an independently configured mapping.
The first boot runs production init with a deliberately invalid plan, verifies
the failure is reported and the application still starts, then saves
writable/read-only mappings. It rejects corrupt plans, writable boot
configuration, duplicated physical identities and conflicting slots before
creation. It accepts physical aliases, skips symlinks/partitions, checks
idempotence and restoration with an already matching slot. A multi-disk set then
rejects corrupt later plans, duplicate disk keys/global slots, missing disks,
untrusted directories/files and selected symlinks without creating a prefix.
Conflicting requested slots and unlisted overlapping views on the later disk
leave earlier disks untouched. Directory-only and legacy-plus-directory restore
both preserve data and existing generations. The fixture measures slab/large
retention over 200 save/boot-restore cycles after 200 warmup cycles, with both
disks enabled. A flushed phase marker and enrolled plans stay on ext2 across an
abrupt VM stop. The physical disks are reordered for the second boot. Production ARM
native init or AMD64 desktop init restores both disk-resident plans before the
test application starts, and the application checks persisted data, read-only
mode, the correct physical disks after reordering and idempotence. The host does
not inject the plans or phase marker between boots.

The fixture touches its readable ELF load pages before sampling. This keeps
cold faults in the long-lived test program's diagnostic code from appearing as
workload retention. Allocation tracking is started when available, and a
failed retention check dumps the remaining sites for diagnosis.
Large-allocation page totals are printed before the slab deltas on every run.

The same first-boot fixture now qualifies the read-only health ABI: actual
QEMU AHCI SMART identity, data/checksum and threshold status on AMD64;
unsupported VirtIO on ARM; invalid pointers and descriptor/resource rejection;
the packaged `health` command; and 200 additional health queries within the
retention measurement. See [the health tests](../storage-health/README.md).

It also executes `vinix-volume monitor` with two samples on the physical disk,
checks unavailable health on a logical volume and rejects a regular file.
The first boot must emit the monitor qualification marker. Host fault, reset,
warning/recovery and 200-sample coverage is in
[the native V monitor suite](../storage-monitor/README.md).

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
