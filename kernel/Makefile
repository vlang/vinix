KERNEL := vinix.elf

CC = cc
V = v

CFLAGS = -O2 -Wall -Wextra -g -pipe -w

INTERNALCFLAGS :=           \
	-I.                     \
	-ffreestanding          \
	-fno-omit-frame-pointer \
	-fno-stack-protector    \
	-fno-pic -fpie          \
	-ffunction-sections     \
	-fdata-sections         \
	-fno-inline             \
	-fwhole-program         \
	-mno-80387              \
	-mno-mmx                \
	-mno-3dnow              \
	-mno-sse                \
	-mno-sse2               \
	-mno-red-zone           \
	-static-pie             \
	-nostdlib               \
	-Tlinker.ld             \
	-Wno-address-of-packed-member \
	-Wno-unused-label       \
	-Wno-unused-function    \
	-Wno-unused-variable    \
	-Wno-unused-parameter   \
	-Wl,-gc-sections        \
	-z max-page-size=0x1000

INTERNALVFLAGS :=   \
	-enable-globals \
	-d no_backtrace \
	-autofree

VFILES := $(shell find ./ -type f -name '*.v' | sort)
CFILES := $(shell find ./ -type f -name '*.c' | sort)

.PHONY: all
all: $(KERNEL)

.PHONY:
clean:
	rm -rf $(KERNEL) blob

$(KERNEL): $(VFILES) $(CFILES)
	$(V) $(VFLAGS) $(INTERNALVFLAGS) -o vblob.c .
	printf '#define double int\n#define float int\n' \
		| cat - vblob.c $(CFILES) \
		| sed 's/void main__kmain(/__attribute__((externally_visible)) void main__kmain(/g' \
		> blob
	rm vblob.c
	$(CC) -x c $(CFLAGS) $(INTERNALCFLAGS) blob -o $@
