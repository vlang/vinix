#!/bin/sh

set -ex

# Build the sysroot with jinx and build limine.
./jinx sysroot
./jinx host-build limine

# Ensure permissions are set.
sudo chown -R root:root sysroot/*
sudo chown -R 1000:1000 sysroot/home/user
sudo chmod 700 sysroot/root
sudo chmod 777 sysroot/tmp

# Make an initramfs with the sysroot.
(cd sysroot && tar cf ../initramfs.tar *)

# Prepare the iso and boot directories.
sudo rm -rf iso_root
sudo mkdir -pv iso_root/boot
sudo cp -r sysroot/boot/vinix.elf iso_root/boot/
sudo cp -r initramfs.tar iso_root/boot/
sudo cp -r build-support/limine.cfg build-support/background.bmp iso_root/boot/

# Install the limine binaries.
sudo cp -r host-pkgs/limine/usr/local/share/limine/limine.sys        iso_root/boot/
sudo cp -r host-pkgs/limine/usr/local/share/limine/limine-cd.bin     iso_root/boot/
sudo cp -r host-pkgs/limine/usr/local/share/limine/limine-cd-efi.bin iso_root/boot/

# Create the disk image.
sudo xorriso -as mkisofs -b boot/limine-cd.bin -no-emul-boot -boot-load-size 4 \
-boot-info-table --efi-boot boot/limine-cd-efi.bin -efi-boot-part         \
--efi-boot-image --protective-msdos-label iso_root -o vinix.iso

# Install limine.
host-pkgs/limine/usr/local/bin/limine-deploy vinix.iso
