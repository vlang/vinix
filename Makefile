KERNEL_HDD = disk.hdd

.PHONY: clean all run

all: $(KERNEL_HDD)

run: $(KERNEL_HDD)
	qemu-system-x86_64 -m 2G -hda $(KERNEL_HDD) -debugcon stdio

limine:
	git clone https://github.com/limine-bootloader/limine.git --branch=latest-binary --depth=1
	make -C limine

kernel/vos.elf:
	$(MAKE) -C kernel

$(KERNEL_HDD): limine kernel/vos.elf
	rm -f $(KERNEL_HDD)
	dd if=/dev/zero bs=1M count=0 seek=64 of=$(KERNEL_HDD)
	parted -s $(KERNEL_HDD) mklabel gpt
	parted -s $(KERNEL_HDD) mkpart primary 2048s 100%
	echfs-utils -g -p0 $(KERNEL_HDD) quick-format 512
	echfs-utils -g -p0 $(KERNEL_HDD) import kernel/vos.elf vos.elf
	echfs-utils -g -p0 $(KERNEL_HDD) import limine.cfg limine.cfg
	echfs-utils -g -p0 $(KERNEL_HDD) import limine/limine.sys limine.sys
	./limine/limine-install $(KERNEL_HDD)

format:
	v fmt -w . || true

clean:
	rm -f $(KERNEL_HDD)
	$(MAKE) -C kernel clean

distclean: clean
	rm -rf limine
