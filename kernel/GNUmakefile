# GNUmakefile: Makefile of the kernel.
# Code is governed by the GPL-2.0 license.
# Copyright (C) 2021-2022 The Vinix authors.

# Nuke built-in rules and variables.
override MAKEFLAGS += -rR

override KERNEL := vinix

define DEFAULT_VAR =
    ifeq ($(origin $1),default)
        override $(1) := $(2)
    endif
    ifeq ($(origin $1),undefined)
        override $(1) := $(2)
    endif
endef

override DEFAULT_TOOLCHAIN_PREFIX :=
$(eval $(call DEFAULT_VAR,TOOLCHAIN_PREFIX,$(DEFAULT_TOOLCHAIN_PREFIX)))

override DEFAULT_CC := $(TOOLCHAIN_PREFIX)cc
$(eval $(call DEFAULT_VAR,CC,$(DEFAULT_CC)))

override DEFAULT_LD := $(TOOLCHAIN_PREFIX)ld
$(eval $(call DEFAULT_VAR,LD,$(DEFAULT_LD)))

override DEFAULT_OBJDUMP := $(TOOLCHAIN_PREFIX)objdump
$(eval $(call DEFAULT_VAR,OBJDUMP,$(DEFAULT_OBJDUMP)))

override DEFAULT_V := v
$(eval $(call DEFAULT_VAR,V,$(DEFAULT_V)))

override DEFAULT_CFLAGS := -g -O2 -pipe
$(eval $(call DEFAULT_VAR,CFLAGS,$(DEFAULT_CFLAGS)))

override DEFAULT_CPPFLAGS :=
$(eval $(call DEFAULT_VAR,CPPFLAGS,$(DEFAULT_CPPFLAGS)))

override DEFAULT_VFLAGS :=
$(eval $(call DEFAULT_VAR,VFLAGS,$(DEFAULT_VFLAGS)))

override DEFAULT_LDFLAGS :=
$(eval $(call DEFAULT_VAR,LDFLAGS,$(DEFAULT_LDFLAGS)))

VINIX_PROD ?=
ifeq ($(VINIX_PROD),no)
    override PROD := false
else
    override PROD := true
endif

override CFLAGS += \
    -g \
    -Wall \
    -Wextra \
    -std=gnu99 \
    -nostdinc \
    -ffreestanding \
    -fno-omit-frame-pointer \
    -fno-stack-protector \
    -fno-stack-check \
    -fno-lto \
    -fno-PIC \
    -fno-PIE \
    -ffunction-sections \
    -fdata-sections \
    -fno-strict-aliasing \
    -m64 \
    -march=x86-64 \
    -mno-80387 \
    -mno-mmx \
    -mno-sse \
    -mno-sse2 \
    -mno-red-zone \
    -mcmodel=kernel

override CPPFLAGS := \
    -I c \
    -isystem c/freestanding-headers \
    $(CPPFLAGS) \
    -MMD \
    -MP

obj/c/printf/printf.c.o: override CPPFLAGS += \
    -DPRINTF_SUPPORT_DECIMAL_SPECIFIERS=0 \
    -DPRINTF_SUPPORT_EXPONENTIAL_SPECIFIERS=0

override LDFLAGS += \
    -m elf_x86_64 \
    -nostdlib \
    -static \
    -zmax-page-size=0x1000 \
    -Tlinker.ld \
    -gc-sections

override VFLAGS += \
    -os vinix \
    -enable-globals \
    -nofloat \
    -autofree \
    -gc none \
    -d no_backtrace

ifeq ($(PROD),true)
	override VFLAGS += -prod
	override CPPFLAGS += -DPROD
endif

override VFILES := $(shell find -L * -type f -name '*.v')
override CFILES := $(shell find -L c/* -type f -name '*.c')
override ASFILES := $(shell find -L asm/* -type f -name '*.S')
override OBJ := $(addprefix obj/,$(CFILES:.c=.c.o) $(ASFILES:.S=.S.o))
override HEADER_DEPS := $(addprefix obj/,$(CFILES:.c=.c.d) $(ASFILES:.S=.S.d))

.PHONY: all
all: bin/$(KERNEL)

bin/$(KERNEL): GNUmakefile linker.ld obj/blob.c.o $(OBJ)
	mkdir -p "$$(dirname $@)"
	$(LD) obj/blob.c.o $(OBJ) $(LDFLAGS) -o $@
	mv c/symbol_table.c symbol_table.c.tmp
	./gensyms.sh $(OBJDUMP) $@ > c/symbol_table.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -c c/symbol_table.c -o obj/c/symbol_table.c.o
	$(LD) obj/blob.c.o $(OBJ) $(LDFLAGS) -o $@
	mv symbol_table.c.tmp c/symbol_table.c

obj/blob.c.o: $(VFILES)
	mkdir -p "$$(dirname $@)"
	$(V) $(VFLAGS) -o obj/blob.c .
	$(CC) $(CFLAGS) $(CPPFLAGS) -w -c obj/blob.c -o $@

-include $(HEADER_DEPS)

obj/%.c.o: %.c GNUmakefile
	mkdir -p "$$(dirname $@)"
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

obj/%.S.o: %.S GNUmakefile
	mkdir -p "$$(dirname $@)"
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

.PHONY: clean
clean:
	rm -rf bin obj

.PHONY: distclean
distclean: clean
	rm -rf c/freestanding-headers c/flanterm c/printf

.PHONY: install
install:
	install -d "$(DESTDIR)$(PREFIX)/share/vinix"
	install -m 644 bin/$(KERNEL) "$(DESTDIR)$(PREFIX)/share/vinix/"
