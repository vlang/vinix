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
	cd build && xbstrap init ..
	$(MAKE) update-v
	cd build && xbstrap install --all

3rdparty/limine:
	mkdir -p 3rdparty
	git clone https://github.com/limine-bootloader/limine.git --branch=v2.0-branch-binary --depth=1 3rdparty/limine
	$(MAKE) -C 3rdparty/limine

V_COMMIT  = 6a6425952747cc5716531a9fa0320afca95a6950
VC_COMMIT = 85bd19fb014c21e008e947b294c0354b534b4948

.PHONY: update-v
update-v:
	mkdir -p 3rdparty/v-archives
	[ -f 3rdparty/v-archives/$(V_COMMIT).tar.gz ] || ( \
		cd 3rdparty/v-archives && \
		wget https://github.com/vlang/v/archive/$(V_COMMIT).tar.gz && \
		rm -rf v v-$(V_COMMIT) && \
		tar -xf $(V_COMMIT).tar.gz && \
		mv v-$(V_COMMIT) v && \
		tar -zcf ../v.tar.gz v \
	)
	[ -f 3rdparty/v-archives/$(VC_COMMIT).tar.gz ] || ( \
		cd 3rdparty/v-archives && \
		wget https://github.com/vlang/vc/archive/$(VC_COMMIT).tar.gz && \
		rm -rf vc vc-$(VC_COMMIT) && \
		tar -xf $(VC_COMMIT).tar.gz && \
		mv vc-$(VC_COMMIT) vc && \
		tar -zcf ../vc.tar.gz vc && \
		cd ../.. && ./rebuild-pkg.sh v host-v --tool \
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
