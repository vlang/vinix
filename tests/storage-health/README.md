# ATA SMART health qualification

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
The optional `--generated` check rejects heap allocation in every generated
health function (two on ARM, seven on AMD64); it detects compiler promotion of
borrowed reports or interface slots as well as explicit allocation.

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
NVMe/ANS readiness, predictive monitoring or wear/temperature interpretation.
