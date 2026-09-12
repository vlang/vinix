ARCHITECTURE ?= x86_64
QEMUFLAGS ?= -M q35,smm=off -m 8G -cdrom vinix.iso -serial stdio -smp 4 -vga std

.PHONY: all amd64-alpine aarch64-alpine aarch64-all
ifeq ($(ARCHITECTURE),aarch64)
all: aarch64-alpine
else
all: amd64-alpine
endif

# Alpine supplies the userland and guest toolchain as binaries. The kernel is
# built directly with the host compiler, so there is no mlibc, binutils, or
# cross-GCC bootstrap to run.
amd64-alpine:
	./build-amd64.sh

aarch64-alpine:
	./build-aarch64.sh

aarch64-all:
	./build-all-aarch64.sh

.PHONY: vinix.iso
vinix.iso: amd64-alpine

.PHONY: vinix-aarch64.iso
vinix-aarch64.iso: aarch64-alpine

.PHONY: debug
debug:
	@if [ "$(ARCHITECTURE)" = aarch64 ]; then \
		PROD=false ./build-aarch64.sh; \
	else \
		PROD=false ./build-amd64.sh; \
	fi

.PHONY: run-kvm
run-kvm: amd64-alpine
	VINIX_AMD64_ISO="$(CURDIR)/vinix.iso" VINIX_QEMU_ACCEL=kvm VINIX_QEMU_CPU=host ./run-amd64-alpine.sh --no-build --interactive

.PHONY: run-hvf
run-hvf: amd64-alpine
	VINIX_AMD64_ISO="$(CURDIR)/vinix.iso" VINIX_QEMU_ACCEL=hvf VINIX_QEMU_CPU=host ./run-amd64-alpine.sh --no-build --interactive

ovmf/ovmf-code-x86_64.fd:
	mkdir -p ovmf
	curl -Lo $@ https://github.com/osdev0/edk2-ovmf-nightly/releases/latest/download/ovmf-code-x86_64.fd

ovmf/ovmf-vars-x86_64.fd:
	mkdir -p ovmf
	curl -Lo $@ https://github.com/osdev0/edk2-ovmf-nightly/releases/latest/download/ovmf-vars-x86_64.fd

.PHONY: run-uefi
run-uefi: vinix.iso ovmf/ovmf-code-x86_64.fd ovmf/ovmf-vars-x86_64.fd
	qemu-system-x86_64 \
		-enable-kvm \
		-cpu host \
		-drive if=pflash,unit=0,format=raw,file=ovmf/ovmf-code-x86_64.fd,readonly=on \
		-drive if=pflash,unit=1,format=raw,file=ovmf/ovmf-vars-x86_64.fd \
		$(QEMUFLAGS)

.PHONY: run-bochs
run-bochs: amd64-alpine
	bochs -f bochsrc

.PHONY: run-lingemu
run-lingemu: amd64-alpine
	lingemu runvirt -m 8192 --diskcontroller type=ahci,name=ahcibus1 --disk vinix.iso,disktype=cdrom,controller=ahcibus1

.PHONY: run
run: amd64-alpine
	VINIX_AMD64_ISO="$(CURDIR)/vinix.iso" ./run-amd64-alpine.sh --no-build --interactive

.PHONY: desktop-amd64
desktop-amd64:
	./build-desktop-amd64.sh

.PHONY: run-desktop-amd64
run-desktop-amd64:
	./run-desktop-amd64.sh

.PHONY: macos-installer
macos-installer:
	./build-macos-installer.sh

.PHONY: macos-installer-payload
macos-installer-payload:
	./build-macos-installer-payload.sh

.PHONY: test-macos-installer
test-macos-installer:
	./installer/macos/test.sh

.PHONY: clean
clean:
	rm -rf build-amd64-iso build-amd64-kernel build-amd64-desktop build-aarch64-iso build-aarch64-kernel vinix.iso vinix-aarch64.iso vinix-desktop-amd64.iso build-support/init-aarch64/initramfs.tar build-support/init-aarch64/initramfs-desktop.tar

.PHONY: distclean
distclean: clean
	make -C kernel distclean
	rm -rf build-amd64-userland build-amd64-qemu build-aarch64-userland ovmf
