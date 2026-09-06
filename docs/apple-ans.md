# Apple M1 ANS2 internal SSD: experimental read-only bring-up

## Status and scope

This driver implements the base M1 (`apple,t8103`) ANS2 transport and read-only
namespace/GPT block devices. It is not a generic PCI NVMe probe. It discovers
NVMe, ASC, mailbox, SART, reset and power resources from the bootloader's Linux
DeviceTree, starts the preloaded ANS firmware using RTKit, and submits commands
through ANS2 linear queues and the NVMMU.

**The full V/kernel build and a physical M1 SSD test have not been performed.**
Host tests exercise the production C with synthetic firmware/MMIO/DMA, not real
hardware. The production C cross-compiles as freestanding AArch64. The V binding
and hardware cache coherency still need end-to-end validation.

**This revision does not provide a writable SSD root filesystem or switch root
to the SSD.** The existing initramfs remains the root filesystem and recovery
path. There is no APFS/FileVault support, filesystem creation, partition editor,
installer, firmware upload, suspend/resume, hotplug or controller recovery.
Do not describe this revision as a completed internal-SSD boot implementation.

The driver deliberately has no NVM Write, Flush, DSM/TRIM, Format, Sanitize,
namespace-management, security-send or vendor-command interface. It cannot be
made writable using an ioctl or kernel command-line option. MMIO and volatile
firmware/queue configuration writes are still necessary to operate the device;
read-only media commands do not make an untested kernel driver risk-free.

## Build and enable

Use the same compiler, V and linker setup as the already working M1 kernel:

```sh
CC=clang SANITIZE=1 ./tests/apple-ans/run.sh
make -C kernel ARCH=aarch64 CC=clang
```

The makefile already discovers C files under `kernel/c` and ARM64 V modules
under `kernel/modules/apple`; no separate build-system change is required.
Preserve local `V`, `LD_AARCH64` and other necessary toolchain overrides.

Add the following exact, whitespace-delimited token to the kernel command line
of a separate test boot entry:

```text
vinix.apple_ans=1
```

Without that token there is no ANS probe, allocation, power change or register
access. `vinix.apple_ans=0` anywhere on the command line overrides an enable.
Similar substrings such as `foo=vinix.apple_ans=1` and `vinix.apple_ans=10` do not
enable it. `-d no_apple_ans` in the V build flags disables probing at build time.
ANS is independent of the GPU/DCP flags and does not require a GPU experiment.

Keep a backup of important data, a known-working kernel and a boot entry without
the enable token. Continue using the established m1n1/U-Boot/Limine boot chain;
this patch does not modify EFI contents or partition tables. It expects a clean
handoff with the ASC CPU stopped and NVMe disabled. A running ASC is rejected,
not reset behind the bootloader's back. Apple firmware must already have been
loaded by the normal boot chain; this driver does not supply it.

## Devices and first hardware test

Initialization runs after devtmpfs and the console are available. Successful
initialization publishes a line for each device, for example:

```text
ans: /dev/ans0n1: ... bytes, 4096-byte sectors, read-only
ans: /dev/ans0n1p1: ... bytes, 4096-byte sectors, read-only
```

`n1` is namespace ID 1, not an arbitrary ordinal. `p1` is GPT slot 1; unused
slots do not renumber later partitions. The device mode is `0440` rather than
world-readable. Raw namespace access remains available if GPT validation fails;
no partition views are published from an unvalidated table.

From the existing initramfs recovery shell, first inspect the actual names:

```sh
ls -l /dev/ans*
```

For namespace 1, a small non-destructive read into the RAM-backed initramfs is:

```sh
dd if=/dev/ans0n1 of=/tmp/ans-head.bin bs=4096 count=16
cksum /tmp/ans-head.bin
```

Here the SSD is the **input** and `/tmp` is the output. Do not reverse those
arguments or use an SSD device as an output. Repeat the read and compare the
files. For a meaningful hardware check, compare the same immutable byte range
against a read made under a known-working OS, using the same physical namespace
and byte offset. Avoid live filesystem regions that legitimately change between
boots. Neither reproducible reads nor a single checksum proves the whole driver.

Then test larger reads, unaligned byte ranges, end-of-device reads, idle periods
followed by reads, and simultaneous console/touchpad use. Record the complete
boot log, exact kernel revision, DeviceTree and reported namespace geometry.
The test must not format, mount read-write, alter macOS/recovery containers or
change the partition map. Do not rely on filesystem mount behavior until the V
binding, block reads and filesystem error handling have been checked on hardware.

## Implementation details

### Platform discovery and memory ownership

Only an enabled `apple,t8103-nvme-ans2` node under a base-M1 root is accepted.
Reg names must be `nvme`, `ans`; mailbox must implement `apple,asc-mailbox-v4`;
SART must be `apple,t8103-sart` (v2). Power names must be `ans`, `apcie0` and the
reset provider must be the ANS power provider. Translated register ranges,
phandle cell counts, power dependencies, offsets and resource aliasing are
checked before controller access. New IOMMU mappings or nonempty `dma-ranges`
are rejected rather than incorrectly treating an IOVA as a physical address.

A fallible contiguous allocation reserves `0x460000` bytes (4.375 MiB), aligned
to 16 KiB, for queues, TCBs, PRPs, a 64 KiB bounce buffer, bounded GPT scratch and
up to 4 MiB of RTKit shared buffers. DMA addresses are physical and limited to
the supported 42-bit RTKit range. User buffers are never passed to the device.
Width-exact MMIO routines, explicit cache clean/invalidate and full barriers are
used; the host model cannot prove real cache-coherency behavior.

Once controller startup has been attempted, the allocation remains pinned,
even if initialization or an I/O fails. In-flight DMA storage is never returned
to the allocator after a timeout. This intentionally sacrifices memory and
requires reboot for recovery instead of risking a late DMA into unrelated data.

### Firmware and command transport

The bounded RTKit client negotiates versions 11-12, starts the advertised
crashlog/syslog/IOReport/OSLog endpoints, allocates only zero-address buffer
requests and acknowledges supported log/report messages. Existing enabled SART
entries are preserved. Only newly allocated driver-owned shared extents are
added to free SART slots. No DART reset or global DMA bypass is performed.

ANS2 has a shared command-tag space. This first version serializes all work and
uses tag 0 for admin commands and tag 1 for reads. Admin completion depth is 2;
I/O completion depth is 64. **Both linear submission arrays have 64-byte slots,
even though CC.IOSQES is set to 7.** The 128-byte stride of non-linear ANS
submission queues must not be applied to this ANS2 linear mode. NVMMU TCBs are
128 bytes each; their opcode/direction/address fields follow the Linux ANS2
contract. Completion tags, queue IDs, phases, status and TCB invalidation are
checked before a command can be reused.

Identify/controller, Identify/namespace, Identify/active-list, single-I/O-queue
setup and NVM Read are the only admitted commands. Up to eight active namespaces
with 512-byte or 4096-byte logical blocks and no metadata/protection information
are supported. Read sizes respect MDTS and the 64 KiB bounce limit. PRP1,
direct PRP2 and one-page PRP lists are supported. Arbitrary byte-aligned reads
are assembled through the bounce buffer with overflow and extent validation.

All waits have timer deadlines and finite iteration bounds, including a stopped
counter guard. RTKit messages are serviced during initialization and I/O; there
is no dedicated runtime mailbox thread or IRQ handler. Commands are polled.
The V lock masks interrupts during the operation, so a hardware fault can delay
the system until its timeout. This is a conservative bring-up implementation,
not a low-latency, high-throughput block scheduler.

### Partition and userspace interface

The existing generic partition scanner is not used. The ANS decoder checks a
protective MBR, both GPT header CRCs where readable, the partition-array CRC,
reciprocal header LBAs, usable bounds, entry sizes/counts, duplicate unique GUIDs
and overlapping extents. It can fall back to the backup GPT when the primary is
invalid. Two valid but conflicting header descriptions are rejected. At most
128 entries of at most 1024 bytes each are accepted. End LBAs are inclusive.
Every entry is validated before any partition is published.

Namespace and partition views implement read, EOF/short-read behavior and
`BLKSSZGET`, `BLKGETSIZE64`, `BLKGETSIZE`, `BLKROGET`. Geometry refers to the view
being queried. Writes and growth return `EROFS`; unsupported ioctls return
`ENOTTY`. No mmap of the device or raw NVMe command passthrough is exposed.

## Diagnostics

A failure prints an internal error number, initialization stage and last NVMe
completion status. The completion status is the hardware status shifted right
one bit (phase removed), not errno. Zero can mean there was no error completion;
it is not proof that the transport succeeded.

| Error | Meaning |
| --- | --- |
| 1 | Invalid local resources/configuration |
| 2 | Unsupported, unclean bootloader handoff |
| 3 | Timeout or stopped timer |
| 4 | Protocol, completion identity or NVMMU failure |
| 5 | Firmware/controller failure or crash |
| 6 | SART/shared-buffer allocation failure |
| 7 | NVMe command error completion |
| 8 | Unsupported controller capability |
| 9 | Unsupported/malformed namespace |
| 10 | Invalid/missing GPT (normally only suppresses partitions) |
| 11 | Read argument/range error |
| 12 | Command blocked by read-only allowlist |

Stages: 1 handoff/reset; 2 RTKit; 3 firmware boot status; 4 NVMe enable/admin
setup; 5 namespace identification; 6 partition reads; 7 live. Errors after
publication keep the geometry but fail subsequent reads; no silent controller
reset or write-based repair is attempted.

## Validation

`tests/apple-ans/run.sh` includes the actual production C file and substitutes
only MMIO, timer, cache synchronization and device responses. Eighteen test
groups cover startup, SART preservation, RTKit handling, all supported PRP forms,
512/4096-byte sectors, partial reads, CQ wrapping, bounds, command rejection,
timeouts including a frozen timer, wrong completion identities, status errors,
firmware crashes, MDTS, namespace validation and GPT fallback/integrity checks.
There are 10,000 deterministic mutations each of namespace and GPT-header
inputs. These are synthetic fixtures, not captures from a physical M1.

Clang AddressSanitizer/UndefinedBehaviorSanitizer and optimized GCC test runs
pass. Production C passes this freestanding compile with warnings as errors:

```sh
clang --target=aarch64-unknown-none -D__AARCH64__ -ffreestanding \
  -mgeneral-regs-only -std=gnu99 -O2 -Wall -Wextra -Werror \
  -c kernel/c/apple_ans.c -o /tmp/apple_ans_aarch64.o
```

Still required: full V/kernel compilation, DeviceTree integration, real reset/
RTKit handoff, actual DMA/cache coherency, sustained read verification and
failure/reboot behavior. Writable I/O, flush and orderly shutdown, filesystem
integration and explicit root selection must be implemented and validated before
claiming a persistent internal-SSD root filesystem.

## Protocol references and attribution

Original transport/platform code is GPL-2.0-or-later. Protocol/register behavior
was cross-checked against the following upstream files. Git blob IDs pin the
versions inspected; the linked branch paths may change.

- Linux `drivers/nvme/host/apple.c`, Asahi Linux Contributors, GPL-2.0:
  https://github.com/torvalds/linux/blob/master/drivers/nvme/host/apple.c
  Blob `c63e28c7576643fea1503a36cafaf078f59522ae`.
- U-Boot `drivers/nvme/nvme_apple.c`, Mark Kettenis, GPL-2.0+:
  https://github.com/u-boot/u-boot/blob/main/drivers/nvme/nvme_apple.c
  Blob `e674eda83445027f739361e0960f5b898728e663`.
- U-Boot `arch/arm/mach-apple/rtkit.c`, Mark Kettenis and Asahi Linux
  Contributors, GPL-2.0+:
  https://github.com/u-boot/u-boot/blob/main/arch/arm/mach-apple/rtkit.c
  Blob `251c6056cbde98b3adcdd86183378d17dcec3e6e`.
- U-Boot `arch/arm/mach-apple/sart.c`, Asahi Linux Contributors, MIT:
  https://github.com/u-boot/u-boot/blob/main/arch/arm/mach-apple/sart.c
  Blob `e9b017ad570b8d8089859ac43c348f6fcfd77d01`.
- Linux PMGR reset implementation, Asahi Linux Contributors, GPL-2.0-only OR MIT:
  https://github.com/torvalds/linux/blob/master/drivers/pmdomain/apple/pmgr-pwrstate.c
  Blob `82c33cf727a825d2536644d2fe09c0282acd1ef8`.
- Linux ANS DeviceTree binding, GPL-2.0 OR BSD-2-Clause:
  https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/nvme/apple,nvme-ans.yaml
  Blob `4c0b1f90aff846e345ec040b22be42f451cf955f`.

Implementation inspected against `cf9d952376ca96af721a182b3604a07742717050`;
branch based on `ce623c040937ba5ed4dd512dc4f92b9dc7bec850`, whose intervening
changes do not modify these integration points.
