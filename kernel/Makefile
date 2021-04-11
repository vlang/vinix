TARGET := vos.elf

CC = cc
V = v

CFLAGS = -O3 -pipe

LDINTERNALFLAGS :=  \
	-Tlinker.ld \
	-nostdlib   \
	-Wl,-gc-sections \
	-static-pie     \
	-pie -fno-pic -fpie \
	-flto \
	-z max-page-size=0x1000

INTERNALCFLAGS  :=       \
	-I.                  \
	-flto                \
	-ffreestanding       \
	-fno-stack-protector \
	-fno-pic -fpie       \
	-ffunction-sections  \
	-fdata-sections      \
	-mgeneral-regs-only  \
	-mno-red-zone

INTERNALVFLAGS := \
	-shared \
	--enable-globals

VFILES := $(shell find ./ -type f -name '*.v')
ASMFILES := $(shell find ./ -type f -name '*.asm')
CFILES := $(shell find ./ -type f -name '*.c')
OBJ := $(ASMFILES:.asm=.o) $(CFILES:.c=.o) blob.o

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJ)
	$(CC) $(LDINTERNALFLAGS) $(OBJ) -o $@

blob.o: blob.C
	$(CC) -w -x c $(CFLAGS) $(INTERNALCFLAGS) -c $< -o $@

%.o: %.c
	$(CC) -Wall -Wextra $(CFLAGS) $(INTERNALCFLAGS) -c $< -o $@

%.o: %.asm
	nasm $< -felf64 -o $@

blob.C: $(VFILES)
	$(V) $(VFLAGS) $(INTERNALVFLAGS) -o $(@:.C=.c) .
	printf '#define double int\n#define float int\n' | cat - $(@:.C=.c) > $@
	rm $(@:.C=.c)

clean:
	rm -rf $(TARGET) $(OBJ) blob.C
