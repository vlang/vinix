# PowerPC G4 port

Target: 32-bit big-endian PowerPC, initially the 7450 CPU and Open Firmware
on a NewWorld Macintosh. QEMU `mac99,via=pmu` is the development machine.
The port boots a small native kernel and protected userspace in QEMU. The
actual Vinix desktop now saves first-run accounts to an ext2 disk and reaches
the compositor, icons, taskbar and System window after a restart. USB keyboard
and mouse work. Separate applications still require process/IPC services. This is not yet a
complete end-user system or the shared Vinix kernel.

## Build and test

The host needs V with `-arch ppc` support, Zig with its PowerPC LLVM backend,
and `qemu-system-ppc`. Apple Clang does not include that backend. All maintained
build and test tooling is V. Zig compiles V's generated C; the firmware and
kernel remain freestanding. The desktop uses static musl.

The CPU backend requires V commit `b7b4dd46ee` (raw PPC assembly support), or
a later compiler containing that change. It is installed in the sibling `../v`
checkout. An alternate compiler can be selected with `VINIX_V_COMPILER`.

### Desktop cross-build

The actual `desktop/` compositor cross-links as a big-endian PPC32 static
executable, including the ui2 calculator, software renderer and musl runtime.
Its linker script places text at `0x40000000` and data at `0x50000000`, within
the native kernel's protected address ranges. Debug sections are omitted so
the application fits the bounded boot archive.

The tested desktop toolchain is deliberately separate from the kernel compiler:
V `1f4d705322714d6ab35a712db9d1b93db9fbcc03`, with the one-line `math.round`
type fix from upstream `8e4573656196e71851153400b4df608fbde951d6`, and ui2
`8b2179604a37056dd5a2b9afc3f4666e38bf4749`. Current V removed `$vml`; this
desktop still uses it. The isolated compatible V checkout on this host is
`/tmp/vinix-ppc-v-desktop` (local backport commit `dc06c1a39f`).

```
VINIX_UI2_SOURCE=/tmp/vinix-ppc-ui2 VINIX_PPC_DESKTOP_V=/tmp/vinix-ppc-v-desktop/v v run tools/powerpc-desktop /tmp/vinix-ppc-desktop
```

The runner stages sources with V, builds the freestanding presenter/execinfo
modules, and links with Zig's `powerpc-linux-musleabihf` libc and unwinder.
It preserves build logs, source archives, revision/overlay records and checksums
outside Git. It does not modify the compiler or ui2 source checkouts.

To build an image with that desktop as `/bin/init`, create a persistent disk
once, then boot it (macOS also needs `brew install e2fsprogs`):

```
VINIX_PPC_INIT=/tmp/vinix-ppc-desktop/vinix-desktop v run tools/powerpc build /tmp/vinix-ppc-desktop-boot
v run tools/powerpc-disk "$HOME/vinix-powerpc.raw"
qemu-system-ppc -M mac99,via=pmu -cpu 7450 -accel tcg -m 512 -smp 1 -nic user,model=sungem -g 800x600x32 -display cocoa,zoom-to-fit=on,zoom-interpolation=off -drive "file=$HOME/vinix-powerpc.raw,format=raw,if=ide,index=0,cache=writeback" -cdrom /tmp/vinix-ppc-desktop-boot/vinix-ppc-boot.iso -boot d -prom-env 'boot-device=cd:\BOOT.ELF;1' -prom-env 'boot-file=cd:\KERNEL.ELF;1 cd:\RAMFS.TAR;1' -prom-env 'output-device=scca' -serial mon:stdio
```

The formatter refuses existing images. Reuse the same disk on subsequent boots
to keep the account and home folders. Keep the disk outside temporary build
directories. On other hosts, omit the Cocoa display option and select their
QEMU display backend. The normal shell image remains useful for the USB audio
and Ethernet regression commands.

The disk is a 64 MiB raw ext2 volume; there is no partition table or installer.
`VINIX_PPC_DISK=/absolute/disk.raw` attaches it when using `tools/powerpc run`
or the capture runner. Add `VINIX_PPC_GRAPHICS=1` for a graphical window; the
macOS launcher enables zoom-to-fit automatically. Boot files remain in the
read-only archive; disk paths such as `/root`, `/home`, `/tmp` and `/run` are
writable. Directory moves, files above 4,243,456 bytes, a merged root directory
listing, and general `*at`/process/IPC compatibility remain pending.

The private disk seed comes from the host CSPRNG and is rotated and flushed
before `/dev/urandom` or `getrandom` serves bytes. Keep images private and create
a fresh disk for each independent installation; copying a disk or restoring a
snapshot also copies its random state. This initial port has no independent
hardware entropy reseeding. Account profiles use the desktop's existing scrypt
format and mode 0600. Successful file/directory fsync reaches ATA FLUSH CACHE;
ext2 is not journaled, so an interrupted metadata update can need offline fsck.
The wall clock currently starts from the filesystem timestamp, not the Mac RTC.

Two-boot regression bundles (including screenshots, source, disks and hashes):

```sh
v run tests/powerpc/persistence.v abi /external/fresh-storage-test
VINIX_PPC_INIT=/path/to/traced/vinix-desktop v run tests/powerpc/persistence.v desktop /external/fresh-account-test
```

The desktop test enters disposable `vinix` / `test123` credentials through USB,
checks the saved hash and permissions, restarts QEMU, and requires a presented
desktop frame. Never use its disk as your personal installation. See
[storage validation](powerpc-storage-validation.md) for preserved evidence.

Set `VINIX_PPC_TRACE=1` on both build commands for startup diagnostics. Capture
the real framebuffer and exercise setup typing/focus without submitting it:

```
VINIX_PPC_TEST_SETUP=1 v -o /tmp/ppc-boot-program run tests/powerpc/boot-program.v /tmp/vinix-ppc-desktop-boot 'vinix-desktop: GPU init: checking user profile'
```

`VINIX_PPC_CAPTURE_DIR` optionally separates captures from the image directory.
The runner waits for the startup marker and allows the first frame to finish;
its marker result alone is not a visual assertion. Validate the captured form,
rendered heading, USB field changes and settled input with:

```
v -o /tmp/ppc-check-setup run tests/powerpc/check-setup.v /tmp/vinix-ppc-desktop-boot
```

Set `VINIX_PPC_TEST_STABILITY=1` on the capture command for 20 additional
frames checked by the same verifier. Images and logs stay outside Git.

On macOS, add `-display cocoa,zoom-to-fit=on,zoom-interpolation=off` to enlarge
the guest display as you resize the window, with sharp pixel scaling. The
existing window offers **View → Zoom To Fit**. An 800x600 guest displayed in
a 1600x1200 area is 2x; 3200x2400 is 4x if the host screen is large enough.
This scales the display without changing the guest's framebuffer resolution.

```
v run tools/powerpc test /tmp/vinix-ppc-state
v run tools/powerpc test-media /tmp/vinix-ppc-cd-state
v run tools/powerpc test-kernel /tmp/vinix-ppc-kernel-state
v run tools/powerpc test-shell /tmp/vinix-ppc-shell-state
v run tools/powerpc test-runtime /tmp/vinix-ppc-runtime-state
v run tools/powerpc run /tmp/vinix-ppc-state
```

Override executable locations with `VINIX_V_COMPILER`, `VINIX_PPC_ZIG` and
`VINIX_PPC_QEMU`. Set `VINIX_PPC_MEMORY` to the guest RAM in MiB (128..2048,
default 512). For the small-memory check:

```
VINIX_PPC_MEMORY=128 v run tools/powerpc test-shell /tmp/vinix-ppc-128
```

`test-runtime` boots a V test program linked with real musl crt1/libc/libm.
It verifies the initial argument/environment/auxiliary stack, ELF TLS, errno,
200 malloc/free and anonymous mmap/munmap cycles, zero filling, failed-map
rollback, monotonic time and floating-point values surviving system calls.
The single-process kernel now supports a bounded `brk` heap and private RW
anonymous mappings. Executable/shared/fixed anonymous mappings remain rejected.
Its integer-only kernel build disables the LLVM hard-float feature; the one
user process owns the FPU until scheduling and per-thread FPU contexts exist.
The runtime probe also checks identity/cwd/affinity and libc open flags, then
times `nanosleep` and `poll` and wakes blocked polls through injected USB input.
The single-process wait loops service polled devices; they do not yet idle
the CPU or support signal interruption.
`VINIX_PPC_INIT` can select an alternate static executable for the boot archive;
its ELF segments must respect the existing PPC text/data address ranges.

The optional directory defaults to a worktree-specific path
under the system temporary directory. Keep output outside Git.

The test cross-compiles a freestanding V firmware client, links an ELF32 MSB
PowerPC executable, and boots its flat image through OpenBIOS. The client
uses the firmware-provided stack and r5 client-interface pointer. It validates
pointer width, firmware-call layout and byte order inside the guest, then
prints `VINIX-PPC: PASS ppc32 big-endian firmware`. It then copies the firmware
tree into a bounded FDT v17 buffer, discovers framebuffer metadata if present,
and snapshots available memory after its claims, explicitly excluding its own
image. Firmware reservations remain excluded. The runner requires the later
`VINIX-PPC: PASS firmware discovery` marker, dumps the copied FDT through the
QEMU monitor, and independently validates its structure and node count.
It has a 60-second boot deadline, kills/reaps its own emulator, and saves
`boot.log`, `firmware.dtb`, and binary/FDT SHA-256 files in the output directory.
`test-media` instead loads the ELF from the generated ISO through OpenBIOS,
then reads and executes a separate ELF32 handoff probe. It records
`media-boot.log`. `test-shell` boots the kernel and initramfs, exercises
commands through the serial port, checks errors and repeated file access,
and records `kernel-boot.log` and `shell-commands.log`.
`run` starts the interactive shell in the host terminal. Type at `vinix$`;
exit QEMU with Ctrl-A then X. The shell's `exit` command stops init.
It no longer selects the returning handoff probe that showed `0 >`.
The V image builder writes ISO9660 directly, without external image utilities.
Each build saves its base Git revision, tool versions, exact source inputs,
and SHA-256 manifests (`sources.sha256` and `SHA256SUMS`) outside Git.
`qemu.txt` records the emulator version and exact launch arguments.
Host corruption tests run with `v test tools/powerpc/validate_test.v`.
ELF validation tests run with `v test kernel/powerpc/elf32`.
Archive validation tests run with `v test kernel/powerpc/ramfs`.

Direct QEMU command after building:

```
qemu-system-ppc -M mac99,via=pmu -cpu 7450 -accel tcg -m 512 -smp 1 -nic user,model=sungem,id=net0 -audiodev coreaudio,id=sound -device usb-audio,audiodev=sound,port=3 -cdrom /tmp/vinix-ppc-state/vinix-ppc-boot.iso -boot d -prom-env 'boot-device=cd:\BOOT.ELF;1' -prom-env 'boot-file=cd:\KERNEL.ELF;1 cd:\RAMFS.TAR;1' -serial mon:stdio
```

This command boots the PPC kernel and initial userspace shell. This ISO
has no partition map, so OpenBIOS takes the filename immediately after the
colon; adding a comma prevents lookup. Keep the ISO file version `;1`.
Input/output uses the emulated SCC serial port. Set `VINIX_PPC_GRAPHICS=1`
to enable the inherited framebuffer, scrolling console and USB mouse
pointer. USB boot-protocol keyboard input works alongside serial input.
For a window with keyboard and mouse, use:

```
VINIX_PPC_GRAPHICS=1 v run tools/powerpc run /tmp/vinix-ppc-state
```

The renderer supports 32-bit RGB and 15-bit RGB555 in big-endian pixel
order. `VINIX_PPC_DEPTH=15` selects QEMU's RGB555 mode; the default is 32.
Other framebuffer depths and mode switching remain unsupported. The mouse
cursor saves and restores native pixels without repeated color conversion.

`/dev/fb0` exposes PPC32 Linux-layout `FBIOGET_VSCREENINFO` (160 bytes) and
`FBIOGET_FSCREENINFO` (68 bytes). `mmap2` can map the entire framebuffer at
`0x58000000`, with `MAP_SHARED`, offset zero and read-only or read/write
permissions. The mapping is non-executable, cache-inhibited and guarded;
it survives closing the descriptor. This is a bounded fbdev mapping API,
not general anonymous/file-backed mmap. Partial mappings, mode switching,
read/write calls and additional simultaneous mappings are not implemented.
`munmap` revokes the mapping and restores the console; exit does the same.
The kernel keeps console text in memory while userspace owns the screen.

Run `fbtest` in the shell to draw directly from protected userspace. It
checks geometry layouts, access restrictions, mapping reuse and pixel
readback, then displays a color pattern until Enter. Graphical shell tests
check every captured pixel and the restored console. This is the display
interface used by the native desktop's software renderer.

The same variable on `test-shell` verifies framebuffer RGB colors and text,
types a command through QEMU's USB keyboard, and checks mouse movement and
button press/release against screenshot pixels. OHCI uses little-endian
descriptors, explicit G4 DMA cache ownership and bounded polling. This first
driver supports boot-protocol HID devices present at boot, directly attached
or behind full-speed hubs (up to eight ports, four tiers and 32 addresses).
It powers and resets downstream ports before assigning unique addresses;
failed address assignments disable the port to isolate address zero.
Reconnection, key repeat, storage and EHCI remain pending. It does
not call firmware for keyboard, mouse or console output after takeover.

Set `VINIX_PPC_USB_HUB=1` to exercise two nested hubs: the keyboard is behind
the first, and the mouse and speaker behind the second. The second hub has
switchable port power. Combine it with `VINIX_PPC_MEMORY=128` and
`VINIX_PPC_GRAPHICS=1` on `test-shell` to verify all three drivers together.

`/dev/pointer` returns the shared Vinix fixed-width pointer snapshot ABI:
big-endian 32-bit x/y, coordinate maxima, button level, pressed/released
edges, and scroll axes. Reads accept the original 32-byte prefix or the
36-byte extended packet. Edges accumulate until a successful read, including
a complete click between reads; invalid buffers do not consume them.
The boot-protocol mouse currently reports three buttons and no wheel data.
`pointertest` lets you move/click, then press Enter to inspect the snapshot.
It supports read-only/nonblocking opens; poll/epoll readiness and hotplug
are not yet connected to the shared kernel.

The GEM Ethernet driver enables Apple UniNorth GMAC MMIO and bus mastering,
finds its MII PHY, negotiates 10/100 duplex, and uses separate 32-entry RX/TX
DMA rings. RX descriptors are recycled in groups of four to preserve cache
ownership on a G4. `net` obtains a DHCP lease; `ping [IPv4]` resolves a next
hop with ARP and sends four checked ICMP echo requests (the default target
is the DHCP gateway). QEMU's user network normally assigns `10.0.2.15`.

The development `/dev/net0` interface reads/writes one Ethernet frame per
call, without FCS. Open with flag 2 for writes; frame size is 14..1514 bytes.
Reads return EAGAIN when empty, or EMSGSIZE and discard an oversized frame.
Ioctl `0x564e0001` returns 16 bytes: MAC[6], reserved[2], big-endian 32-bit
link state and MTU. User pointers, frame lengths and descriptor types are
checked. DHCP/ARP/ICMP live in the freestanding shell; this is not yet the
shared kernel's TCP/IP socket stack. DNS, TCP, IPv6, background lease renewal,
gigabit PHY tuning and iMac clock/reset GPIO support remain pending.
The same driver passes QEMU link loss/recovery and ring-wrap traffic tests;
native hardware has not yet been validated.

`tone` plays one second of stereo PCM through a USB Audio Class 1 output.
The initial profile is fixed 48000 Hz, signed 16-bit little-endian stereo,
with a synchronous full-speed 192-byte endpoint. `/dev/audio` accepts
write-only or read/write opens and PCM writes of 192..192000 bytes, in
192-byte multiples. Writes are synchronous and bounded to two seconds;
OHCI continues polling HID during playback. The kernel validates the whole
user buffer before copying it into a retained DMA allocation, schedules
isochronous TDs, checks every packet completion and stops the list before
buffer reuse. This is bounded PCM playback, not yet asynchronous mixing or
capture. Other rates, adaptive/asynchronous endpoints and UAC2 are pending.

The runner attaches QEMU USB audio directly to port 3. Tests record two
tones to WAV, require exactly 96000 stereo frames, and verify channel order,
sample byte order, amplitude and distinct 1000/500 Hz timing. A command typed
over USB during playback must also reach the shell. The test removes the
QEMU sound device before quitting so the WAV backend finalizes its header.
Interactive runs use CoreAudio by default; `VINIX_PPC_AUDIO` selects another
QEMU backend. This driver targets USB speakers/adapters; the iMac's built-in
I2S/DBDMA and TAS300x speaker codec remain separate, unimplemented work.

The separate direct test uses `-kernel vinix-of.bin`. QEMU's
`-kernel` ELF loader relocates PowerMac load addresses by 16 MiB, so this path
deliberately uses a flat binary linked at 0x01000000. The separate ELF output
has its ordinary physical/virtual addresses for loading from real firmware.
Add `-S -s` to stop at reset and attach a PowerPC-capable GDB on port 1234.

## Kernel loader boundary

`/chosen/bootargs` supplies an absolute Open Firmware kernel path and an
optional second path for the initramfs, separated by a space. An empty value
runs only firmware discovery. The CD test passes `cd:\PROBE.ELF;1` through
the firmware's `boot-file` option. This is a diagnostic ELF, not Vinix's
main kernel. It is built from `tests/powerpc/handoff/`.

The loader accepts static ELF32 MSB PowerPC ET_EXEC files below 16 MiB,
with at most 16 nonoverlapping load segments and matching virtual/physical
addresses. It rejects dynamic linking, TLS, malformed tables, overflowed
ranges and entries outside file-backed executable instructions. It checks
the complete image before claiming destination memory, loads segments,
zeros BSS and publishes instructions to the G4 caches. Source memory and
file handles are released if the image returns or loading fails.

The initial handoff ABI is PPC32 SysV: `r3` points to `powerpc.boot.Info`,
`r4` is the firmware client pointer, and `r1` uses a claimed 64 KiB stack
aligned to 16 bytes. Firmware is still active. The available-memory snapshot
is refreshed after claims and excludes the loader, copied FDT, source image,
kernel, initramfs and stack. Boot-info version 5 includes the retained
initramfs range and a bounded inventory of UniNorth PCI devices. The `Info`
map is authoritative; the copied firmware tree's
earlier `available` property is not an allocator input. Kernels must retain
firmware reservations until they can replace firmware mappings and services.
The loader checks identity translations for every page of the executable,
stack, copied tree and loader; nonidentity mappings currently fail safely.

The probe checks initialized data, zeroed/writable BSS, stack alignment/range,
boot-info version/size, FDT magic and kernel/stack exclusion from free memory.
It returns to the loader for an explicit PASS marker.

The independent PPC kernel entry in `kernel/powerpc/start` now takes control
without returning to firmware. `test-kernel` boots `KERNEL.ELF` and verifies
its own polled SCC console, physical-page allocator, low exception vectors,
complete integer register frame save/restore and decrementer interrupts.
The supervisor runs in real mode; userspace runs with relocation and the
problem-state bit set. A 64 KiB hashed page table maps read-only executable
text in segment 4 and non-executable writable data/stack in segment 5.
Inherited firmware BATs are disabled. The boot check executes `sc` from user
mode and verifies faults for kernel reads, privileged instructions, text
writes and stack execution before returning to the kernel. Real G4 TLB
invalidation uses 64 `tlbie` operations, not QEMU's accepted-but-unsupported
`tlbia` ([MPC7450 reference manual](https://www.nxp.com/docs/en/reference-manual/MPC7450UM.pdf), section 2.4.6).
After the protection check, the kernel revokes the fixture mappings and
releases its frames. With an initramfs, it validates the read-only USTAR
archive, maps `/bin/init` as a separate ELF32 process, and enters it in user
mode. The shell implements `help`, `ls`, `cat`, `pwd`, `ps`, `uname`, `mem`,
`echo`, `net`, `ping`, `tone` and `exit`. File contents and directory entries come from the archive;
memory accounting comes from the physical allocator.

The syscall subset uses PPC32 Linux numbers, argument registers and CR0.SO
error signalling. User buffers are checked page by page before access.
Console reads currently return EAGAIN when empty, and the shell polls; this
is not a complete Linux ABI. Boot checks exercise invalid pointers, writes
to text, unknown syscalls, descriptor exhaustion/reuse and page-spanning
file reads. There is one process, with static musl, initial TLS and FPU state,
bounded writable ext2 and framebuffer mappings. `fork`/`exec`, scheduling,
pipes, signals, Unix/TCP sockets and per-thread floating-point/vector state
remain pending. Desktop icons do not imply those separate applications run.

## Milestones

1. **Working:** V cross-build, ELF32 MSB link, Open Firmware entry and automated
   QEMU boot check. No dependency on the amd64/arm64 kernel build products.
2. **Working in QEMU:** available-memory map with loader exclusions, copied
   device tree, optional framebuffer metadata, checked ELF32 loading and
   stack/boot-info handoff and initramfs loading. Pending: support for
   nonidentity firmware mappings. The ISO-to-ELF firmware
   boot path works in QEMU; Apple's firmware and physical CD boot are untested.
3. **Working in QEMU:** kernel `powerpc.cpu` primitives for PVR/MSR, coherent
   64-bit timebase reads, 32-bit CAS and G4 instruction-cache publication.
   The guest checks successful/failed CAS, clock progress, and executing code
   after cache synchronization. Kernel exception entry and decrementer
   interrupts and initial hashed user mappings now pass. Pending: interrupt controller,
   64-bit atomic policy and scheduler integration.
4. **Working in QEMU:** static userspace ELF32 execution, initial PPC32 syscall
   subset, read-only boot filesystem and writable ext2. Static musl, initial
   TLS, heap/mmap and single-process FPU operation pass. Pending: common kernel
   pointer-width/endian audit, scheduling, full syscall ABI, signals and
   per-thread floating-point/vector state.
5. **Working in QEMU:** freestanding V init/shell with serial input and file
   commands, real desktop registration, account persistence and compositor.
   Pending: separate application processes and shared Vinix userland services.
   The initial shell also boots with 128 MiB guest RAM;
   that does not establish a memory budget for the eventual desktop.
6. **Working in QEMU:** inherited 15/32-bit framebuffer console and OHCI USB
   keyboard/mouse, GEM Ethernet DMA, DHCP/ARP/ICMP and USB PCM output. Pending:
   full desktop, USB hotplug/EHCI, TCP/IP sockets, built-in iMac audio,
   real-machine ATA/DBDMA, PMU and
   hardware boot tests. Identify the
   exact iMac revision before selecting its built-in audio codec.

The existing ARM64 iBoot adapter is unrelated to PowerPC Open Firmware.
Neither current Vinix ISO nor Alpine ppc64le packages run on a G4. A real
hardware boot and a full-kernel/desktop boot must be reported separately from
the firmware smoke test.

References: [QEMU PowerMac](https://www.qemu.org/docs/master/system/ppc/powermac.html),
[QEMU direct loader](https://github.com/qemu/qemu/blob/master/hw/ppc/mac_newworld.c),
[OpenBIOS preloaded kernel handoff](https://github.com/openbios/openbios/blob/master/arch/ppc/qemu/main.c).
