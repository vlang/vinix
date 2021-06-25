SHELL = /bin/bash

KERNEL_HDD = vinix.hdd

.PHONY: all
all: vinix.iso

QEMUFLAGS = -M q35,smm=off -m 2G -smp 4 -no-reboot -no-shutdown -cdrom vinix.iso -serial stdio

.PHONY: run-kvm
run-kvm: vinix.iso
	qemu-system-x86_64 -enable-kvm -cpu host $(QEMUFLAGS)

.PHONY: run-hvf
run-hvf: vinix.iso
	qemu-system-x86_64 -accel hvf -cpu host $(QEMUFLAGS)

.PHONY: run
run: vinix.iso
	qemu-system-x86_64 -cpu qemu64,level=11,+rdtscp,+sep $(QEMUFLAGS)

.PHONY: distro
distro:
	mkdir -p build 3rdparty
	$(MAKE) 3rdparty/v
	$(MAKE) 3rdparty/vc
	cd build && xbstrap init .. && xbstrap install --all

3rdparty/limine:
	mkdir -p 3rdparty
	git clone https://github.com/limine-bootloader/limine.git --branch=v2.0-branch-binary --depth=1 3rdparty/limine
	$(MAKE) -C 3rdparty/limine

V_COMMIT  = e797547d6d313380c00f1ea46d1c989b672f65e4
VC_COMMIT = db52ea7ffbad0db52866f1e90abdf231d8039c7c

3rdparty/v:
	git clone https://github.com/vlang/v.git 3rdparty/v
	cd 3rdparty/v && git checkout $(V_COMMIT)

3rdparty/vc:
	git clone https://github.com/vlang/vc.git 3rdparty/vc
	cd 3rdparty/vc && git checkout $(VC_COMMIT)

.PHONY: update-v
update-v:
	cd 3rdparty/v && [ `git rev-parse HEAD` = $(V_COMMIT) ] || ( \
		git checkout master && \
		git pull && \
		git checkout $(V_COMMIT) \
	)
	cd 3rdparty/vc && [ `git rev-parse HEAD` = $(VC_COMMIT) ] || ( \
		git checkout master && \
		git pull && \
		git checkout $(VC_COMMIT) && \
		cd ../../build && \
		xbstrap install-tool --reconfigure host-v \
	)

.PHONY: kernel/vinix.elf
kernel/vinix.elf: update-v
	cd build && xbstrap install --rebuild kernel

vinix.iso: 3rdparty/limine kernel/vinix.elf
	( cd build/system-root && tar -zcf ../../initramfs.tar.gz * )
	rm -rf pack
	mkdir -p pack/boot
	cp initramfs.tar.gz kernel/vinix.elf v-logo.bmp pack/
	cp limine.cfg 3rdparty/limine/limine.sys 3rdparty/limine/limine-cd.bin 3rdparty/limine/limine-eltorito-efi.bin pack/boot/
	xorriso -as mkisofs -b /boot/limine-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table --efi-boot /boot/limine-eltorito-efi.bin -efi-boot-part --efi-boot-image --protective-msdos-label pack -o vinix.iso
	./3rdparty/limine/limine-install vinix.iso

.PHONY: format
format: 3rdparty/v
	./3rdparty/v/v fmt -w kernel || true

.PHONY: clean
clean:
	rm -f vinix.iso
	$(MAKE) -C kernel clean

.PHONY: distclean
distclean: clean
	rm -rf 3rdparty build initramfs.tar.gz pack kernel/*.xbstrap
