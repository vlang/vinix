# GNUmakefile: Main makefile of the project.
# Code is governed by the GPL-2.0 license.
# Copyright (C) 2021-2022 The Vinix authors.

QEMUFLAGS ?= -M q35,smm=off -m 8G -cdrom vinix.iso -serial stdio

.PHONY: all
all: vinix.iso

vinix.iso: base
	./jinx rebuild base-files kernel init util-vinix
	./build-support/makeiso.sh

.PHONY: full
full:
	./jinx build-all

.PHONY: base
base:
	./jinx build bash coreutils

.PHONY: run-kvm
run-kvm: vinix.iso
	qemu-system-x86_64 -enable-kvm -cpu host $(QEMUFLAGS) -smp 1

.PHONY: run-hvf
run-hvf: vinix.iso
	qemu-system-x86_64 -accel hvf -cpu host $(QEMUFLAGS) -smp 4

ovmf:
	mkdir -p ovmf
	cd ovmf && curl -o OVMF-X64.zip https://efi.akeo.ie/OVMF/OVMF-X64.zip && 7z x OVMF-X64.zip

.PHONY: run-uefi
run-uefi: ovmf
	qemu-system-x86_64 -enable-kvm -cpu host $(QEMUFLAGS) -smp 4 -bios ovmf/OVMF.fd

.PHONY: run
run: vinix.iso
	qemu-system-x86_64 $(QEMUFLAGS) -no-shutdown -no-reboot -d int -smp 1

.PHONY: clean
clean:
	rm -rf iso_root sysroot vinix.iso initramfs.tar
	cd kernel     && make clean
	cd util-vinix && make clean

.PHONY: distclean
distclean: clean
	./jinx clean
