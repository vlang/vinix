# GNUmakefile: Makefile of the kernel.
# Code is governed by the GPL-2.0 license.
# Copyright (C) 2021-2024 The Vinix authors.

# Nuke built-in rules and variables.
MAKEFLAGS += -rR
.SUFFIXES:

# This is the name that our final executable will have.
# Change as needed.
override OUTPUT := vinix

# Convenience macro to reliably declare user overridable variables.
override USER_VARIABLE = $(if $(filter $(origin $(1)),default undefined),$(eval override $(1) := $(2)))

# Destination directory on install (should always be empty by default).
$(call USER_VARIABLE,DESTDIR,)

# Install prefix; /usr/local is a good, standard default pick.
$(call USER_VARIABLE,PREFIX,/usr/local)

# User controllable C compiler command.
$(call USER_VARIABLE,KCC,cc)

# User controllable linker command.
$(call USER_VARIABLE,KLD,ld)

# User controllable objdump command.
$(call USER_VARIABLE,KOBJDUMP,objdump)

# User controllable V command.
$(call USER_VARIABLE,KV,v)

# User controllable C flags.
$(call USER_VARIABLE,KCFLAGS,-g -O2 -pipe)

# User controllable C preprocessor flags. We set none by default.
$(call USER_VARIABLE,KCPPFLAGS,)

# User controllable V flags. We set none by default.
$(call USER_VARIABLE,KVFLAGS,)

# User controllable linker flags. We set none by default.
$(call USER_VARIABLE,KLDFLAGS,)

$(call USER_VARIABLE,VINIX_PROD,)

# Ensure the dependencies have been obtained.
ifneq ($(shell ( test '$(MAKECMDGOALS)' = clean || test '$(MAKECMDGOALS)' = distclean ); echo $$?),0)
    ifeq ($(shell ( ! test -d freestnd-c-hdrs-0bsd || ! test -f c/cc-runtime.c || ! test -d c/flanterm || ! test -f c/printf/printf.c || ! test -f c/printf/printf.h ); echo $$?),0)
        $(error Please run the ./get-deps script first)
    endif
endif

# Check if KCC is Clang.
override KCC_IS_CLANG := $(shell ! $(KCC) --version 2>/dev/null | grep 'clang' >/dev/null 2>&1; echo $$?)

# If the C compiler is Clang, set the target as needed.
ifeq ($(KCC_IS_CLANG),1)
    override KCC += \
        -target x86_64-unknown-none
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
    -isystem freestnd-c-hdrs-0bsd \
    $(KCPPFLAGS) \
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

ifeq ($(VINIX_PROD),no)
    override KVFLAGS += -warn-about-allocs
else
    override KVFLAGS += -prod
    override KCPPFLAGS += -DPROD
endif

# Use "find" to glob all *.v, *.c, and *.S files in the tree and obtain the
# object and header dependency file names.
override VFILES := $(shell find -L * -type f -name '*.v' | LC_ALL=C sort)
override CFILES := $(shell cd c && find -L * -type f -name '*.c' | LC_ALL=C sort)
override ASFILES := $(shell cd asm && find -L * -type f -name '*.S' | LC_ALL=C sort)
override OBJ := $(addprefix obj/,$(CFILES:.c=.c.o) $(ASFILES:.S=.S.o))
override HEADER_DEPS := $(addprefix obj/,$(CFILES:.c=.c.d) $(ASFILES:.S=.S.d))

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
	rm -rf freestnd-c-hdrs-0bsd c/cc-runtime.c c/flanterm c/printf

# Install the final built executable to its final on-root location.
.PHONY: install
install: all
	install -d "$(DESTDIR)$(PREFIX)/share/$(OUTPUT)"
	install -m 644 bin/$(OUTPUT) "$(DESTDIR)$(PREFIX)/share/$(OUTPUT)/"

# Try to undo whatever the "install" target did.
.PHONY: uninstall
uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/share/$(OUTPUT)/$(OUTPUT)"
	-rmdir "$(DESTDIR)$(PREFIX)/share/$(OUTPUT)"
