# PowerPC bring-up validation

2026-11-08, macOS ARM64 host, V `b7b4dd46ee`, Zig 0.17.0,
QEMU 11.1.2 / OpenBIOS 1.1.

CD firmware boot: **pass**. The ELF executes from an ISO9660 CD through
OpenBIOS on `mac99,via=pmu`, CPU 7450, 512 MiB RAM. Guest checks cover the
PPC32 big-endian firmware ABI, PVR/MSR access, clock progress, successful and
failed CAS, cache publication, memory discovery and a copied 50-node FDT.
The host independently validates the FDT dumped from guest RAM. FDT corruption
unit tests also pass. The ISO's ELF extracted with bsdtar matches the input.

Artifact bundle: `/tmp/vinix-ppc-media-verified` (outside Git).
Base source revision: `6366119cb1d5aa6e634a9e14308625e74499294d` plus the
exact implementation inputs preserved under `sources/` and `sources.sha256`.
`SHA256SUMS` digest:
`e187b562dd53d237417f0ffa3111679d63ba13ffc395db1a8e95e82955232ac7`.

Compiler patch validation: 50 parser tests, 1881 compiler-error cases (6
skipped), 8 comptime-definition cases, 104 inout files (92 successful runs,
11 expected panics, 1 skipped), and 332 checked documentation examples.
Compiler test logs are `/tmp/vinix-v-ppc-errors.log` and
`/tmp/vinix-v-ppc-inout.log`. The raw PPC assembly is also exercised by the
guest tests above.

This does not validate the complete Vinix kernel, userspace, desktop, or
physical iMac hardware. The loader currently returns to firmware.

## ELF32 handoff

The subsequent CD-to-loader-to-ELF probe also passes. It verifies initialized
data, zeroed/writable BSS, an aligned claimed stack, boot-info fields, FDT
magic and exclusion of kernel/stack pages from the available-memory map.
The loader checks each claimed page through the firmware MMU `translate`
method before transferring control. Host ELF tests cover every truncated
prefix, malformed headers, integer/bounds/alignment errors, unsupported
dynamic loaders, nonexecutable entries and overlapping segments. Both the
ELF and FDT host test files pass.

Artifact bundle: `/tmp/vinix-ppc-handoff-verified`.
Base revision: `86ca85518e2161512ab64a61ab5623670bf60ccb`; exact inputs are
preserved in the bundle's source snapshot and manifest. `SHA256SUMS` digest:
`79830df8a4334c22292869630d5062ad998a8dbe818eb3e575cc4d9ee5f69d0f`.
The loaded ELF is a test fixture; this is not a full-kernel boot.

## Initial kernel takeover

`test-kernel` passes its native SCC console, system-call exception return,
and repeated decrementer interrupt checks. The kernel stops using firmware
and does not return to its prompt. Physical-frame ownership and hash-table
policy host tests also pass, including exhaustion and invalid free cases.

Bundle: `/tmp/vinix-ppc-kernel-stage`, base revision `9992871cd` plus the
exact source snapshot in the bundle. `SHA256SUMS` digest:
`66a3272b5d147821668db970d7050f000660dd41019572749bdfcf8459a943fa`.
This stage has no userspace or interactive shell yet.

## Protected userspace

The subsequent kernel check enters problem state with instruction/data
relocation enabled, completes a getpid-style syscall, and recovers only at
the expected PCs from four deliberate faults: kernel-memory read,
privileged `mfmsr`, text write, and execution on a non-executable stack.
It then returns to supervisor mode. QEMU passes all checks using the
G4-compatible 64-index TLB invalidation sequence.

Bundle: `/tmp/vinix-ppc-mmu-verified`, base revision `d60df15c9` plus the
preserved source snapshot. `SHA256SUMS` digest:
`4f196992a9599bf97d453655b98bbf81de30b7c450a6f1890a0cf124b2037a12`.
This is still a protection fixture; it is not an interactive shell.

## Interactive userspace shell

`test-shell` passes from ISO boot through kernel takeover to a separately
loaded `/bin/init` ELF32 process. It exercises `help`, root and nested `ls`,
`cat`, `pwd`, `ps`, `uname`, `mem`, `echo`, backspace, missing files, invalid
commands and exit. Thirty-two repeated open/read/close cycles preserve the
free-page count. In-guest syscall checks reject kernel pointers, writes to
text, a buffer crossing into unmapped memory and unknown/test-only syscalls;
they also exercise descriptor exhaustion/reuse and a valid page-spanning
file read. USTAR corruption/truncation, capacity, duplicate-name and
unsupported-entry host tests pass. The diagnostic media handoff still passes.

Shell bundle: `/tmp/vinix-ppc-shell-final`, base revision `73f5b1470` plus
the exact source snapshot and `sources.sha256`. `SHA256SUMS` digest:
`e82365c6eab3e4496b282ccf4915cc46046dbf63a57d70bcc9f62e88c5b2bec0`.
Media regression bundle: `/tmp/vinix-ppc-initramfs-media`, base revision
`209da615e` plus its source snapshot. `SHA256SUMS` digest:
`6e02cedcf0a4b1d29f359adf405fb06ff51f0ea1b9ecf6c408689c4a53f64e91`.

This validates the initial PPC kernel and freestanding V shell under QEMU,
not the shared Vinix kernel, ordinary Linux programs, desktop, or physical
iMac G4. The default runner now selects the shell and terminal serial I/O.

## 128 MiB guest

The same complete shell suite passes with `VINIX_PPC_MEMORY=128`, including
protection checks, commands, descriptor reuse, stable free pages and exit.
The allocator reports 86,416 KiB managed and 86,204 KiB free, with firmware
and boot-file claims still reserved. This is the initial shell's footprint,
not a measurement of the future desktop.

Bundle: `/tmp/vinix-ppc-shell-128`, base revision `9875519d2` plus the source
snapshot. `qemu.txt` records the emulator version and arguments.
`SHA256SUMS` digest:
`d8ade0131037fb97b56dc1f4375b262d6fc279865f3417259f6be86252202dab`.

## Framebuffer console

The inherited 800x600 32-bit framebuffer renders the shell with a readable
mixed-case font, line wrapping, scrolling and backspace. QEMU screenshot
validation checks separate RGB swatches and foreground pixels after the
complete shell command suite. The screenshot was also visually inspected.
Firmware diagnostics are mirrored to SCC when stdout is the display.

Bundle: `/tmp/vinix-ppc-video`, base `775898128` plus preserved sources.
`SHA256SUMS`: `86863aef30576e3ebf766c1657517695422986e8499a39a24bfabe9d2a7a6737`.
This verifies the graphical console, not accelerated GPU rendering or the
shared Vinix desktop; keyboard input in this stage is still serial.

## OHCI USB input

The kernel discovers UniNorth PCI OHCI, enables MMIO and bus mastering,
resets its root ports and enumerates the directly attached keyboard/mouse.
The test types `echo usb-aZ` using HMP key events, including Shift and
Backspace, and checks the command's result in the independent serial log.
Mouse events move the pointer by 50,30 pixels; screenshots verify every
arrow pixel before, during and after the left-button press. The complete
shell/protection/memory-stability suite also passes with these devices active.

Bundle: `/tmp/vinix-ppc-usb-final`, base `3d2b574dc` plus preserved sources.
`SHA256SUMS`: `7750175edf3ed39e3edbf09811d24c3e14c19e86b0966863dc83070cd2da6c45`.
This covers QEMU boot-time HID devices. Hubs, reconnection, other USB classes
and native iMac validation are separate work.

## GEM Ethernet

QEMU boots with Apple UniNorth GMAC. The userspace `net` command completes
DHCP DISCOVER/OFFER/REQUEST/ACK; `ping` resolves the gateway through ARP and
checks ICMP checksums, source/destination, sequence and payload. Sixty-four
echo exchanges wrap both 32-entry DMA rings repeatedly. The harness drops
and restores the emulated link, verifies its reported state, and receives
four further replies. An independent pcap checker requires all 68 matching
request/reply pairs plus DHCP and ARP traffic. Free physical pages stay
constant across networking and repeated file operations.

Host parser tests reject every truncated DHCP prefix, malformed lengths,
wrong transaction/MAC, bad IPv4/UDP checksums, fragments, duplicate options
and unsupported option overloading. In-guest tests reject invalid user
pointers, oversized TX frames, unknown ioctls and directory operations on
the packet device. The USB input and framebuffer checks pass in the same run.

Bundle: `/tmp/vinix-ppc-network`, base `224d57e15` plus preserved sources.
`SHA256SUMS`: `4ced056c490690650b908ca7442f079ea65f029ef873db205ae0986c14e2299f`.
This validates GEM DMA and the small userspace network utility in QEMU,
not shared-kernel sockets, TCP, gigabit PHYs or physical iMac Ethernet.

## USB PCM playback

The OHCI driver enumerates a UAC1 speaker, unmutes it, selects its streaming
interface and submits checked isochronous TDs. Two independent writes of
48000 stereo frames complete successfully. The host WAV contains exactly
96000 nonzero frames, with expected channel amplitudes and 1000/500 Hz sign
transitions. This checks actual output, byte order, channel order, timing
and buffer reuse. USB key events injected during the first write are queued
and subsequently execute `echo ok`. Framebuffer, mouse, Ethernet, memory
stability and invalid-buffer checks pass in the same boot.

Uptime now uses the 64-bit timebase instead of counting timer interrupts,
so synchronous playback does not lose elapsed seconds. The freestanding
64/32 division helper passes host tests through maximum-width operands.

Bundle: `/tmp/vinix-ppc-audio-final`, base `984ff5b92` plus preserved sources.
`SHA256SUMS`: `682b86277054d11b5d1e19b7062e7ac26fe19a296c5decc92fee3cf89c0683c4`.
This verifies the fixed-format USB output in QEMU. Native iMac speakers,
other USB audio profiles, input capture and asynchronous mixing are untested
or unimplemented, as detailed in the port document.

## Nested USB hubs

The complete graphics/input/audio/network shell suite passes with 128 MiB
RAM and two external hub tiers. The keyboard is on the first hub; the mouse
and speaker are on the second, which requires per-port power switching.
There are no directly attached HID devices in this topology. The same
screenshot, PCM waveform and packet-capture checks pass, including keyboard
events during audio playback and stable free pages. Enumeration supports
bounded USB 1.1 hub traversal; reconnection remains separate work.

Bundle: `/tmp/vinix-ppc-hubs-final`, base `6fa5980cd` plus preserved sources.
`SHA256SUMS`: `81ffb33dd9d52f5af5eb53daedb301e719e92d095f3800208b854353bb40b1aa`.

## RGB555 framebuffer

The full shell suite passes in both 15-bit and 32-bit modes. RGB swatches,
text and pointer colors are checked at their exact expected precision.
Moving the pointer away restores all 384 underlying pixels byte for byte
against a pre-movement screenshot. The RGB555 console was also visually
inspected. The loader now accepts the firmware's 15-bit depth property;
the renderer rejects unaligned framebuffer addresses and scanline strides.

Bundles, both based on `2e85fd5b1` plus preserved sources:

- `/tmp/vinix-ppc-rgb555`, `SHA256SUMS`:
  `d1c64d3a1c1f61d23949bb6868c5652c743a62b9d72d085dd972405324ffb63a`.
- `/tmp/vinix-ppc-rgb32-regression`, `SHA256SUMS`:
  `a36967ff740da54d11353c9d3744ede8b3cd6b720485e0a652842094699cfce4`.

## Protected userspace graphics

`/dev/fb0` geometry queries and bounded shared mappings pass in both display
formats. The userspace test rejects invalid pointers, executable/private
mappings, nonzero offsets, oversized mappings, duplicate mappings and writes
through a read-only descriptor. Sixteen map/write/read/unmap cycles preserve
free memory. A final mapping remains valid after its descriptor is closed;
all 480000 pixels of its generated image match an independent screenshot
check. Unmapping restores console text and the pointer. The RGB555 image was
also visually inspected.

The kernel protection fixture now primes a data TLB entry, removes its PTE
and requires a fault on the next userspace load at the expected PC/address.
Hash lookup tests cover primary/secondary collisions and slot reuse.
The complete input, audio and Ethernet suites pass alongside these checks.

Bundles, based on `9b822d048` plus preserved sources:

- `/tmp/vinix-ppc-fbdev-final`: RGB555, nested hubs, 128 MiB; `SHA256SUMS`
  `fe359b84a93951d39ef603a8cf25812c77c239c759d20f63513eb05792c60013`.
- `/tmp/vinix-ppc-fbdev-32-final`: RGB32, direct USB, 512 MiB; `SHA256SUMS`
  `89e9b8b28fd0637eb2e17e15d89601dc50cfba27d5f8049abcb552b4f9fd83d4`.

## Userspace pointer input

The shared `/dev/pointer` packet layout now reaches protected PPC userspace.
QEMU injects a 7,-4 movement and a complete left click between two reads.
The returned packet has the expected coordinates, released button level and
both click edges. Rejected short/invalid-pointer reads leave the edges intact;
the next valid read consumes them. Both 32-byte and 36-byte reads pass. Host
tests additionally exercise signed-delta extremes and coordinate clamping.

The full framebuffer, nested-hub, audio, network and stable-memory suite
passes with 128 MiB RAM. Bundle: `/tmp/vinix-ppc-pointer-final`, base
`3e96b4ec9` plus preserved sources. `SHA256SUMS`:
`7eafa5d74475df4e4a2f82eeca150cc80af6b09810580c4e95b6e184d1736d4d`.

## Serial-mode regression and HID length guard

The final serial-mode suite passes after adding a completion-length guard
to HID reports. Short successful transfers are rearmed without interpreting
old bytes in the DMA buffer. The normal QEMU keyboard/audio/network paths
pass; malformed USB report injection is not part of this emulator run.

Bundle: `/tmp/vinix-ppc-hid-serial-final`, base `695cb08f4` plus preserved
sources. `SHA256SUMS`:
`f9440c4ed340613fdd4ff4ba8e47af7324427482b8fbf55e46a16f461d85b155`.

## Desktop framebuffer ABI (2026-11-08)

The desktop's shared fbdev structures now use pointer-width physical addresses.
The previous `u64` fields displaced the pitch and length on PPC32. The V checker
compiles size and field-offset assertions against the unmodified Linux v6.12
`include/uapi/linux/fb.h` for PowerPC32, x86-64 and AArch64; all three passed.

Reproduce with `v run tests/powerpc/check-fbdev.v UAPI_INCLUDE OUTPUT_DIRECTORY`,
where `UAPI_INCLUDE/linux/fb.h` is the upstream header. The checker uses Zig's
target-specific libc and Linux type headers. This verifies the ioctl layout,
not a running desktop.

Base revision: `8d6c7461e`, with the source overlay preserved in
`/tmp/vinix-ppc-fbdev-abi-final/sources/`. Bundle:
`/tmp/vinix-ppc-fbdev-abi-final/SHA256SUMS`, digest
`5ee0e99a2efcd77ba5fcb502286b976051da96a6c25e346c82ea7c14fc1277e9`.

## Native desktop cross-link and libc startup (2026-11-08)

The actual desktop links as a static PPC32 MSB executable with the compiler/ui2
revisions documented in `powerpc.md`. The two staging tests passed. The complete
build/source archive is `/tmp/vinix-ppc-desktop-audit`, base `77947bc7b`;
`SHA256SUMS`: `e9ce54ee18b0c626ad592212d71a9354c5bda42c072fb4aee79bbbaf19523708`.
This is an application cross-build, not proof of a running desktop session.

The native musl-linked V runtime probe boots through Open Firmware, enters user
mode, passes argv/environment/auxv/TLS checks, performs 200 heap/mapping cycles
with stable free-page counts, checks zeroed reused mappings and rollback after
capacity exhaustion, uses libm across syscalls, checks monotonic time and exits
with status zero. Host ELF tests also cover malformed and duplicate TLS headers.
The unchanged graphics/USB/audio/network shell suite passed at 128 MiB with two
USB hub tiers. Both bundles preserve the `77947bc7b` source overlays:

- `/tmp/vinix-ppc-libc-final`: runtime test. `SHA256SUMS`:
  `336ef43120c3033ab94fa0a501580d4f73291fb4ce7a8b1c376f4334e2d9d6a4`.
- `/tmp/vinix-ppc-libc-regression`: full device regression. `SHA256SUMS`:
  `38de388be8066bcc69f064555e4b9b94b61beae76a96ceef17cca517f7b2dc48`.

## Desktop-sized address space (2026-11-08)

The 512 KiB hashed page table and 32,768 mapping records accommodate the real
desktop's image and heap. User-buffer translation now searches the hardware
hash groups rather than scanning every mapping. The user stack is 2 MiB, and
the boot archive limit is 32 MiB; the kernel read buffer stays at 16 MiB so it
does not occupy the kernel's required load address on the 128 MiB guest.

The host collision/exhaustion hash tests passed. At 128 MiB the libc probe
successfully maps 32 MiB, then allocates until exhaustion, releases every block
and verifies the original free-page count. The full graphics, nested-hub USB,
audio and Ethernet regression also passes. Base `d4591db06` plus preserved
source overlays:

- `/tmp/vinix-ppc-large-runtime`, `SHA256SUMS`:
  `4bdb5879c7403354a0aaafbf0b16895aa28ac1b518a5fbd82cf3856e7efedfcc`.
- `/tmp/vinix-ppc-large-regression`, `SHA256SUMS`:
  `daeea1f3821f178ac84abf1e39786c327f48c581ad68e876636374f51ec21e20`.

## Desktop process identity and startup calls (2026-11-08)

The initial process now reports root UID/GID, `/` as its working directory,
and CPU 0 as its affinity. Read-only opens accept the libc metadata flags
while enforcing `O_DIRECTORY`. The real musl probe checks all four identity
calls, cwd and affinity buffer errors, nonexistent PIDs, 200 open/read/close
cycles, directory rejection and write rejection. All checks and the existing
heap/FPU runtime checks pass in a 128 MiB guest.

`VINIX_PPC_TRACE=1` enables bounded failed-syscall diagnostics. The boot deadline
is 60 seconds to accommodate larger native applications. Bundle, based on
`9a7253674` with preserved sources: `/tmp/vinix-ppc-startup-runtime`;
`SHA256SUMS`: `4d6a6bdfd15fcf08b77735a8063570808927096fce98c8fd82de65c68bd7a60e`.

## Native desktop first frame and USB input (2026-11-08)

The real desktop now links into the kernel's text/data ranges and boots as
`/bin/init`, with static musl and software rendering. QEMU's 800x600 scanout
shows the existing "Create your user" form. USB typing enters `vinix` in the
name field; a mouse click focuses the password field and subsequent typing
appears as three masked characters. Both captures were visually inspected.
The initial console-only capture was taken before the first render completed;
the V capture runner now waits five seconds after the startup marker.

This proves native application rendering and input, not account persistence
or a working multi-process desktop session. Registration is not bypassed.
The kernel still lacks writable filesystems, process creation and Unix sockets;
poll/nanosleep are also not yet implemented at this milestone.

Preserve these bundles together (base `d4591db06`/`9a7253674` and source overlays):

- `/tmp/vinix-ppc-desktop-native`, application build/source archives,
  `SHA256SUMS`: `adf460c95e160645e8e0e64bec5e8da76fa18bc2429b3dc10c8866874aa8ef21`.
- `/tmp/vinix-ppc-desktop-boot2`, native kernel/image/source inputs,
  `SHA256SUMS`: `f1e137690f0db5d8c1332b2c4389b8a3fcb23ffbdcd51a37e07d988acac302fb`.
- `/tmp/vinix-ppc-desktop-input`, capture runner, logs and three PPMs,
  `PROGRAM-SHA256SUMS`: `1fc6bd3a5c959583761335b446b2e03832f93c90e1cf0fbeb236b99dad5f8cf0`.

## Desktop input waits (2026-11-08)

PPC32 `poll` and the time32 `nanosleep` used by musl now wait against the
timebase while servicing OHCI. Readiness does not consume keyboard bytes,
pointer edges or Ethernet packets. Negative descriptors, error event masks,
timeouts, invalid buffers, invalid times and the descriptor bound are handled.
The kernel remains single-process and these waits still spin; CPU idle and
signal interruption need interrupt-driven drivers and a scheduler.

The musl probe passes measured 20 ms sleep and 15 ms empty-poll deadlines,
mixed-descriptor/error tests, infinite keyboard wait and timed pointer wait.
Repeated polls preserve pending input until read. Host pointer readiness tests
pass, and the 128 MiB graphics/nested-hub/audio/Ethernet regression passes.
Base `3289116b1`, with complete source snapshots:

- `/tmp/vinix-ppc-wait-runtime2`, `SHA256SUMS`:
  `51ee9fb555738cc80852322474c941df51a5451f1eea14e80e94d14f8cbad3a1`.
- `/tmp/vinix-ppc-wait-regression`, `SHA256SUMS`:
  `1a865a14b2e33da3f4d015855e1674fa6028c8d69f49bd2b05da35655a43f0bc`.

The desktop again renders its form and accepts typing and mouse focus. An
initial image preview appeared blank; checking the saved pixels and viewing
the original resolution showed the complete form. The clicked PNG from this
run is byte-identical to the repeat run's good image (SHA-256
`dd2fbcb3b99c442a2be16acbd21fe0ee98c03fc8598fc77c4a28aa0ad7bf2b26`).
The preview was not evidence of a guest rendering fault.

- `/tmp/vinix-ppc-desktop-ready`, boot `SHA256SUMS`:
  `0c1e0596d47e160098368eb6067b675f9154172d9b273bc672c7fff3436b2b0a`;
  capture `PROGRAM-SHA256SUMS`:
  `882dcc8f6f6b56fa2e139fe62d382965eb497b12b8e29f2761c5c13d4980c989`.
- `/tmp/vinix-ppc-desktop-waits-recheck`, `PROGRAM-SHA256SUMS`:
  `574af8e4fff8430717c3948c4b84b5833db2230edf30d6649222cea0e4e14f6f`.

## Independent desktop capture checks (2026-11-08)

`tests/powerpc/check-setup.v` checks the actual QEMU PPM dimensions, backdrop,
card edges and heading ink, plus name/password field changes from USB input
and unchanged settled fields. A 20-frame follow-up sequence passes; an older
console-only capture is rejected. This checks observable application output
independently of serial startup markers. It does not claim account creation,
session startup or physical iMac validation.

Bundle `/tmp/vinix-ppc-desktop-stability` uses the native image above, base
`1b0610e82` plus preserved capture/checker sources. `PROGRAM-SHA256SUMS`:
`f8a06f42c118aa0368b5a25c6bb95c85265f5e1b1cd23c50093d8e100300713b`.
`CHECKER-SHA256SUMS` covers the checker and positive/negative reports:
`c0a39ae871665d819f0f6e8ffa5b88a617eb7c548773601a29a967434323e136`.

## Native ATA persistence (2026-11-08)

The loader discovers KeyLargo/Heathrow ATA taskfiles from Open Firmware. A
native polled LBA28 driver identifies disks, transfers 512-byte sectors with
explicit little-endian data words, bounds requests, and issues FLUSH CACHE.
ATAPI boot media are skipped. No firmware disk calls occur after takeover.

The destructive test is compiled only with `VINIX_PPC_TEST_ATA=1` and requires
an exact 4 MiB disk with its fixture label. Two QEMU boots update the final
sector; an independent host comparison checks every byte, including unchanged
neighbours. Out-of-bounds requests fail. This is QEMU validation; hardware
controller reset/timing setup and LBA48 remain future work.

Reproduce: `v -o /tmp/ppc-ata-test run tests/powerpc/ata-disk.v FRESH_DIRECTORY`.
`VINIX_PPC_DISK` attaches an existing raw disk to normal launcher runs.
Bundle `/tmp/vinix-ppc-ata-persist3`, base `5f33f0d56` plus saved sources:
top-level `SHA256SUMS` `c7efad4397caf07bb198ac8b1caefbbf24c63cb998aa9f03ca9d50d1c50b105f`;
`boot-1/SHA256SUMS` `6e7920dda0de1631cb5a18d6118d97118953e8645324171a78d731e251488c64`;
`boot-2/SHA256SUMS` `3281ca5803f68c84d6e30c55139469b16603bdaa94ca0b1be8c65c32902634dc`.
