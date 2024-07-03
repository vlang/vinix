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

override DEFAULT_KTOOLCHAIN :=
$(eval $(call DEFAULT_VAR,KTOOLCHAIN,$(DEFAULT_KTOOLCHAIN)))

override DEFAULT_KCC := $(KTOOLCHAIN)cc
$(eval $(call DEFAULT_VAR,KCC,$(DEFAULT_KCC)))

override DEFAULT_KOBJDUMP := $(KTOOLCHAIN)objdump
$(eval $(call DEFAULT_VAR,KOBJDUMP,$(DEFAULT_KOBJDUMP)))

override DEFAULT_KV := v
$(eval $(call DEFAULT_VAR,KV,$(DEFAULT_KV)))

override DEFAULT_KCFLAGS := -g -O2 -pipe
$(eval $(call DEFAULT_VAR,KCFLAGS,$(DEFAULT_KCFLAGS)))

override DEFAULT_KCPPFLAGS :=
$(eval $(call DEFAULT_VAR,KCPPFLAGS,$(DEFAULT_KCPPFLAGS)))

override DEFAULT_KVFLAGS :=
$(eval $(call DEFAULT_VAR,KVFLAGS,$(DEFAULT_KVFLAGS)))

override DEFAULT_KLDFLAGS :=
$(eval $(call DEFAULT_VAR,KLDFLAGS,$(DEFAULT_KLDFLAGS)))

VINIX_PROD ?=
ifeq ($(VINIX_PROD),no)
    override PROD := false
else
    override PROD := true
endif

override KCFLAGS += \
    -g \
    -Wall \
    -Wextra \
    -std=gnu99 \
    -nostdinc \
    -ffreestanding \
    -fno-omit-frame-pointer \
    -fno-stack-protector \
    -fno-stack-check \
    -fPIE \
    -ffunction-sections \
    -fdata-sections \
    -fno-strict-aliasing \
    -m64 \
    -march=x86-64 \
    -mno-80387 \
    -mno-mmx \
    -mno-sse \
    -mno-sse2 \
    -mno-red-zone

override KCPPFLAGS := \
    -I c \
    -isystem c/freestanding-headers \
    $(KCPPFLAGS) \
    -MMD \
    -MP

obj/c/printf/printf.c.o: override KCPPFLAGS += \
    -DPRINTF_SUPPORT_DECIMAL_SPECIFIERS=0 \
    -DPRINTF_SUPPORT_EXPONENTIAL_SPECIFIERS=0

obj/c/flanterm/backends/fb.c.o: override KCPPFLAGS += \
    -DFLANTERM_FB_DISABLE_BUMP_ALLOC

override KLDFLAGS += \
    -nostdlib \
    -pie \
    -Wl,-m,elf_x86_64 \
    -Wl,-nostdlib \
    -Wl,-pie \
    -Wl,-z,separate-code \
    -Wl,-z,text \
    -Wl,-z,max-page-size=0x1000 \
    -Wl,-T,linker.ld \
    -Wl,-gc-sections

override KVFLAGS += \
    -os vinix \
    -enable-globals \
    -nofloat \
    -manualfree \
    -experimental \
    -message-limit 10000 \
    -gc none \
    -d no_backtrace

ifeq ($(PROD),true)
	override KVFLAGS += -prod
	override KCPPFLAGS += -DPROD
else
	override KVFLAGS += -warn-about-allocs
endif

override VFILES := $(shell find -L * -type f -name '*.v')
override CFILES := $(shell find -L c/* -type f -name '*.c')
override ASFILES := $(shell find -L asm/* -type f -name '*.S')
override OBJ := $(addprefix obj/,$(CFILES:.c=.c.o) $(ASFILES:.S=.S.o))
override HEADER_DEPS := $(addprefix obj/,$(CFILES:.c=.c.d) $(ASFILES:.S=.S.d))

.PHONY: all
all: bin/$(KERNEL)

# The magic printf/dd command is used to force the final ELF file type to ET_DYN.
# GNU binutils, for silly reasons, forces the ELF type to ET_EXEC even for
# relocatable PIEs, if the base load address is non-0.
# See https://sourceware.org/bugzilla/show_bug.cgi?id=31795 for more information.
bin/$(KERNEL): GNUmakefile linker.ld obj/blob.c.o $(OBJ)
	mkdir -p "$$(dirname $@)"
	$(KCC) $(KCFLAGS) obj/blob.c.o $(OBJ) $(KLDFLAGS) -o $@
	mv c/symbol_table.c symbol_table.c.tmp
	./gensyms.sh $(KOBJDUMP) $@ > c/symbol_table.c
	$(KCC) $(KCFLAGS) $(KCPPFLAGS) -c c/symbol_table.c -o obj/c/symbol_table.c.o
	$(KCC) $(KCFLAGS) obj/blob.c.o $(OBJ) $(KLDFLAGS) -o $@
	mv symbol_table.c.tmp c/symbol_table.c
	printf '\003' | dd of=$@ bs=1 count=1 seek=16 conv=notrunc 2>/dev/null

obj/blob.c.o: $(VFILES)
	mkdir -p "$$(dirname $@)"
	$(KV) $(KVFLAGS) -o obj/blob.c .
	sed 's/call 0(/call *(/g' < obj/blob.c > obj/blob.c.tmp
	mv obj/blob.c.tmp obj/blob.c
	$(KCC) $(KCFLAGS) $(KCPPFLAGS) -w -c obj/blob.c -o $@

-include $(HEADER_DEPS)

obj/%.c.o: %.c GNUmakefile
	mkdir -p "$$(dirname $@)"
	$(KCC) $(KCFLAGS) $(KCPPFLAGS) -c $< -o $@

obj/%.S.o: %.S GNUmakefile
	mkdir -p "$$(dirname $@)"
	$(KCC) $(KCFLAGS) $(KCPPFLAGS) -c $< -o $@

.PHONY: clean
clean:
	rm -rf bin obj

.PHONY: distclean
distclean: clean
	rm -rf c/freestanding-headers c/flanterm c/printf printf

.PHONY: install
install:
	install -d "$(DESTDIR)$(PREFIX)/share/$(KERNEL)"
	install -m 644 bin/$(KERNEL) "$(DESTDIR)$(PREFIX)/share/$(KERNEL)/"
