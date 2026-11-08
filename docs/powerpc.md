# PowerPC G4 port

Target: 32-bit big-endian PowerPC, initially the 7450 CPU and Open Firmware
on a NewWorld Macintosh. QEMU `mac99,via=pmu` is the development machine.
The port boots a small native kernel and a protected userspace shell in
QEMU. It does not yet run the shared Vinix kernel or desktop.

## Build and test

The host needs V with `-arch ppc` support, Zig with its PowerPC LLVM backend,
and `qemu-system-ppc`. Apple Clang does not include that backend. All maintained
build and test tooling is V. Zig compiles V's generated C; no Zig application
source, hosted libc, or Python is used.

The CPU backend requires V commit `b7b4dd46ee` (raw PPC assembly support), or
a later compiler containing that change. It is installed in the sibling `../v`
checkout. An alternate compiler can be selected with `VINIX_V_COMPILER`.

```
v run tools/powerpc test /tmp/vinix-ppc-state
v run tools/powerpc test-media /tmp/vinix-ppc-cd-state
v run tools/powerpc test-kernel /tmp/vinix-ppc-kernel-state
v run tools/powerpc test-shell /tmp/vinix-ppc-shell-state
v run tools/powerpc run /tmp/vinix-ppc-state
```

Override executable locations with `VINIX_V_COMPILER`, `VINIX_PPC_ZIG` and
`VINIX_PPC_QEMU`. Set `VINIX_PPC_MEMORY` to the guest RAM in MiB (128..2048,
default 512). For the small-memory check:

```
VINIX_PPC_MEMORY=128 v run tools/powerpc test-shell /tmp/vinix-ppc-128
```

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
It has a 20-second boot deadline, kills/reaps its own emulator, and saves
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
qemu-system-ppc -M mac99,via=pmu -cpu 7450 -accel tcg -m 512 -smp 1 -nic none -cdrom /tmp/vinix-ppc-state/vinix-ppc-boot.iso -boot d -prom-env 'boot-device=cd:\BOOT.ELF;1' -prom-env 'boot-file=cd:\KERNEL.ELF;1 cd:\RAMFS.TAR;1' -nographic -serial mon:stdio
```

This command boots the PPC kernel and initial userspace shell. This ISO
has no partition map, so OpenBIOS takes the filename immediately after the
colon; adding a comma prevents lookup. Keep the ISO file version `;1`.
Input/output uses the emulated SCC serial port. Set `VINIX_PPC_GRAPHICS=1`
to enable the inherited 32-bit framebuffer, scrolling console and USB mouse
pointer. USB boot-protocol keyboard input works alongside serial input.
For a window with keyboard and mouse, use:

```
VINIX_PPC_GRAPHICS=1 v run tools/powerpc run /tmp/vinix-ppc-state
```

The same variable on `test-shell` verifies framebuffer RGB colors and text,
types a command through QEMU's USB keyboard, and checks mouse movement and
button press/release against screenshot pixels. OHCI uses little-endian
descriptors, explicit G4 DMA cache ownership and bounded polling. This first
driver supports directly attached boot-protocol HID devices present at boot;
USB hubs, reconnection, key repeat, storage and EHCI remain pending. It does
not call firmware for keyboard, mouse or console output after takeover.

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
`echo` and `exit`. File contents and directory entries come from the archive;
memory accounting comes from the physical allocator.

The syscall subset uses PPC32 Linux numbers, argument registers and CR0.SO
error signalling. User buffers are checked page by page before access.
Console reads currently return EAGAIN when empty, and the shell polls; this
is not a complete Linux ABI. Boot checks exercise invalid pointers, writes
to text, unknown syscalls, descriptor exhaustion/reuse and page-spanning
file reads. There is one process, no `fork`/`exec`, scheduler, writable
filesystem, pipes, signals, TLS, libc or floating-point/vector context.
Shared Vinix scheduler, filesystem and desktop integration remain pending.

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
   subset and read-only boot filesystem. Pending: common kernel pointer-width/
   endian audit, process scheduling and full syscall ABI, signals, TLS and
   floating-point/vector state.
5. **Working in QEMU:** freestanding V init/shell with serial input and file
   commands. Pending: PPC32 libc and ordinary applications, shared Vinix
   userland and desktop. The initial shell also boots with 128 MiB guest RAM;
   that does not establish a memory budget for the eventual desktop.
6. **Working in QEMU:** inherited 32-bit framebuffer console and OHCI USB
   keyboard/mouse. Pending: full desktop, USB hubs/hotplug/EHCI, GEM Ethernet,
   audio, real-machine ATA/DBDMA, PMU and hardware boot tests. Identify the
   exact iMac revision before selecting its built-in audio codec.

The existing ARM64 iBoot adapter is unrelated to PowerPC Open Firmware.
Neither current Vinix ISO nor Alpine ppc64le packages run on a G4. A real
hardware boot and a full-kernel/desktop boot must be reported separately from
the firmware smoke test.

References: [QEMU PowerMac](https://www.qemu.org/docs/master/system/ppc/powermac.html),
[QEMU direct loader](https://github.com/qemu/qemu/blob/master/hw/ppc/mac_newworld.c),
[OpenBIOS preloaded kernel handoff](https://github.com/openbios/openbios/blob/master/arch/ppc/qemu/main.c).
