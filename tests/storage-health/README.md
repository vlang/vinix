# ATA and NVMe health qualification

The host controller and fixtures are V throughout:

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-health/run.v \
  --work /tmp/storage-health-host --generated /path/to/worktree/kernel/obj/blob.c
```

The work directory must be new. The controller copies the production AHCI
declarations, slot selection, PRDT setup and complete health implementation,
plus the resource dispatcher and descriptor ioctl policy. A deterministic
transport boundary emulates command completion. Tests inspect every command's
opcode, subcommand, register signature, direction, exact 512-byte PRDT and
cleared completion FIS. They cover supported, disabled and invalid capability
words, threshold exceeded/not exceeded, short IDENTIFY/SMART transfers,
checksum corruption, failed ports, missing FIS, invalid register signatures
and busy/error/data-request status bits. Backend errors propagate once and
port failure prevents further submissions. Descriptor tests cover readable
versus write-only/O_PATH access, MAC rejection, unsupported resources and
output faults after driver unlock. The production utility's report validation,
exit statuses, bounded identity sanitization and all six raw bytes are tested.
All host tests use Clang ASan/UBSan.

NVMe tests copy the production command/completion and reset code, complete
health backend, MMIO mapping and I/O-queue initializer. Simulated hardware
supplies DMA and register transitions, rather than replacing submission or
completion functions. Tests check fresh Identify Controller, exactly 128
SMART log dwords, controller-wide NSID and RAE=1, cleared DMA pages, all warning
bits, failed completions/CID reuse, timeouts before/after identity, fatal status,
wrong completion CID/queue, and failed disable quarantine. Two hundred queries
return all pages; two hundred later calls on a quarantined controller neither
allocate nor submit. Allocation failure submits nothing. MMIO tests check high
BAR page addresses, uncached flags, interval bounds and mapping failures; real
queue creation must leave completion interrupts disabled. Utility tests retain
all 128 counter bits and sanitize NVMe identity without ATA's byte swap.

The optional `--generated` check rejects heap allocation in every generated
health/mapping function and NVMe read/flush commands (two on ARM, twelve on AMD64);
it detects compiler promotion of borrowed reports, interface slots and command
temporaries as well as explicit allocation.

Build ordinary kernels in isolated worktrees, then run the existing native V
storage controller against each built kernel:

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --work /tmp/storage-health-x86
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --work /tmp/storage-health-arm
```

These runs create only disposable disk images. AMD64 queries actual QEMU AHCI
SMART responses through the ordinary output-only ioctl and packaged utility,
checks physical identity and checksum, rejects invalid output pointers,
write-only descriptors, regular files, partitions and logical views. ARM
confirms unsupported VirtIO queries return `ENOTTY` while both architectures
retain the volume-plan/reboot suite. After warmup, 200 additional successful
health queries plus 200 bad-pointer queries on AMD64 run inside the existing
slab/large-retention measurement; ARM measures 200 unsupported queries.
Generated V-to-C output is reviewed to ensure stack/interface handling adds
no allocation. Firmware strings and attribute units remain vendor specific.
QEMU and mocked faults do not establish real-drive health accuracy, native
ANS readiness, predictive monitoring or vendor-specific wear interpretation.

NVMe guest qualification uses a development kernel with the existing
`PROD=false` probing policy and an explicit extra fixture:

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --nvme --kernel /path/to/development-kernel/bin/vinix \
  --work /tmp/storage-health-nvme
```

The fixture adds healthy and warning-reporting QEMU PCI NVMe devices, checks
the actual ABI and packaged CLI (exit 0 and 3), unchanged completed I/O counters,
bad output pointers, descriptor and partition rejection. After warmup, 200
successes plus 200 bad-pointer queries per NVMe device join the slab/large
retention measurement. Both devices are queried again after reboot. High BAR
register/doorbell mappings and polled queue initialization are exercised by the
guest, while timeout/reset refusal remains deterministic host qualification.
The initial run measured 800 retained 64-byte objects over 200 plan cycles;
allocation call chains identified V's heap promotion of NVMe read commands.
Read and flush command temporaries now use the caller's stack; submission
copies them into permanent queue memory, preserving payload DMA ownership.
This does not change NVMe production activation or establish physical-controller,
hot-unplug, controller reconstruction or power-loss qualification.
