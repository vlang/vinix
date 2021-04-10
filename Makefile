KERNEL_HDD = disk.hdd

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
	make -C 3rdparty/limine

3rdparty/echfs:
	mkdir -p 3rdparty
	git clone https://github.com/echfs/echfs.git --depth=1 3rdparty/echfs
	make -C 3rdparty/echfs

3rdparty/v:
	mkdir -p 3rdparty
	git clone https://github.com/vlang/v.git 3rdparty/v
	cd 3rdparty/v && git checkout bf6a2f80ef4d44384c4af7185f8168973e5bfbf2
	make -C 3rdparty/v

.PHONY: kernel/vos.elf
kernel/vos.elf: 3rdparty/v
	$(MAKE) -C kernel V="`realpath ./3rdparty/v/v`" CC="`realpath ./build/tools/host-gcc/bin/x86_64-vos-gcc`"

$(KERNEL_HDD): 3rdparty/limine 3rdparty/echfs kernel/vos.elf
	rm -f $(KERNEL_HDD)
	dd if=/dev/zero bs=1M count=0 seek=64 of=$(KERNEL_HDD)
	parted -s $(KERNEL_HDD) mklabel gpt
	parted -s $(KERNEL_HDD) mkpart primary 2048s 100%
	./3rdparty/echfs/echfs-utils -g -p0 $(KERNEL_HDD) quick-format 512
	./3rdparty/echfs/echfs-utils -g -p0 $(KERNEL_HDD) import kernel/vos.elf vos.elf
	./3rdparty/echfs/echfs-utils -g -p0 $(KERNEL_HDD) import v-logo.bmp v-logo.bmp
	./3rdparty/echfs/echfs-utils -g -p0 $(KERNEL_HDD) import limine.cfg limine.cfg
	./3rdparty/echfs/echfs-utils -g -p0 $(KERNEL_HDD) import 3rdparty/limine/limine.sys limine.sys
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
