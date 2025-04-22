#!/bin/sh

set -ex

# Build the sysroot with jinx and build limine.
rm -rf sysroot
set -f
./jinx build-if-needed base $PKGS_TO_INSTALL
./jinx install "sysroot" base $PKGS_TO_INSTALL
set +f
if ! [ -d host-pkgs/limine ]; then
    ./jinx host-build limine
fi

# Make an initramfs with the sysroot.
( cd sysroot && tar cf ../initramfs.tar * )

# Prepare the iso and boot directories.
rm -rf iso_root
mkdir -pv iso_root/boot
cp sysroot/usr/share/vinix/vinix iso_root/boot/
cp initramfs.tar iso_root/boot/
cp build-support/limine.conf iso_root/boot/

# Install the limine binaries.
cp host-pkgs/limine/usr/local/share/limine/limine-bios.sys iso_root/boot/
cp host-pkgs/limine/usr/local/share/limine/limine-bios-cd.bin iso_root/boot/
cp host-pkgs/limine/usr/local/share/limine/limine-uefi-cd.bin iso_root/boot/
mkdir -pv iso_root/EFI/BOOT
cp host-pkgs/limine/usr/local/share/limine/BOOT*.EFI iso_root/EFI/BOOT/

# Create the disk image.
xorriso -as mkisofs -R -r -J -b boot/limine-bios-cd.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table -hfsplus \
    -apm-block-size 2048 --efi-boot boot/limine-uefi-cd.bin \
    -efi-boot-part --efi-boot-image --protective-msdos-label \
    iso_root -o vinix.iso

# Install limine.
host-pkgs/limine/usr/local/bin/limine bios-install vinix.iso
