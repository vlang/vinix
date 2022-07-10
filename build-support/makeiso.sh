#!/bin/sh

set -ex

# Build the sysroot with jinx and build limine.
./jinx sysroot
./jinx host-build limine

# Make an initramfs with the sysroot.
(cd sysroot && tar cf ../initramfs.tar *)

# Prepare the iso and boot directories.
rm -rf iso_root
mkdir -pv iso_root/boot
cp -r sysroot/boot/vinix.elf iso_root/boot/
cp -r initramfs.tar iso_root/boot/
cp -r build-support/limine.cfg build-support/background.bmp iso_root/boot/

# Install the limine binaries.
cp -r host-pkgs/limine/usr/local/share/limine/limine.sys        iso_root/boot/
cp -r host-pkgs/limine/usr/local/share/limine/limine-cd.bin     iso_root/boot/
cp -r host-pkgs/limine/usr/local/share/limine/limine-cd-efi.bin iso_root/boot/

# Create the disk image.
xorriso -as mkisofs -b boot/limine-cd.bin -no-emul-boot -boot-load-size 4 \
-boot-info-table --efi-boot boot/limine-cd-efi.bin -efi-boot-part         \
--efi-boot-image --protective-msdos-label iso_root -o vinix.iso

# Install limine.
host-pkgs/limine/usr/local/bin/limine-deploy vinix.iso
