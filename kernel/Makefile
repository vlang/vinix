TARGET := vos.elf

CC = cc
V = v

CFLAGS = -O2 -pipe

INTERNALCFLAGS  :=       \
	-I.                  \
	-ffreestanding       \
	-fno-omit-frame-pointer \
	-fno-stack-protector \
	-pie -static-pie     \
	-fno-pic -fpie       \
	-ffunction-sections  \
	-fdata-sections      \
	-mgeneral-regs-only  \
	-mno-red-zone        \
	-fwhole-program      \
	-Tlinker.ld          \
	-nostdlib            \
	-Wl,-gc-sections     \
	-z max-page-size=0x1000

INTERNALVFLAGS := \
	-shared \
	--enable-globals

VFILES := $(shell find ./ -type f -name '*.v')
CFILES := $(shell find ./ -type f -name '*.c')

.PHONY: all
all: $(TARGET)

.PHONY:
clean:
	rm -rf $(TARGET) $(OBJ) blob.C

$(TARGET): blob.C
	$(CC) -x c $(CFLAGS) $(INTERNALCFLAGS) $< -o $@

blob.C: $(VFILES) $(CFILES)
	$(V) $(VFLAGS) $(INTERNALVFLAGS) -o blob.c .
	printf '#define double int\n#define float int\n' \
		| cat - blob.c $(CFILES) \
		| sed 's/void main__kmain(/__attribute__((externally_visible)) void main__kmain(/g' \
		> blob.C
	rm blob.c
