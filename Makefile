SHELL = /bin/bash

KERNEL_HDD = vos.hdd

V_COMMIT = 1e856c0f94c648194d23e07fdd426a597e8ff2f5

.PHONY: all
all: $(KERNEL_HDD)

QEMUFLAGS = -M q35 -m 2G -smp 4 -d int -no-reboot -no-shutdown -drive file=$(KERNEL_HDD),format=raw,index=0,media=disk -debugcon stdio

.PHONY: run-kvm
run-kvm: $(KERNEL_HDD)
	qemu-system-x86_64 -enable-kvm -cpu host $(QEMUFLAGS)

.PHONY: run-hvf
run-hvf: $(KERNEL_HDD)
	qemu-system-x86_64 -accel hvf -cpu host $(QEMUFLAGS)

.PHONY: run
run: $(KERNEL_HDD)
	qemu-system-x86_64 $(QEMUFLAGS)

.PHONY: distro
distro:
	mkdir -p build
	export LC_ALL=C && cd build && xbstrap init .. && xbstrap install --all

3rdparty/dir2fat32-esp:
	wget https://github.com/mintsuki-org/dir2fat32-esp/raw/master/dir2fat32-esp -O 3rdparty/dir2fat32-esp
	chmod +x 3rdparty/dir2fat32-esp

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

$(KERNEL_HDD): 3rdparty/limine 3rdparty/dir2fat32-esp kernel/vos.elf
	( cd build/system-root && tar -zcf ../../initramfs.tar.gz * )
	rm -rf pack
	mkdir -p pack
	cp initramfs.tar.gz kernel/vos.elf v-logo.bmp limine.cfg 3rdparty/limine/limine.sys pack/
	mkdir -p pack/EFI/BOOT
	cp 3rdparty/limine/BOOTX64.EFI pack/EFI/BOOT/
	./3rdparty/dir2fat32-esp -f $(KERNEL_HDD) 64 pack
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
	rm -rf 3rdparty build ports initramfs.tar.gz pack
