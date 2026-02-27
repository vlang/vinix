# Nuke built-in rules and variables.
MAKEFLAGS += -rR
.SUFFIXES:

# This is the name that our final executable will have.
# Change as needed.
override OUTPUT := vinix

# Install prefix; /usr/local is a good, standard default pick.
PREFIX := /usr/local

# Target architecture: x86_64 (default) or aarch64.
ARCH ?= x86_64

# User controllable C compiler command.
CC := cc

# User controllable archiver command.
AR := ar

# User controllable V command.
V := v

# User controllable C flags.
CFLAGS := -g -O2 -pipe

# User controllable C preprocessor flags. We set none by default.
CPPFLAGS :=

# User controllable V flags. We set none by default.
VFLAGS :=

# User controllable linker flags. We set none by default.
LDFLAGS :=

PROD :=

# Ensure the dependencies have been obtained.
ifneq ($(shell ( test '$(MAKECMDGOALS)' = clean || test '$(MAKECMDGOALS)' = distclean ); echo $$?),0)
    ifeq ($(shell ( ! test -d freestnd-c-hdrs || ! test -d cc-runtime || ! test -d c/flanterm || ! test -f c/nanoprintf.h ); echo $$?),0)
        $(error Please run the ./get-deps script first)
    endif
endif

# Check if CC is Clang.
override CC_IS_CLANG := $(shell ! $(CC) --version 2>/dev/null | grep 'clang' >/dev/null 2>&1; echo $$?)

# Architecture-specific configuration.
ifeq ($(ARCH),aarch64)

# If the C compiler is Clang, set the target as needed.
ifeq ($(CC_IS_CLANG),1)
    override CC += \
        -target aarch64-unknown-none
endif

# Internal C flags for AArch64.
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
    -ffunction-sections \
    -fdata-sections \
    -fno-strict-aliasing \
    -march=armv8.4-a \
    -mgeneral-regs-only

# On macOS, clang injects platform flags that break bare-metal ELF linking.
# Use ld.lld directly for AArch64 linking.
LD_AARCH64 := ld.lld

# Internal linker flags for AArch64 (passed directly to ld.lld, not via clang).
override LDFLAGS_DIRECT += \
    -m aarch64elf \
    --build-id=none \
    --nostdlib \
    --static \
    -z max-page-size=0x1000 \
    --gc-sections \
    -T linker-aarch64.ld

override CPPFLAGS += -D__AARCH64__

else # x86_64 (default)

# If the C compiler is Clang, set the target as needed.
ifeq ($(CC_IS_CLANG),1)
    override CC += \
        -target x86_64-unknown-none
endif

# Internal C flags for x86_64.
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

# Internal linker flags for x86_64.
override LDFLAGS += \
    -Wl,-m,elf_x86_64 \
    -Wl,--build-id=none \
    -nostdlib \
    -static \
    -z max-page-size=0x1000 \
    -Wl,--gc-sections \
    -T linker.ld

endif # ARCH

# Internal C preprocessor flags that should not be changed by the user.
override CPPFLAGS := \
    -I c \
    -isystem freestnd-c-hdrs \
    $(CPPFLAGS) \
    -MMD \
    -MP

obj/flanterm/backends/fb.c.o: override CPPFLAGS += \
    -DFLANTERM_FB_DISABLE_BUMP_ALLOC

override VFLAGS += \
    -os vinix \
    -enable-globals \
    -nofloat \
    -manualfree \
    -experimental \
    -message-limit 10000 \
    -gc none \
    -d no_backtrace

ifeq ($(ARCH),aarch64)
    override VFLAGS += -d aarch64
endif

ifeq ($(PROD),false)
    override VFLAGS += -warn-about-allocs
else
    override VFLAGS += -prod
    override CPPFLAGS += -DPROD
endif

# V's -os vinix sets __vinix__ in the V layer but does NOT emit #define __vinix__
# in the generated C. The C runtime (builtin__print, write_buf_to_fd) needs it to
# route output through write() -> kwrite() instead of being a no-op.
override CPPFLAGS += -D__vinix__

# Use "find" to glob all *.v, *.c, and *.S files in the tree and obtain the
# object and header dependency file names.
# Exclude arch-specific modules not matching the target architecture.
ifeq ($(ARCH),aarch64)
override VFILES := $(shell find -L * -type f -name '*.v' \
    ! -path 'obj/*' \
    ! -path 'modules/x86/*' \
    ! -path 'modules/acpi/*' \
    ! -path 'modules/uacpi/*' \
    ! -path 'modules/dev/ata/*' \
    ! -path 'modules/dev/console/console.v' \
    ! -path 'modules/dev/hda/*' \
    ! -path 'modules/dev/mouse/*' \
    ! -path 'modules/dev/nvme/*' \
    ! -path 'modules/dev/random/*' \
    ! -path 'modules/dev/serial/*' \
    ! -path 'modules/time/pit.v' \
    ! -path 'modules/syscall/syscall.v' \
    ! -path 'modules/syscall/table/syscall_table.v' \
    ! -path 'modules/userland/userland.v' \
    ! -path 'modules/event/event.v' \
    ! -name 'katomic.v' \
    ! -name 'klock.v' \
    ! -name '*_amd64.v' \
    | LC_ALL=C sort)
override ASFILES := $(shell cd asm && find -L * -type f -name '*.S' \
    ! -name 'int_thunks_asm.S' \
    | LC_ALL=C sort)
else
override VFILES := $(shell find -L * -type f -name '*.v' \
    ! -path 'obj/*' \
    ! -path 'modules/aarch64/*' \
    ! -path 'modules/apple/*' \
    ! -path 'modules/devicetree/*' \
    ! -path 'modules/drm/*' \
    ! -path 'modules/gpu/*' \
    ! -path 'modules/syscall/common.v' \
    ! -name '*_aarch64.v' \
    ! -name '*_arm64.v' \
    | LC_ALL=C sort)
override ASFILES := $(shell cd asm && find -L * -type f -name '*.S' \
    ! -path 'aarch64/*' \
    | LC_ALL=C sort)
endif

override CFILES := $(shell cd c && find -L * -type f -name '*.c' | LC_ALL=C sort)
override OBJ := $(addprefix obj/,$(CFILES:.c=.c.o) $(ASFILES:.S=.S.o))
override HEADER_DEPS := $(addprefix obj/,$(CFILES:.c=.c.d) $(ASFILES:.S=.S.d))

# Default target. This must come first, before header dependencies.
.PHONY: all
all: bin/$(OUTPUT)

# Include header dependencies.
-include obj/blob.c.d $(HEADER_DEPS)

# Link rules for building the C compiler runtime.
cc-runtime-$(ARCH)/cc-runtime.a: GNUmakefile cc-runtime/*
	rm -rf cc-runtime-$(ARCH)
	cp -r cc-runtime cc-runtime-$(ARCH)
	$(MAKE) -C cc-runtime-$(ARCH) -f cc-runtime.mk \
		CC="$(CC)" \
		AR="$(AR)" \
		CFLAGS="$(CFLAGS)" \
		CPPFLAGS='-isystem ../freestnd-c-hdrs -DCC_RUNTIME_NO_FLOAT'

# Link rules for the final executable.
bin/$(OUTPUT): GNUmakefile $(if $(filter aarch64,$(ARCH)),linker-aarch64.ld,linker.ld) obj/blob.c.o $(OBJ) cc-runtime-$(ARCH)/cc-runtime.a
	mkdir -p "$$(dirname $@)"
ifeq ($(ARCH),aarch64)
	$(LD_AARCH64) $(LDFLAGS_DIRECT) obj/blob.c.o $(OBJ) cc-runtime-$(ARCH)/cc-runtime.a -o $@
else
	$(CC) $(CFLAGS) $(LDFLAGS) obj/blob.c.o $(OBJ) cc-runtime-$(ARCH)/cc-runtime.a -o $@
endif

obj/blob.c.o: GNUmakefile $(VFILES)
	mkdir -p "$$(dirname $@)"
	rm -rf obj/vsrc
	for f in $(VFILES); do mkdir -p "obj/vsrc/$$(dirname $$f)" && ln -sf "$(CURDIR)/$$f" "obj/vsrc/$$f"; done
	$(V) $(VFLAGS) -o obj/blob.c obj/vsrc
	sed 's/call 0(/call *(/g;/Wimplicit-function-declaration/d' < obj/blob.c > obj/blob.c.tmp
	mv obj/blob.c.tmp obj/blob.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -w -c obj/blob.c -o $@

# Compilation rules for *.c files.
obj/%.c.o: c/%.c GNUmakefile
	mkdir -p "$$(dirname $@)"
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

# Compilation rules for *.S files.
obj/%.S.o: asm/%.S GNUmakefile
	mkdir -p "$$(dirname $@)"
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

# Remove object files and the final executable.
.PHONY: clean
clean:
	rm -rf bin obj cc-runtime-x86_64 cc-runtime-aarch64

# Remove everything built and generated including downloaded dependencies.
.PHONY: distclean
distclean: clean
	rm -rf freestnd-c-hdrs cc-runtime c/flanterm c/nanoprintf* c/uacpi uacpi-repository

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
