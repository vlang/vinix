KERNEL := vinix.elf

PROD = false

CC = cc
LD = ld
OBJDUMP = objdump
V = v

CFLAGS = -O2 -Wall -Wextra -g -pipe
LDFLAGS =
VFLAGS =

INTERNALCFLAGS :=                 \
	-ffreestanding                \
	-fno-omit-frame-pointer       \
	-fno-stack-protector          \
	-fpie                         \
	-ffunction-sections           \
	-fdata-sections               \
	-mno-80387                    \
	-mno-mmx                      \
	-mno-3dnow                    \
	-mno-sse                      \
	-mno-sse2                     \
	-mno-red-zone                 \
	-Wno-address-of-packed-member \
	-Wno-unused-label             \
	-Wno-unused-function          \
	-Wno-unused-variable          \
	-Wno-unused-parameter

INTERNALLDFLAGS :=         \
	-Tlinker.ld            \
	-nostdlib              \
	-zmax-page-size=0x200000 \
	-static                \
	-pie                   \
	--no-dynamic-linker    \
	-ztext                 \
	-gc-sections

INTERNALVFLAGS :=   \
	-os vinix       \
	-enable-globals \
	-nofloat        \
	-autofree       \
	-d no_backtrace

ifeq ($(PROD), true)
	INTERNALVFLAGS += -prod
	INTERNALCFLAGS += -DPROD
endif

VFILES := $(shell find ./ -type f -name '*.v')
CFILES := $(shell find ./ -type f -name '*.c')
SFILES := $(shell find ./ -type f -name '*.S')
COBJ   := $(CFILES:.c=.o) $(SFILES:.S=.o)

.PHONY: all
all: $(KERNEL)

.PHONY: clean
clean:
	rm -rf $(KERNEL) $(COBJ) blob.o blob.c

.PHONY: install
install:
	install -d "$(DESTDIR)$(PREFIX)"
	install -s $(KERNEL) "$(DESTDIR)$(PREFIX)/"

blob.o: $(VFILES)
	VMODULES=/tmp/.vmodules $(V) $(VFLAGS) $(INTERNALVFLAGS) -o blob.c .
	$(CC) -I./c $(CFLAGS) $(INTERNALCFLAGS) -w -c blob.c -o $@

%.o: %.c
	$(CC) -I./c $(CFLAGS) $(INTERNALCFLAGS) -c $< -o $@

%.o: %.S
	$(CC) -I./c $(CFLAGS) $(INTERNALCFLAGS) -c $< -o $@

$(KERNEL): blob.o $(COBJ)
	$(LD) $^ $(LDFLAGS) $(INTERNALLDFLAGS) -o $@
	mv c/symbol_table.c symbol_table.c.tmp
	./gensyms.sh $(OBJDUMP) $@ > c/symbol_table.c
	$(CC) $(CFLAGS) $(INTERNALCFLAGS) -c c/symbol_table.c -o c/symbol_table.o
	$(LD) $^ $(LDFLAGS) $(INTERNALLDFLAGS) -o $@
	mv symbol_table.c.tmp c/symbol_table.c
