KERNEL_HDD = disk.hdd

.PHONY: clean all run 3rdparty/limine 3rdparty/echfs

all: $(KERNEL_HDD)

run: $(KERNEL_HDD)
	qemu-system-x86_64 -m 2G -hda $(KERNEL_HDD) -debugcon stdio

3rdparty: 3rdparty/echfs 3rdparty/limine

3rdparty/limine:
	test -f 3rdparty/limine/Makefile || (echo 'Run git submodule update --init to fetch the dependencies' && exit 1)
	make -C 3rdparty/limine

3rdparty/echfs:
	test -f 3rdparty/echfs/Makefile || (echo 'Run git submodule update --init to fetch the dependencies' && exit 1)
	make -C 3rdparty/echfs

kernel/vos.elf:
	$(MAKE) -C kernel

$(KERNEL_HDD): 3rdparty kernel/vos.elf
	rm -f $(KERNEL_HDD)
	dd if=/dev/zero bs=1M count=0 seek=64 of=$(KERNEL_HDD)
	parted -s $(KERNEL_HDD) mklabel gpt
	parted -s $(KERNEL_HDD) mkpart primary 2048s 100%
	./3rdparty/echfs/echfs-utils -g -p0 $(KERNEL_HDD) quick-format 512
	./3rdparty/echfs/echfs-utils -g -p0 $(KERNEL_HDD) import kernel/vos.elf vos.elf
	./3rdparty/echfs/echfs-utils -g -p0 $(KERNEL_HDD) import limine.cfg limine.cfg
	./3rdparty/echfs/echfs-utils -g -p0 $(KERNEL_HDD) import 3rdparty/limine/limine.sys limine.sys
	./3rdparty/limine/limine-install $(KERNEL_HDD)

clean:
	rm -f $(KERNEL_HDD)
	$(MAKE) -C kernel clean

distclean: clean
	rm -rf 3rdparty/limine 3rdparty/echfs
