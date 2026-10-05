# Booting Vinix straight from iBoot

Apple silicon Macs start a custom kernel ("fuOS") from any macOS install
whose boot policy allows it: iBoot loads a raw file, enters it at EL2 with
the MMU off, and passes its boot arguments, the Apple DeviceTree (ADT) and a
framebuffer. The loader here is that file. It turns iBoot's hand-off into
the Limine hand-off the kernel already expects, so the same kernel binary
boots in QEMU, on the M1 through m1n1 and U-Boot, and here with nothing in
between:

1. parse the boot arguments and validate the ADT;
2. disarm the watchdog iBoot leaves running (`/arm-io/wdt`, as m1n1 does);
3. load the kernel ELF appended to the loader;
4. convert the ADT to an FDT: Apple's names and little-endian values kept,
   `#address-cells`, `#size-cells`, `reg` and `ranges` re-encoded big-endian,
   `phandle` from `AAPL,phandle`, the root marked `vinix,apple-adt`, and
   `/chosen/bootargs` from the image's command line;
5. build the memory map: RAM is iBoot's `[phys_base, phys_base + mem_size)`
   minus the coprocessor firmware it already loaded (every `segment-ranges`),
   with the kernel and its initramfs kept and iBoot's own data reclaimable;
6. build page tables (HHDM at `0xffff000000000000`, the kernel at its link
   address) and answer the kernel's Limine requests;
7. quiet the FIQ sources m1n1 would (timers, PMU, fast IPI) and enter the
   kernel at EL2 the way Limine 12.8 does on a VHE CPU.

The kernel recognises the converted tree (`devicetree.is_apple_adt()`),
resolves addresses as XNU does -- translation stops at the first bus
without `ranges` -- and drives the interrupt controller from the ADT's
`aic,3` node.

## Build

```
make -C kernel CC=clang ARCH=aarch64 LIMINE_MP=1 V=~/code/v/v -j8
apple-boot/build.py                 # -> apple-boot/build/vinix-apple.bin
```

`build.py` takes `--kernel`, `--initramfs` (a ustar archive) and
`--cmdline`. Without `--initramfs` the image carries `report_init.c` as
PID 1, which prints what the kernel found and stays up: the first boots on a
new Mac have no keyboard to type at. It warns when the kernel binary is
older than its sources.

## Test

```
make -C apple-boot test
```

- `tests/check_converter.py` rebuilds this Mac's ADT from the IORegistry,
  converts it with the loader's own C code, reads it back as the kernel
  does, and checks every node's translated `reg` against the windows XNU
  mapped (on an M5 Max: 233 nodes, 0 differences).
- `tests/qemu_iboot.py` boots the image in QEMU through a stub that hands
  over as iBoot does (EL2 with E2H set, MMU off, boot arguments revision 2,
  a 30-bit framebuffer at the top of RAM) with a tree that has a watchdog
  behind a translating bus, a firmware segment and an AICv3 described with
  this M5 Max's properties. It passes when PID 1 prints its line, the
  watchdog registers were cleared, the segment is untouched and the kernel
  masked every AIC IRQ. `--screenshot out.png` saves the screen,
  `--kernel` picks the kernel, `--no-aic` takes QEMU's GIC path instead.
  `--real-adt` hands over this Mac's own tree (about 2,000 nodes, 726 KB on
  an M5 Max) with only the watchdog and AIC hidden, so the loader and the
  kernel get through all of it.

## Install on a Mac

This changes the boot policy of one macOS installation. The Mac's main
macOS stays as it is and keeps its Full Security; the startup picker (hold
the power button) chooses between them.

1. **A macOS install to replace.** Add an APFS volume (Disk Utility, or
   `diskutil apfs addVolume <container> APFS Vinix`, the container from
   `diskutil list internal`) and install the same macOS
   version into it (`softwareupdate --fetch-full-installer`, then the
   installer app, choosing that volume). Finish its setup and create an
   administrator: changing its policy asks for that user.
2. **Put the image where recoveryOS can read it**, e.g.
   `/Users/Shared/vinix-apple.bin` on the main macOS.
3. **Boot into One True Recovery**: shut down, hold the power button until
   "Loading startup options", choose Options, then Utilities > Terminal.
4. In that Terminal:

   ```
   diskutil apfs listVolumeGroups      # the Vinix install's volume group UUID
   diskutil apfs unlockVolume "Macintosh HD - Data"   # if FileVault is on
   bputil -nkcas -v <UUID>              # Permissive Security for that install only
   kmutil configure-boot -c "/Volumes/Macintosh HD - Data/Users/Shared/vinix-apple.bin" \
       --raw --entry-point 2048 --lowest-virtual-address 0 -v /Volumes/Vinix
   ```

5. Restart, holding the power button, and pick the Vinix volume.

A new image needs step 4's `kmutil configure-boot` again, from recoveryOS.
To undo it, run `bputil -f -v <UUID>` there, or delete the volume.

## Reading the screen

The loader draws on iBoot's framebuffer before the kernel takes it over. A
square appears along the top edge per stage -- green 0 boot arguments,
blue 1 ADT, yellow 2 watchdog, cyan 3 kernel loaded, magenta 4 FDT,
white 5 memory map, orange 6 page tables, grey 7 entering the kernel -- and
rows of hex values below them:

| label | value |
|-------|-------|
| `B0` | boot-argument revision, CurrentEL in the upper half |
| `D1` | the watchdog base it disarmed (0: none found) |
| `E0` | kernel entry point |
| `A0` | `phys_base` |
| `A1` | `mem_size`; the top byte counts reserved firmware ranges |
| `C0` | Limine requests answered |

A failure is a red band: the last stage, a code, and a value.

| code | meaning | value |
|------|---------|-------|
| `0001` | boot arguments unreadable | their address |
| `0101` | ADT malformed | its address |
| `0301` | no payload after the loader, or it overruns iBoot's data | payload address |
| `0302` | kernel ELF rejected | its size |
| `0401` | FDT conversion overflowed | bytes written |
| `0501`-`0504` | memory map: too many entries, no room for the late window, too many reserved ranges, no window clear of firmware | the address or size |
| `0A01` | out of memory | request size |
| `0B01`, `0B02` | page tables: a block in the way, a misaligned range | the entry or addresses |
| `0C01` | Limine response arena full | request size |
| `E0xx` | exception, vector `xx`; `E1` ESR, `E2` ELR, `E3` FAR in the rows | ESR |

## What runs on the M5

The kernel boots on one CPU (no Limine MP response, so the other cores stay
where iBoot left them), with the AICv3 up and the timer on FIQ, iBoot's
framebuffer as the console, and the initramfs as its root. There is no
keyboard or trackpad driver for the M5's MTP yet, no NVMe root, and the
GPU and display coprocessor are left alone (`vinix.apple_gpu` and
`vinix.apple_dcp` stay off).
