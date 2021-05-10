SHELL = /bin/bash

KERNEL_HDD = vinix.hdd

V_COMMIT = 4728d102d94e483a4dda951eb104200c9282bd89

.PHONY: all
all: vinix.iso

QEMUFLAGS = -M q35 -m 2G -smp 4 -d int -no-reboot -no-shutdown -cdrom vinix.iso -debugcon stdio

.PHONY: run-kvm
run-kvm: vinix.iso
	qemu-system-x86_64 -enable-kvm -cpu host $(QEMUFLAGS)

.PHONY: run-hvf
run-hvf: vinix.iso
	qemu-system-x86_64 -accel hvf -cpu host $(QEMUFLAGS)

.PHONY: run
run: vinix.iso
	qemu-system-x86_64 $(QEMUFLAGS)

.PHONY: distro
distro:
	mkdir -p build
	export LC_ALL=C && cd build && xbstrap init .. && xbstrap install --all

3rdparty/limine:
	mkdir -p 3rdparty
	git clone https://github.com/limine-bootloader/limine.git --branch=v2.0-branch-binary --depth=1 3rdparty/limine
	$(MAKE) -C 3rdparty/limine

3rdparty/v:
	mkdir -p 3rdparty
	git clone https://github.com/vlang/v.git 3rdparty/v
	cd 3rdparty/v && git checkout $(V_COMMIT)
	$(MAKE) -C 3rdparty/v

.PHONY: update-v
update-v: 3rdparty/v
	cd 3rdparty/v && ( git checkout $(V_COMMIT) || ( git checkout master && git pull && git checkout $(V_COMMIT) && $(MAKE) ) )

.PHONY: kernel/vinix.elf
kernel/vinix.elf: update-v
	$(MAKE) -C kernel V="`realpath ./3rdparty/v/v`" \
		CC="`realpath ./build/tools/host-gcc/bin/x86_64-vinix-gcc`" \
		OBJDUMP="`realpath ./build/tools/host-binutils/bin/x86_64-vinix-objdump`"

vinix.iso: 3rdparty/limine kernel/vinix.elf
	( cd build/system-root && tar -zcf ../../initramfs.tar.gz * )
	rm -rf pack
	mkdir -p pack/boot
	cp initramfs.tar.gz kernel/vinix.elf v-logo.bmp pack/
	cp limine.cfg 3rdparty/limine/limine.sys 3rdparty/limine/limine-cd.bin 3rdparty/limine/limine-eltorito-efi.bin pack/boot/
	xorriso -as mkisofs -b /boot/limine-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table -part_like_isohybrid -eltorito-alt-boot -e /boot/limine-eltorito-efi.bin -no-emul-boot pack -isohybrid-gpt-basdat -o vinix.iso
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
	rm -rf 3rdparty build ports initramfs.tar.gz pack
