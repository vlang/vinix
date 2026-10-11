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
ASan/UBSan. Bundle checks include every truncated prefix and single-bit
corruption, checksummed invalid headers/later records, append rollback,
duplicate global slots/disk identities, the 6208-byte version-1/64-disk bound
and output canaries. A publisher fixture replaces only synchronous syscall boundaries;
it tests EINTR and short writes, write/file-fsync/close/rename failures preserving
the old file, and directory-fsync failure retaining the new published file with
unconfirmed durability. A destination matching a temporary candidate must survive
publication and cleanup. Both architectures' complete generated utilities are
audited for implicit heap/runtime dependencies.
Capacity tests cover offline bundle edits, unchanged identity/mode/offset,
idempotent desired lengths and failed publication on shrink, alignment,
overflow, overlap or absent slots. A restore syscall model compiles the
production preflight/application code with only open/close/status/identity-I/O
boundaries replaced. It checks explicit growth opt-in, unlisted extension and
later-slot conflicts before mutation, generation/old-size races, kernel growth
refusal, later create failure, descriptor cleanup and successful resumed replay.
Offline mapping configuration tests cover additions to empty disks, middle/last
removal, preserved identities/order/modes, freed slot reuse across disks, full
64-slot/disk bounds, complete rollback of invalid additions and unchanged files
on corrupt/symlink inputs. Both command paths run publisher fault injection.
See [offline edit qualification](edit-bundle.md) and
[read-only bundle inspection/preflight](check-bundle.md).
Disk membership tests import empty/populated saved plans, retain existing
desired state, reject duplicate keys/slots and invalid inputs, and remove empty
first/middle/last participants with stable order and preserved slot ownership.
They require one remaining disk and cover the full 64-disk/slot format bound,
unchanged source files, symlink/nonregular refusal and both commands' publisher
faults. See [membership qualification](disk-bundle.md).
Extent allocation tests compare aligned gap enumeration against a cell oracle
for every small fragmentation pattern and first-fit placement against brute
force. They cover clipping, unsorted/read-only rows, global slots, all 65 gaps,
sector sizes, near-u64 rounding, atomic rejection, unchanged query bytes and
publisher faults. Guests verify raw data, live conflict rejection and held
descriptors. See [extent allocation qualification](space-bundle.md).

Physical capacity adoption covers MBR/GPT identifiers, 512/4096-byte sectors,
exact expected geometry, unchanged desired rows, identifier ambiguity, full
bundles, overflow bounds, read-only retained probes and atomic publisher faults.
An unchanged-size retry must complete the durability protocol. Guests enlarge
their existing raw disk between boots, adopt the new geometry, allocate and grow
a tail mapping, then restore old and new data on a fourth boot. See
[physical capacity qualification](capacity-bundle.md).

Persistent pool tests compare aggregate capacity and ordered cross-disk first
fit against an independent 2048-case fragmentation oracle. They cover sector
eligibility, membership validation/removal, disk-index compaction, 128-bit
totals, version-1 compatibility, version-2 corruption/import rollback and the
8768-byte/64-region bound. Pool edits and allocations run all publisher faults.
Guests verify later-disk conflict preflight, retained data/descriptors and pool
metadata across reordered boot and capacity adoption. See
[pool qualification](pool-bundle.md).

Plan-set checks cover duplicate disks/slots, 64 plans and all global
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
output into retained logs, limits each boot to 1800 seconds and terminates only
its own process. The allowance includes 5200 utility processes across 200 warmup
and 200 measured thirteen-command cycles, with pool membership/query/allocation,
physical-capacity verification, offline mapping/disk edits and live preflight
on x86 TCG; the strict retention
checks are unchanged.
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
both preserve data and existing generations. A bundle then replaces the individual
enrollment. Failed saves with a missing later disk or repeated physical identity
preserve the previous file; invalid arguments do not replace it. Corruption,
missing disks, untrusted bundle mode/owner, final symlinks, legacy enrollment
conflicts and later occupied/unlisted slots fail without creating a prefix.
Explicit and boot bundle replay preserve data and existing generations.
The capacity fixture then plans larger views without changing live geometry,
rejects invalid edits and default replay, and checks later-disk/extension
conflicts before growth. Writable and read-only views grow in place, keeping
their generations. An already open raw descriptor writes and flushes the new
extent, which remains readable after reboot at the saved larger capacity.
The fixture measures slab/large retention over 200 cycles after 200 warmup
cycles, with both disks enabled. Each cycle saves the bundle, plans unchanged
capacity, verifies/republishes unchanged physical capacity, adds two pool members,
queries the pool and allocates/checks/removes a scratch mapping, enrolls/forgets
an empty offline participant, explicitly replays growth and runs boot restoration.
A flushed phase marker
and the atomically published bundle stay on ext2 across an
abrupt VM stop. The physical disks are reordered for the second boot. Production ARM
native init or AMD64 desktop init restores both disks from the bundle before the
test application starts, and the application checks persisted data, read-only
mode, the correct physical disks after reordering and idempotence. The host does
not inject the bundle or phase marker between boots. The controller requires
the bundle and capacity preflight markers before accepting the first boot.
After the ordinary second-boot assertions pass, the controller extends only
the disposable raw file from 16 to 24 MiB, preserving its MBR and prior bytes.
The third boot must reject the old saved geometry before the application adopts
the exact new capacity, allocates and grows a tail view, and persists its bundle
and phase marker. The fourth boot must restore all six mappings through
production init and retain durable old/tail data and read-only modes. Both pool
regions must survive the reordered second boot and enlarged fourth boot.

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

The block-volume host and guest commands below also use native V controllers.

Run the unchanged production volume, metrics and security code with mocked
host allocation/I/O boundaries:

```sh
V=/path/to/v tests/storage-volumes/host
VINIX_HOST_SANITIZE=1 V=/path/to/v tests/storage-volumes/host
V=/path/to/v python3 tests/block-storage/run.py
V=/path/to/v tests/mounted-disk-policy/host
```

Build ordinary kernels in isolated worktrees and then run both disposable guest
fixtures. No qualification ioctl or fault-enabled kernel is required:

```sh
VINIX_KERNEL_DIR=/path/to/arm-worktree/kernel V=/path/to/v \
  tests/storage-volumes/run --arch aarch64
VINIX_AMD64_KERNEL=/path/to/x86-worktree/kernel/bin/vinix V=/path/to/v \
  tests/storage-volumes/run --arch amd64
```

The ARM runner uses the existing musl SDK; set `VINIX_AARCH64_SYSROOT` for the
static compiler. Both architectures snapshot the requested kernel and directly
own QEMU with private ISO, firmware variables and serial log.
AMD64 needs `x86_64-linux-musl-gcc`, QEMU and Limine/OVMF. `--state-dir` requires
a fresh directory and preserves the generated initramfs and 16 MiB disk.
`VINIX_QEMU_TIMEOUT` defaults to 300 seconds. The runner never selects a host
physical device; it creates and attaches only its disposable disk.
`--kernel-dir` selects either architecture's kernel directory; `--build-only`
produces the fixture, utility, archive and disk without booting. The native
supervisor kills QEMU with SIGKILL before checking sentinels, preserving the
power-cut contract. The host command retains artifacts in a fresh directory
selected by `VINIX_VOLUME_HOST_DIR`. Its original volume assertions remain
unchanged, and the production health dispatcher now receives an independent
host device and access/output-fault tests.

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
