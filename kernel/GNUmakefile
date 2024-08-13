# GNUmakefile: Makefile of the kernel.
# Code is governed by the GPL-2.0 license.
# Copyright (C) 2021-2022 The Vinix authors.

# Nuke built-in rules and variables.
override MAKEFLAGS += -rR

# This is the name that our final executable will have.
# Change as needed.
override OUTPUT := vinix

# Convenience macro to reliably declare user overridable variables.
define DEFAULT_VAR =
    ifeq ($(origin $1),default)
        override $(1) := $(2)
    endif
    ifeq ($(origin $1),undefined)
        override $(1) := $(2)
    endif
endef

# User controllable C compiler command.
override DEFAULT_KCC := cc
$(eval $(call DEFAULT_VAR,KCC,$(DEFAULT_KCC)))

# User controllable linker command.
override DEFAULT_KLD := ld
$(eval $(call DEFAULT_VAR,KLD,$(DEFAULT_KLD)))

# User controllable objdump command.
override DEFAULT_KOBJDUMP := objdump
$(eval $(call DEFAULT_VAR,KOBJDUMP,$(DEFAULT_KOBJDUMP)))

# User controllable V command.
override DEFAULT_KV := v
$(eval $(call DEFAULT_VAR,KV,$(DEFAULT_KV)))

# User controllable C flags.
override DEFAULT_KCFLAGS := -g -O2 -pipe
$(eval $(call DEFAULT_VAR,KCFLAGS,$(DEFAULT_KCFLAGS)))

# User controllable C preprocessor flags. We set none by default.
override DEFAULT_KCPPFLAGS :=
$(eval $(call DEFAULT_VAR,KCPPFLAGS,$(DEFAULT_KCPPFLAGS)))

# User controllable V flags. We set none by default.
override DEFAULT_KVFLAGS :=
$(eval $(call DEFAULT_VAR,KVFLAGS,$(DEFAULT_KVFLAGS)))

# User controllable linker flags. We set none by default.
override DEFAULT_KLDFLAGS :=
$(eval $(call DEFAULT_VAR,KLDFLAGS,$(DEFAULT_KLDFLAGS)))

VINIX_PROD ?=
ifeq ($(VINIX_PROD),no)
    override PROD := false
else
    override PROD := true
endif

# Internal C flags that should not be changed by the user.
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
    -fno-lto \
    -fno-PIC \
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

# Internal C preprocessor flags that should not be changed by the user.
override KCPPFLAGS := \
    -I c \
    $(KCPPFLAGS) \
    -isystem freestanding-headers \
    -MMD \
    -MP

obj/printf/printf.c.o: override KCPPFLAGS += \
    -DPRINTF_SUPPORT_DECIMAL_SPECIFIERS=0 \
    -DPRINTF_SUPPORT_EXPONENTIAL_SPECIFIERS=0

obj/flanterm/backends/fb.c.o: override KCPPFLAGS += \
    -DFLANTERM_FB_DISABLE_BUMP_ALLOC

# Internal linker flags that should not be changed by the user.
override KLDFLAGS += \
    -m elf_x86_64 \
    -nostdlib \
    -static \
    -z max-page-size=0x1000 \
    -gc-sections \
    -T linker.ld

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

# Use "find" to glob all *.v, *.c, and *.S files in the tree and obtain the
# object and header dependency file names.
override VFILES := $(shell find -L * -type f -name '*.v' | LC_ALL=C sort)
override CFILES := $(shell cd c && find -L * -type f -name '*.c' | LC_ALL=C sort)
override ASFILES := $(shell cd asm && find -L * -type f -name '*.S' | LC_ALL=C sort)
override OBJ := $(addprefix obj/,$(CFILES:.c=.c.o) $(ASFILES:.S=.S.o))
override HEADER_DEPS := $(addprefix obj/,$(CFILES:.c=.c.d) $(ASFILES:.S=.S.d))

# Ensure the dependencies have been obtained.
override MISSING_DEPS := $(shell if ! test -d freestanding-headers || ! test -f c/cc-runtime.c || ! test -f c/printf/printf.c || ! test -f c/printf/printf.h; then echo 1; fi)
ifeq ($(MISSING_DEPS),1)
    $(error Please run the ./get-deps script first)
endif

# Default target.
.PHONY: all
all: bin/$(OUTPUT)

# Link rules for the final executable.
bin/$(OUTPUT): GNUmakefile linker.ld obj/blob.c.o $(OBJ)
	mkdir -p "$$(dirname $@)"
	$(KLD) obj/blob.c.o $(OBJ) $(KLDFLAGS) -o $@
	./gensyms.sh $(KOBJDUMP) $@ > obj/symbol_table.c
	$(KCC) $(KCFLAGS) $(KCPPFLAGS) -c obj/symbol_table.c -o obj/symbol_table.c.o
	$(KLD) obj/blob.c.o $(OBJ) $(KLDFLAGS) -o $@

obj/blob.c.o: $(VFILES)
	mkdir -p "$$(dirname $@)"
	$(KV) $(KVFLAGS) -o obj/blob.c .
	sed 's/call 0(/call *(/g' < obj/blob.c > obj/blob.c.tmp
	mv obj/blob.c.tmp obj/blob.c
	$(KCC) $(KCFLAGS) $(KCPPFLAGS) -w -c obj/blob.c -o $@

# Include header dependencies.
-include $(HEADER_DEPS)

# Compilation rules for *.c files.
obj/%.c.o: c/%.c GNUmakefile
	mkdir -p "$$(dirname $@)"
	$(KCC) $(KCFLAGS) $(KCPPFLAGS) -c $< -o $@

# Compilation rules for *.S files.
obj/%.S.o: asm/%.S GNUmakefile
	mkdir -p "$$(dirname $@)"
	$(KCC) $(KCFLAGS) $(KCPPFLAGS) -c $< -o $@

# Remove object files and the final executable.
.PHONY: clean
clean:
	rm -rf bin obj

# Remove everything built and generated including downloaded dependencies.
.PHONY: distclean
distclean: clean
	rm -rf freestanding-headers c/cc-runtime.c c/flanterm c/printf

# Install the final built executable to its final on-root location.
.PHONY: install
install: all
	install -d "$(DESTDIR)$(PREFIX)/share/$(OUTPUT)"
	install -m 644 bin/$(OUTPUT) "$(DESTDIR)$(PREFIX)/share/$(OUTPUT)/"
