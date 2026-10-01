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

# Opt-in until the complete i915 kernel API surface is implemented. The
# imported Linux driver stays byte-for-byte upstream in third_party/.
LINUXKPI ?= 0
LINUXKPI_SOURCE_DIR ?= $(abspath ../third_party/linux-i915/linux-6.6.157)
ifneq ($(LINUXKPI),0)
ifneq ($(LINUXKPI),1)
    $(error LINUXKPI must be 0 or 1)
endif
ifneq ($(ARCH),x86_64)
    $(error LINUXKPI currently supports ARCH=x86_64 only)
endif
ifeq ($(wildcard $(LINUXKPI_SOURCE_DIR)/.vinix-upstream.json),)
    $(error Run python3 linuxkpi/upstream.py fetch before enabling LINUXKPI)
endif
endif

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

# Emit Limine's multiprocessor request when the boot environment can start
# secondary CPUs safely. Generic direct builds stay conservative; the M1
# deployment selects this explicitly alongside its pinned Limine 12.8 loader.
LIMINE_MP ?= 0
ifneq ($(LIMINE_MP),0)
ifneq ($(LIMINE_MP),1)
    $(error LIMINE_MP must be 0 or 1)
endif
endif

# User controllable linker flags. We set none by default.
LDFLAGS :=

# Optional direct linker for cross-building x86_64 on a non-x86 host. Leave
# empty to retain the compiler-driver link used by native builds.
LD_X86_64 ?=

PROD :=

# Ensure the dependencies have been obtained.
ifneq ($(shell ( test '$(MAKECMDGOALS)' = clean || test '$(MAKECMDGOALS)' = distclean ); echo $$?),0)
    ifeq ($(shell ( ! test -d freestnd-c-hdrs || ! test -d cc-runtime || ! test -d c/flanterm || ! test -f c/nanoprintf.h || ! test -f c/lwip/include/lwip/init.h ); echo $$?),0)
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
    -fstack-protector-strong \
    -mstack-protector-guard=global \
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
LD_AARCH64 ?= ld.lld

# Internal linker flags for AArch64 (passed directly to ld.lld, not via clang).
override LDFLAGS_DIRECT += \
    -m aarch64elf \
    --build-id=none \
    --nostdlib \
    --static \
    -z max-page-size=0x4000 \
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
    -fstack-protector-strong \
    -mstack-protector-guard=global \
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

override LDFLAGS_DIRECT_X86_64 += \
    -m elf_x86_64 \
    --build-id=none \
    --nostdlib \
    --static \
    -z max-page-size=0x1000 \
    --gc-sections \
    -T linker.ld

endif # ARCH

# Internal C preprocessor flags that should not be changed by the user.
override CPPFLAGS := \
    -I c \
    -I c/lwip/include \
    -isystem freestnd-c-hdrs \
    $(CPPFLAGS) \
    -MMD \
    -MP

obj/c/flanterm/backends/fb.c.o: override CPPFLAGS += \
    -DFLANTERM_FB_DISABLE_BUMP_ALLOC

override VFLAGS += \
    -os vinix \
    -enable-globals \
    -nofloat \
    -manualfree \
    -message-limit 10000 \
    -gc none \
    -target-libc-headers \
    -no-closures \
    -d no_backtrace

ifeq ($(ARCH),aarch64)
    override VFLAGS += -arch arm64 -d aarch64
    ifeq ($(LIMINE_MP),1)
        override VFLAGS += -d limine_mp
    endif
else
    override VFLAGS += -arch amd64
endif

# V build tags change the generated kernel C even though no source timestamp
# changes. Keep the selected configuration in the prerequisite name so moving
# between a QEMU SMP build and a hardware-safe Apple build cannot reuse a
# stale obj/blob.c.o.
V_CONFIG_STAMP := obj/.v-config-$(ARCH)-limine-mp-$(LIMINE_MP)-alloc-track-$(ALLOC_TRACK)-linuxkpi-$(LINUXKPI)

ifeq ($(LINUXKPI),1)
    override VFLAGS += -d linuxkpi
    override CPPFLAGS += -DVINIX_LINUXKPI
    LINUXKPI_CPPFLAGS := -D__KERNEL__ -include linux/kconfig.h -I linuxkpi/include -I $(LINUXKPI_SOURCE_DIR)/include -I $(LINUXKPI_SOURCE_DIR)/include/uapi -I $(LINUXKPI_SOURCE_DIR)/arch/x86/include -I $(LINUXKPI_SOURCE_DIR)/drivers/gpu/drm/i915 -Wno-unused-parameter -fwrapv
    LINUXKPI_OBJ := obj/linuxkpi/list_sort.o obj/linuxkpi/sort.o obj/linuxkpi/rbtree.o obj/linuxkpi/find_bit.o obj/linuxkpi/hweight.o obj/linuxkpi/i915_memcpy.o
    obj/c/linuxkpi.c.o obj/c/linuxkpi_refcount.c.o obj/c/linuxkpi_string.c.o obj/c/linuxkpi_percpu.c.o: override CPPFLAGS += $(LINUXKPI_CPPFLAGS)
endif

# ALLOC_TRACK=1 records the call chain of every live slab allocation, for
# hunting leaks; see c/alloc_track.c. It costs a 7 MiB table and a lock on
# every allocation, so it is off unless asked for.
ifeq ($(ALLOC_TRACK),1)
    override VFLAGS += -d alloc_track
    override CPPFLAGS += -DVINIX_ALLOC_TRACK
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
    ! -path 'x86/*' \
    ! -path 'acpi/*' \
    ! -path 'uacpi/*' \
    ! -path 'dev/ata/*' \
    ! -path 'dev/hda/*' \
    ! -path 'dev/mouse/*' \
    ! -path 'dev/nvme/*' \
    ! -path 'dev/serial/*' \
    ! -path 'time/pit.v' \
    ! -path 'syscall/syscall.v' \
    ! -path 'userland/userland.v' \
    ! -name 'katomic.v' \
    ! -name 'klock.v' \
    ! -name '*_amd64.v' \
    | LC_ALL=C sort)
override ASFILES := $(shell cd asm && find -L * -type f -name '*.S' \
    ! -name 'int_thunks_asm.S' \
    ! -path 'x86_64/*' \
    | LC_ALL=C sort)
else
override VFILES := $(shell find -L * -type f -name '*.v' \
    ! -path 'obj/*' \
    ! -path 'aarch64/*' \
    ! -path 'apple/*' \
    ! -path 'devicetree/*' \
    ! -path 'drm/*' \
    ! -path 'gpu/*' \
    ! -path 'dev/pointerdev/*' \
    ! -path 'syscall/common.v' \
    ! -name '*_aarch64.v' \
    ! -name '*_arm64.v' \
    | LC_ALL=C sort)
override ASFILES := $(shell cd asm && find -L * -type f -name '*.S' \
    ! -path 'aarch64/*' \
    | LC_ALL=C sort)
endif

override CFILES := $(shell cd c && find -L * -type f -name '*.c' | LC_ALL=C sort)
# Keep generated C and assembly objects below distinct subdirectories. In
# particular, c/uacpi used to create obj/uacpi, which V then mistook for the
# imported `uacpi` package while compiling obj/vsrc.
override COBJ := $(addprefix obj/c/,$(CFILES:.c=.c.o))
override ASOBJ := $(addprefix obj/asm/,$(ASFILES:.S=.S.o))
override OBJ := $(COBJ) $(ASOBJ) $(LINUXKPI_OBJ)
override HEADER_DEPS := $(addprefix obj/c/,$(CFILES:.c=.c.d)) $(addprefix obj/asm/,$(ASFILES:.S=.S.d))

# Default target. This must come first, before header dependencies.
.PHONY: all
all: bin/$(OUTPUT)
obj/c/linuxkpi.c.o obj/c/linuxkpi_refcount.c.o obj/c/linuxkpi_string.c.o obj/c/linuxkpi_percpu.c.o: $(V_CONFIG_STAMP)

ifeq ($(LINUXKPI),1)
.PHONY: linuxkpi-verify
linuxkpi-verify:
	python3 linuxkpi/upstream.py verify --base $(dir $(LINUXKPI_SOURCE_DIR))
all: linuxkpi-verify

$(LINUXKPI_OBJ) obj/c/linuxkpi.c.o obj/c/linuxkpi_refcount.c.o obj/c/linuxkpi_string.c.o obj/c/linuxkpi_percpu.c.o: | linuxkpi-verify

obj/linuxkpi/%.o: $(LINUXKPI_SOURCE_DIR)/lib/%.c GNUmakefile $(V_CONFIG_STAMP)
	mkdir -p "$(@D)"
	$(CC) $(CFLAGS) $(CPPFLAGS) $(LINUXKPI_CPPFLAGS) -std=gnu11 -c $< -o $@

obj/linuxkpi/i915_memcpy.o: $(LINUXKPI_SOURCE_DIR)/drivers/gpu/drm/i915/i915_memcpy.c GNUmakefile $(V_CONFIG_STAMP)
	mkdir -p "$(@D)"
	$(CC) $(CFLAGS) $(CPPFLAGS) $(LINUXKPI_CPPFLAGS) -std=gnu11 -c $< -o $@
endif

# Include header dependencies.
-include obj/blob.c.d $(HEADER_DEPS) $(LINUXKPI_OBJ:.o=.d)

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
ifneq ($(strip $(LD_X86_64)),)
	$(LD_X86_64) $(LDFLAGS_DIRECT_X86_64) obj/blob.c.o $(OBJ) cc-runtime-$(ARCH)/cc-runtime.a -o $@
else
	$(CC) $(CFLAGS) $(LDFLAGS) obj/blob.c.o $(OBJ) cc-runtime-$(ARCH)/cc-runtime.a -o $@
endif
endif

$(V_CONFIG_STAMP):
	mkdir -p obj
	rm -f obj/.v-config-*
	touch $@

# The tracker's C half follows the same switch as its V half.
obj/c/alloc_track.c.o: $(V_CONFIG_STAMP)

obj/blob.c.o: GNUmakefile $(VFILES) $(V_CONFIG_STAMP)
	mkdir -p "$$(dirname $@)"
	rm -rf obj/vsrc
	for f in $(VFILES); do mkdir -p "obj/vsrc/$$(dirname $$f)" && ln -sf "$(CURDIR)/$$f" "obj/vsrc/$$f"; done
# The modules live beside main.v, so V looks them up under the nearest v.mod.
# Give the filtered tree its own v.mod, or that root would be $(CURDIR) and the
# arch-specific files this build deliberately left out of VFILES would be read
# back from the originals.
	cp v.mod obj/vsrc/v.mod
	$(V) $(VFLAGS) -o obj/blob.c obj/vsrc
	sed 's/call 0(/call *(/g;/Wimplicit-function-declaration/d' < obj/blob.c > obj/blob.c.tmp
	mv obj/blob.c.tmp obj/blob.c
	$(CC) $(CFLAGS) $(CPPFLAGS) -w -c obj/blob.c -o $@

# Compilation rules for *.c files.
obj/c/%.c.o: c/%.c GNUmakefile
	mkdir -p "$$(dirname $@)"
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

# Compilation rules for *.S files.
obj/asm/%.S.o: asm/%.S GNUmakefile
	mkdir -p "$$(dirname $@)"
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $< -o $@

# Remove object files and the final executable.
.PHONY: clean
clean:
	rm -rf bin obj cc-runtime-x86_64 cc-runtime-aarch64

# Remove everything built and generated including downloaded dependencies.
.PHONY: distclean
distclean: clean
	rm -rf freestnd-c-hdrs cc-runtime c/flanterm c/nanoprintf* c/uacpi uacpi-repository c/lwip lwip-repository

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
