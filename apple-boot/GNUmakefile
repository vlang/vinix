# Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
# Use of this source code is governed by a GPL v2 license
# that can be found in the LICENSE file.
#
# Builds the Apple-silicon loader and its host tests. `make` produces
# build/vinix-apple-loader.bin; ../build-apple-boot.sh appends the kernel,
# initramfs and command line to it.

LLVM ?= /opt/homebrew/opt/llvm/bin
CC := $(LLVM)/clang
LD := ld.lld
OBJCOPY := $(LLVM)/llvm-objcopy
HOSTCC ?= clang

BUILD := build
SOURCES := src/loader.c src/bootargs.c src/console.c src/mm.c src/elf.c src/limine.c \
	src/wdt.c src/memmap.c
OBJECTS := $(patsubst src/%.c,$(BUILD)/obj/%.o,$(SOURCES)) $(BUILD)/obj/start.o $(BUILD)/obj/vcore.o

CFLAGS := --target=aarch64-none-elf -std=gnu11 -O2 -g -Wall -Wextra -Werror \
	-ffreestanding -fno-builtin -nostdlib -fPIE -mstrict-align -mgeneral-regs-only \
	-mno-outline-atomics -fno-stack-protector -fno-asynchronous-unwind-tables \
	-fno-unwind-tables -ffunction-sections -fdata-sections
VFILES := $(wildcard vcore/*.v)
V_CFLAGS := -nostdinc -isystem ../kernel/freestnd-c-hdrs -Isrc -DAPPLE_BOOT_FREESTANDING \
	-fwrapv -fno-strict-aliasing -Wno-unused-function -Wno-unused-parameter

LDFLAGS := -T apple-boot.ld -pie --no-dynamic-linker -z norelro --pack-dyn-relocs=none \
	--gc-sections --no-undefined

.PHONY: all test clean
all: $(BUILD)/vinix-apple-loader.bin

$(BUILD)/obj/%.o: src/%.c src/*.h
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/obj/vcore.c: $(VFILES) compile-v.py
	@mkdir -p $(dir $@)
	python3 compile-v.py $@

$(BUILD)/obj/vcore.o: $(BUILD)/obj/vcore.c src/v_abi.h
	$(CC) $(CFLAGS) $(V_CFLAGS) -c $< -o $@

$(BUILD)/obj/start.o: src/start.S
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/vinix-apple-loader.elf: $(OBJECTS) apple-boot.ld
	$(LD) $(LDFLAGS) -o $@ $(OBJECTS)

$(BUILD)/vinix-apple-loader.bin: $(BUILD)/vinix-apple-loader.elf
	$(OBJCOPY) -O binary --strip-debug $< $@

$(BUILD)/obj/vcore-host.c: $(VFILES) compile-v.py
	@mkdir -p $(dir $@)
	python3 compile-v.py --host $@

$(BUILD)/obj/vcore-host.o: $(BUILD)/obj/vcore-host.c src/v_abi.h
	$(HOSTCC) -std=gnu11 -O2 -g -Wall -Wextra -Werror -Wno-unused-function \
		-Wno-unused-parameter -ffreestanding -fno-builtin -fwrapv -fno-strict-aliasing \
		-ffunction-sections -fdata-sections -Isrc -c $< -o $@

comma := ,
HOST_GC := $(if $(filter Darwin,$(shell uname -s)),-Wl$(comma)-dead_strip,-Wl$(comma)--gc-sections)

$(BUILD)/adt2fdt: tests/adt2fdt.c $(BUILD)/obj/vcore-host.o src/*.h
	@mkdir -p $(BUILD)
	$(HOSTCC) -O2 -g -Wall -Wextra -Werror -DAPPLE_BOOT_HOST $(HOST_GC) -o $@ \
		tests/adt2fdt.c $(BUILD)/obj/vcore-host.o

# The converter check reads this Mac's IORegistry; the QEMU test boots
# $(VINIX_KERNEL_DIR)/bin/vinix (default ../kernel) through a fake iBoot.
test: $(BUILD)/adt2fdt $(BUILD)/vinix-apple-loader.bin
	python3 tests/check_converter.py
	python3 tests/qemu_iboot.py
	python3 tests/qemu_iboot.py --real-adt

clean:
	rm -rf $(BUILD)
