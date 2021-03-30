KERNEL_HDD = disk.hdd

.PHONY: clean all run

all: $(KERNEL_HDD)

run: $(KERNEL_HDD)
	qemu-system-x86_64 -m 2G -hda $(KERNEL_HDD) -debugcon stdio

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
	cd 3rdparty/v && git checkout 205fb88d9081cf9bdabe9f34b8bc947d7a8232b3
	make -C 3rdparty/v

kernel/vos.elf: 3rdparty/v
	$(MAKE) -C kernel V="`realpath ./3rdparty/v/v`"

$(KERNEL_HDD): 3rdparty/limine 3rdparty/echfs kernel/vos.elf
	rm -f $(KERNEL_HDD)
	dd if=/dev/zero bs=1M count=0 seek=64 of=$(KERNEL_HDD)
	parted -s $(KERNEL_HDD) mklabel gpt
	parted -s $(KERNEL_HDD) mkpart primary 2048s 100%
	./3rdparty/echfs/echfs-utils -g -p0 $(KERNEL_HDD) quick-format 512
	./3rdparty/echfs/echfs-utils -g -p0 $(KERNEL_HDD) import kernel/vos.elf vos.elf
	./3rdparty/echfs/echfs-utils -g -p0 $(KERNEL_HDD) import limine.cfg limine.cfg
	./3rdparty/echfs/echfs-utils -g -p0 $(KERNEL_HDD) import 3rdparty/limine/limine.sys limine.sys
	./3rdparty/limine/limine-install $(KERNEL_HDD)

format:
	v fmt -w . || true

clean:
	rm -f $(KERNEL_HDD)
	$(MAKE) -C kernel clean

distclean: clean
	rm -rf limine
