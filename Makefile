export PATH := $(PATH):/usr/sbin
unexport CC
unexport CXX
unexport CFLAGS
unexport CXXFLAGS
unexport LDFLAGS
unexport MAKEFLAGS

.PHONY: all
all: vinix.iso

QEMUFLAGS = -M q35,smm=off -m 2G -smp 4 -cdrom vinix.iso -serial stdio

.PHONY: run-kvm
run-kvm: vinix.iso
	qemu-system-x86_64 -enable-kvm -cpu host $(QEMUFLAGS)

.PHONY: run-hvf
run-hvf: vinix.iso
	qemu-system-x86_64 -accel hvf -cpu host $(QEMUFLAGS)

.PHONY: run
run: vinix.iso
	qemu-system-x86_64 -cpu qemu64,level=11,+rdtscp $(QEMUFLAGS)

.PHONY: distro
distro:
	mkdir -p build 3rdparty
	cd build && [ -f bootstrap.link ] || xbstrap init ..
	cd build && xbstrap install -u --all

.PHONY: kernel
kernel:
	cd build && xbstrap install --rebuild kernel

.PHONY: init
init:
	cd build && xbstrap install --rebuild init

vinix.iso: kernel init
	cd build && xbstrap run make-iso
	mv build/vinix.iso ./

.PHONY: clean
clean:
	rm -f vinix.iso
	$(MAKE) -C kernel clean
	rm -f init/init

.PHONY: distclean
distclean: clean
	rm -rf 3rdparty build initramfs.tar.gz pack kernel/*.xbstrap init/*.xbstrap
