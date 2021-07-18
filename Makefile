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
	cd build && [ -f bootstrap.link ] || ( ln -s ../sysroot system-root && xbstrap init .. )
	cd build && xbstrap install -u --all

.PHONY: kernel/vinix.elf
kernel/vinix.elf: distro
	cd build && xbstrap install --rebuild kernel

vinix.iso: kernel/vinix.elf
	( cd sysroot && tar -zcf ../initramfs.tar.gz * )
	rm -rf pack
	mkdir -p pack/boot
	cp initramfs.tar.gz kernel/vinix.elf v-logo.bmp pack/
	cp limine.cfg ./build/tools/host-limine/share/limine/limine.sys ./build/tools/host-limine/share/limine/limine-cd.bin ./build/tools/host-limine/share/limine/limine-eltorito-efi.bin pack/boot/
	xorriso -as mkisofs -b /boot/limine-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table --efi-boot /boot/limine-eltorito-efi.bin -efi-boot-part --efi-boot-image --protective-msdos-label pack -o vinix.iso
	./build/tools/host-limine/bin/limine-install vinix.iso

.PHONY: clean
clean:
	rm -f vinix.iso
	$(MAKE) -C kernel clean

.PHONY: distclean
distclean: clean
	rm -rf 3rdparty build initramfs.tar.gz pack kernel/*.xbstrap
	rm -rf sysroot/boot/vinix.elf sysroot/usr sysroot/etc/xbstrap
