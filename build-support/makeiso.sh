#!/bin/sh

set -ex

# Build the sysroot with jinx and build limine.
rm -rf sysroot
./jinx sysroot
./jinx host-build limine

# Make an initramfs with the sysroot.
(cd sysroot && tar cvf ../initramfs.tar *)

# Prepare the iso and boot directories.
rm -rf iso_root
mkdir -pv iso_root/boot
cp -r sysroot/usr/vinix.elf iso_root/boot/
cp -r initramfs.tar iso_root/boot/
cp -r base-files/boot/* iso_root/boot/

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
