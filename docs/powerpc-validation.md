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
