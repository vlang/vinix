# GNUmakefile: Main makefile of the project.
# Code is governed by the GPL-2.0 license.
# Copyright (C) 2021-2022 The Vinix authors.

QEMUFLAGS ?= -M q35,smm=off -m 8G -cdrom vinix.iso -serial stdio -smp 4

.PHONY: all
all:
	rm -f vinix.iso
	$(MAKE) vinix.iso

vinix.iso: jinx
	rm -f builds/kernel.built builds/kernel.packaged
	$(MAKE) distro-base
	./build-support/makeiso.sh

.PHONY: debug
debug:
	JINX_CONFIG_FILE=jinx-config-debug $(MAKE) all

jinx:
	curl -Lo jinx https://github.com/mintsuki/jinx/raw/5f522c327be8245613f3e059de424209579237d1/jinx
	chmod +x jinx

.PHONY: distro-full
distro-full: jinx
	./jinx build-all

.PHONY: distro-base
distro-base: jinx
	./jinx build base-files kernel init bash binutils bzip2 coreutils diffutils findutils gawk gcc gmp grep gzip less make mpc mpfr nano ncurses pcre2 readline sed tar tzdata util-vinix xz-utils zlib zstd

.PHONY: run-kvm
run-kvm: vinix.iso
	qemu-system-x86_64 -enable-kvm -cpu host $(QEMUFLAGS)

.PHONY: run-hvf
run-hvf: vinix.iso
	qemu-system-x86_64 -accel hvf -cpu host $(QEMUFLAGS)

ovmf:
	mkdir -p ovmf
	cd ovmf && curl -o OVMF.fd https://retrage.github.io/edk2-nightly/bin/RELEASEX64_OVMF.fd

.PHONY: run-uefi
run-uefi: vinix.iso ovmf
	qemu-system-x86_64 -enable-kvm -cpu host $(QEMUFLAGS) -bios ovmf/OVMF.fd

.PHONY: run-bochs
run-bochs: vinix.iso
	bochs -f bochsrc

.PHONY: run-lingemu
run-lingemu: vinix.iso
	lingemu runvirt -m 8192 --diskcontroller type=ahci,name=ahcibus1 --disk vinix.iso,disktype=cdrom,controller=ahcibus1

.PHONY: run
run: vinix.iso
	qemu-system-x86_64 $(QEMUFLAGS)

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
distclean: jinx
	make -C kernel distclean
	./jinx clean
	rm -rf iso_root sysroot vinix.iso initramfs.tar jinx ovmf
	chmod -R 777 .jinx-cache
	rm -rf .jinx-cache
