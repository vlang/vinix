# GNUmakefile: Main makefile of the project.
# Code is governed by the GPL-2.0 license.
# Copyright (C) 2021-2022 The Vinix authors.

QEMUFLAGS ?= -M q35,smm=off -m 8G -cdrom vinix.iso -serial stdio

.PHONY: all
all: jinx
	./jinx build base-files kernel init util-vinix
	./build-support/makeiso.sh

.PHONY: debug
debug:
	JINX_CONFIG_FILE=jinx-config-debug $(MAKE) all

jinx:
	curl -o jinx https://raw.githubusercontent.com/mintsuki/jinx/trunk/jinx
	chmod +x jinx

.PHONY: distro-full
distro-full: jinx
	./jinx build-all

.PHONY: distro-base
distro-base: jinx
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
run-bochs: vinix.iso
        bochs -f bochsrc
run-lingemu: vinix.iso 
        lingemu runvirt -m 8192 --diskcontroller type=ahci,name=ahcibus1 --disk vinix.iso,disktype=cdrom,controller=ahcibus1
.PHONY: run
run: vinix.iso
	qemu-system-x86_64 $(QEMUFLAGS) -no-shutdown -no-reboot -d int -smp 1

.PHONY: kernel-clean
kernel-clean:
	make -C kernel clean
	rm -rf builds/kernel* pkgs/kernel*

.PHONY: util-vinix-clean
util-vinix-clean:
	make -C util-vinix clean
	rm -rf builds/util-vinix* pkgs/util-vinix*

.PHONY: init-clean
init-clean:
	rm -rf init/init
	rm -rf builds/init* pkgs/init*

.PHONY: base-files-clean
base-files-clean:
	rm -rf builds/base-files* pkgs/base-files*

.PHONY: clean
clean: kernel-clean util-vinix-clean init-clean base-files-clean
	rm -rf iso_root sysroot vinix.iso initramfs.tar

.PHONY: distclean
distclean: clean jinx
	make -C kernel distclean
	./jinx clean
	rm jinx
