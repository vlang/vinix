# PowerPC G4 port

Target: 32-bit big-endian PowerPC, initially the 7450 CPU and Open Firmware
on a NewWorld Macintosh. QEMU `mac99,via=pmu` is the development machine.
This is an architecture bring-up, not yet a bootable Vinix desktop.

## Build and test

The host needs V with `-arch ppc` support, Zig with its PowerPC LLVM backend,
and `qemu-system-ppc`. Apple Clang does not include that backend. All maintained
build and test tooling is V. Zig compiles V's generated C; no Zig application
source, hosted libc, or Python is used.

```
v run tools/powerpc test /tmp/vinix-ppc-state
v run tools/powerpc run /tmp/vinix-ppc-state
```

Override executable locations with `VINIX_V_COMPILER`, `VINIX_PPC_ZIG` and
`VINIX_PPC_QEMU`. The optional directory defaults to a worktree-specific path
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
Host corruption tests run with `v test tools/powerpc/validate_test.v`.

Direct QEMU command after building:

```
qemu-system-ppc -M mac99,via=pmu -cpu 7450 -accel tcg -m 512 -smp 1 -nic none -kernel /tmp/vinix-ppc-state/vinix-of.bin -serial stdio
```

This command boots the firmware bring-up program, not the whole OS. QEMU's
`-kernel` ELF loader relocates PowerMac load addresses by 16 MiB, so this path
deliberately uses a flat binary linked at 0x01000000. The separate ELF output
has its ordinary physical/virtual addresses for loading from real firmware.
Add `-S -s` to stop at reset and attach a PowerPC-capable GDB on port 1234.

## Milestones

1. **Working:** V cross-build, ELF32 MSB link, Open Firmware entry and automated
   QEMU boot check. No dependency on the amd64/arm64 kernel build products.
2. **Working in QEMU:** available-memory map with loader exclusions, copied
   device tree, optional framebuffer metadata. Pending: kernel/initramfs loading,
   bootable Open Firmware media, physical-address translation on real firmware.
3. Pending: CPU exceptions, cache/TLB operations, Book III-S 32-bit MMU,
   interrupt controller, timer, atomics and scheduler integration.
4. Pending: common kernel pointer-width/endian audit, ELF32 execution and
   PPC32 Linux syscall ABI, signals, TLS and floating-point/vector state.
5. Pending: PPC32 libc, init, shell and desktop userland; small-memory profile.
6. Pending: real-machine ATA/DBDMA, USB OHCI/EHCI, GEM Ethernet, framebuffer,
   PMU and hardware boot tests. Identify the exact iMac revision first.

The existing ARM64 iBoot adapter is unrelated to PowerPC Open Firmware.
Neither current Vinix ISO nor Alpine ppc64le packages run on a G4. A real
hardware boot and a full-kernel/desktop boot must be reported separately from
the firmware smoke test.

References: [QEMU PowerMac](https://www.qemu.org/docs/master/system/ppc/powermac.html),
[QEMU direct loader](https://github.com/qemu/qemu/blob/master/hw/ppc/mac_newworld.c),
[OpenBIOS preloaded kernel handoff](https://github.com/openbios/openbios/blob/master/arch/ppc/qemu/main.c).
