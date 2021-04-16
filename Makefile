SHELL = /bin/bash

KERNEL_HDD = disk.hdd

V_COMMIT = 60bc280ad0da43a88bc4c9cd4ec30e67c9eaae0f

.PHONY: all
all: $(KERNEL_HDD)

.PHONY: run
run: $(KERNEL_HDD)
	qemu-system-x86_64 -enable-kvm -cpu host -m 2G -drive file=$(KERNEL_HDD),format=raw,index=0,media=disk -debugcon stdio

.PHONY: run-nokvm
run-nokvm: $(KERNEL_HDD)
	qemu-system-x86_64 -m 2G -drive file=$(KERNEL_HDD),format=raw,index=0,media=disk -debugcon stdio

.PHONY: distro
distro:
	mkdir -p build
	cd build && xbstrap init .. && xbstrap install --all

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

.PHONY: kernel/vos.elf
kernel/vos.elf: update-v
	$(MAKE) -C kernel V="`realpath ./3rdparty/v/v`" \
		CC="`realpath ./build/tools/host-gcc/bin/x86_64-vos-gcc`" \
		OBJDUMP="`realpath ./build/tools/host-binutils/bin/x86_64-vos-objdump`"

$(KERNEL_HDD): 3rdparty/limine kernel/vos.elf
	rm -rf pack
	mkdir -p pack
	cp kernel/vos.elf v-logo.bmp limine.cfg 3rdparty/limine/limine.sys pack/
	mkdir -p pack/EFI/BOOT
	cp 3rdparty/limine/BOOTX64.EFI pack/EFI/BOOT/
	./dir2fat32.sh -f $(KERNEL_HDD) 64 pack
	./3rdparty/limine/limine-install $(KERNEL_HDD)

.PHONY: format
format: 3rdparty/v
	./3rdparty/v/v fmt -w kernel || true

.PHONY: clean
clean:
	rm -f $(KERNEL_HDD)
	$(MAKE) -C kernel clean

.PHONY: distclean
distclean: clean
	rm -rf 3rdparty build ports
