# Vinix Installer for Apple M1

This is a native macOS app written in V with ui2. It discovers the internal
startup disk and m1n1-bootable external USB disks, asks for an allocation, and
drives the supported Asahi installation machinery with a Vinix boot payload.

The installer is intentionally limited to the original Apple M1, which is the
Apple Silicon generation currently supported by Vinix. It refuses M1 Pro/Max,
M2, M3, M4, M5, Intel, virtual disks, and unsupported external-disk topologies.

## Build

Build the ARM64 desktop image and Limine first:

```sh
git clone https://github.com/vlang/ui2 third_party/ui2
./build-limine-aarch64.sh
./build-desktop-aarch64.sh --compact-initramfs
make macos-installer
open "build/vinix-installer/Vinix Installer.app"
```

The normal build copies the loader, kernel, Limine configuration, and desktop
initramfs into the app, so the result can be moved to another M1 Mac. Use
`./build-macos-installer.sh --thin` for a small developer build that refers to
the current checkout instead. A previously packaged payload can be supplied
without rebuilding the desktop:

```sh
VINIX_INSTALLER_PAYLOAD_DIR=/path/to/payload ./build-macos-installer.sh
```

That directory must contain `BOOTAA64.EFI`, `limine.conf`, `vinix`, and
`initramfs.tar`. The GitHub Actions release job uses this interface to rebuild
the native app while preserving the last published boot payload.

Every installer-source change on GitHub builds on an Apple Silicon runner.
Commits to `master` replace `Vinix-Installer-M1.dmg` and its checksum on the
rolling `m1-installer-latest` release. The permanent download URL is:

<https://github.com/vlang/vinix/releases/download/m1-installer-latest/Vinix-Installer-M1.dmg>

The app is ad-hoc signed for local development. Public distribution still
requires signing with a Developer ID certificate and Apple notarization.

## What changes on disk

An internal install shrinks only the APFS container that contains the booted
macOS. Asahi's current safety calculation must still leave at least 38 GB of
usable macOS space, and any APFS or snapshot constraint stops the install before
partitioning. An external install erases that entire selected disk; the native
confirmation names it explicitly.

The selected allocation contains a 2.5 GB stub macOS installation and a paired,
expandable FAT32 EFI system partition. The ESP receives m1n1 stage 2, U-Boot,
device trees, extracted Apple firmware, Limine, and Vinix. The desktop still
runs from its initramfs; the extra ESP capacity keeps the user-selected
allocation reserved for Vinix without claiming that the experimental ANS
writable-root path is production ready.

Disk mutation and boot-policy authentication are performed by the upstream
[Asahi installer](https://github.com/AsahiLinux/asahi-installer). The wrapper
pins and SHA-256-verifies installer v0.9.1 and the 2026-09-05 UEFI-only m1n1
package before running either. Administrator and Apple machine-owner passwords
are read by the upstream terminal UI and are never passed through the V app.

## First boot

The normal macOS flow must end in a full shutdown, not a warm restart. The
terminal prints these instructions before asking to shut down:

1. Wait at least 25 seconds after the Mac turns off.
2. Press and hold the power button until startup options appear.
3. Select **Vinix**.
4. Complete Apple's one-time **Finish Installation** recovery screen.

If the install is run from the paired recovery environment and can finish in
one stage, it offers a restart and still prints the startup-options instruction.

## Verification

```sh
V=/path/to/v ./installer/macos/test.sh
./build-macos-installer.sh --thin
```
