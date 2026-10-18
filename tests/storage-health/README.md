# ATA, NVMe and Apple ANS health/status qualification

For the ANS transport, namespace enumeration, health and status subset:

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-health/run.v \
  --work /tmp/ans-host --ans-only
```

The namespace model implements only Identify CNS 0/1 and exercises the actual
submission, NVMMU, completion and namespace parser. It checks sparse/inactive
IDs, scan and slot limits, malformed metadata, completed errors, timeouts and
wrong command tags. CNS 2 must be refused before any hardware submission.
All four ANS entries run with Clang ASan/UBSan. This subset avoids dependencies
on the separate AHCI/NVMe fixture bindings.

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

ANS tests copy the complete production transport/media policy up to the
privileged hardware callback boundary, plus the complete health backend and
resource method. The MMIO/DMA model checks both cleared transfer lengths, cache
synchronization, fixed admin tag, NVMMU direction/PRPs, exact Get Log encoding,
controller scope through two namespace indices, full payloads and output guards.
Every bit of every non-tag command byte is mutated and rejected before submission.
Tests cover all warning bits, ordinary completion errors with successful retry,
timeouts with running/stopped clocks, wrong CID/queue/head, failed NVMMU
invalidation, fatal controller status, shutdown, null outputs and invalid indices.
Two hundred successful queries wrap the two-entry admin completion queue;
two hundred calls after each fatal failure neither submit nor clear owned DMA.
ANS partitions reject queries, and the architecture's production dispatcher is
exercised under ASan/UBSan.

ANS status tests also copy the production resource read/write/sync methods and
exported transport calls. The independent I/O completion model verifies rounded
reads, partition boundary read-modify-write, namespace-wide sync, separate
namespace totals, successful prefixes before read/write/flush failures, one error
per failed request, health retry, EOF/validation and offline/read-only policy.
Whole and partition views expose identical physical counters with their own
capacity and offset. Status queries submit no admin command. Counter storage
stays outside the mirrored transport layout, preserving the older ANS fixtures.

The optional `--generated` check rejects heap allocation in generated
health/status/mapping functions, ANS accounting/transport and NVMe read/flush commands;
it detects compiler promotion of borrowed reports, interface slots and command
temporaries as well as explicit allocation.
For AMD64, use a development (`PROD=false`) blob so the compiler retains the
NVMe boot-only mapping functions.

For a kernel allocation measurement, create a separate ARM git worktree and link
its untracked kernel build dependencies as for an ordinary build. The following
V producer installs only the maintained hardware model and a boot self-test into
that worktree; the production transport, health/status methods and dispatchers run against
the real kernel allocator. It rejects the main checkout and modified ANS boot
source unless it matches the current production checkout (for testing an
uncommitted feature). No test hook or model is added to an ordinary kernel.

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-health/ans_fixture.v /path/to/ans-worktree
make -C /path/to/ans-worktree/kernel ARCH=aarch64 CC=clang V=/path/to/v \
  VFLAGS='-nocache -d ans_health_fixture' ALLOC_TRACK=1
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/ans-worktree/kernel/bin/vinix --work /tmp/ans-kernel-model
V=/path/to/v build-support/run-v-tool.sh tests/storage-health/ans_fixture.v \
  --log /tmp/ans-kernel-model/first-boot.log
V=/path/to/v build-support/run-v-tool.sh tests/storage-health/ans_fixture.v \
  --log /tmp/ans-kernel-model/second-boot.log
```

The kernel self-test warms the path, then makes 200 resource-dispatched queries
and compares every slab class and large-allocation page count. It then warms
and repeats 200 read/partial-write/sync/failed-raw-write/status cycles, checking
the exact namespace totals and partition flags while every allocation class
stays flat. Both result markers are required on both boots. Reports include
an unknown warning bit and payload tail bytes. Its synchronous software model
is freed before normal ANS initialization. The guest also runs the existing
storage-plan/health/reboot suite. This tests kernel dispatch and allocation
behavior, without claiming physical Apple hardware or health-log accuracy.

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
