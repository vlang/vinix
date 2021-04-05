KERNEL_HDD = disk.hdd

.PHONY: clean all run
all: $(KERNEL_HDD)

run: $(KERNEL_HDD)
	qemu-system-x86_64 -m 2G -hda $(KERNEL_HDD) -debugcon stdio

%.v:
ALL_V_FILES = $(shell 3rdparty/v/v -print-v-files kernel/main.v)

3rdparty/limine:
	mkdir -p 3rdparty
	git clone https://github.com/limine-bootloader/limine.git --quiet --branch=v2.0-branch-binary --depth=1 3rdparty/limine
	make --quiet -C 3rdparty/limine 2> /dev/null

3rdparty/echfs:
	mkdir -p 3rdparty
	git clone https://github.com/echfs/echfs.git --quiet --depth=1 3rdparty/echfs
	make --quiet -C 3rdparty/echfs 2> /dev/null

3rdparty/v:
	mkdir -p 3rdparty
	git clone https://github.com/vlang/v.git --quiet --branch=weekly.2021.13 --depth=1 3rdparty/v
	make --quiet -C 3rdparty/v 2> /dev/null

kernel/vos.elf: 3rdparty/v $(ALL_V_FILES)
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

format: 3rdparty/v
	./3rdparty/v/v fmt -w kernel || true

clean:
	rm -f $(KERNEL_HDD)
	$(MAKE) -C kernel clean

distclean: clean
	rm -rf 3rdparty
