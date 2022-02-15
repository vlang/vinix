# GNUmakefile: Makefile of the kernel.
# Code is governed by the GPL-2.0 license.
# Copyright (C) 2021-2022 The Vinix authors.

ifeq ($(origin CC), default)
	CC := cc
endif
ifeq ($(origin LD), default)
	LD := ld
endif
OBJDUMP ?= objdump
V       ?= v
CFLAGS  ?= -O2 -Wall -Wextra -g -pipe
LDFLAGS ?=
VFLAGS  ?=
PROD    ?= false

override INTERNALCFLAGS :=        \
	-ffreestanding                \
	-nostdinc                     \
	-fno-omit-frame-pointer       \
	-fno-stack-protector          \
	-fno-pic                      \
	-ffunction-sections           \
	-fdata-sections               \
	-fno-strict-aliasing          \
	-mno-80387                    \
	-mno-mmx                      \
	-mno-3dnow                    \
	-mno-sse                      \
	-mno-sse2                     \
	-mno-red-zone                 \
	-mcmodel=kernel               \
	-Wno-address-of-packed-member \
	-Wno-unused-value             \
	-Wno-unused-label             \
	-Wno-unused-function          \
	-Wno-unused-variable          \
	-Wno-unused-parameter

override INTERNALLDFLAGS :=  \
	-Tlinker.ld              \
	-nostdlib                \
	-zmax-page-size=0x200000 \
	-static                  \
	-gc-sections

override INTERNALVFLAGS := \
	-os vinix              \
	-enable-globals        \
	-nofloat               \
	-autofree              \
	-d no_backtrace

ifeq ($(PROD), true)
	override INTERNALVFLAGS += -prod
	override INTERNALCFLAGS += -DPROD
endif

override KERNEL := vinix.elf
override VFILES := $(shell find ./ -type f -name '*.v')
override CFILES := $(shell find ./ -type f -name '*.c')
override SFILES := $(shell find ./ -type f -name '*.S')
override COBJ   := $(CFILES:.c=.o) $(SFILES:.S=.o)

.PHONY: all
all: $(KERNEL)

freestanding_headers:
	git clone https://github.com/mintsuki/freestanding_headers.git

.PHONY: clean
clean:
	rm -rf $(KERNEL) $(COBJ) blob.o blob.c

.PHONY: install
install:
	install -d "$(DESTDIR)$(PREFIX)"
	install -s $(KERNEL) "$(DESTDIR)$(PREFIX)/"

blob.o: $(VFILES) freestanding_headers
	VMODULES=/tmp/.vmodules $(V) $(VFLAGS) $(INTERNALVFLAGS) -o blob.c .
	$(CC) -Ifreestanding_headers -Ic $(CFLAGS) $(INTERNALCFLAGS) -w -c blob.c -o $@

%.o: %.c freestanding_headers
	$(CC) -Ifreestanding_headers -Ic $(CFLAGS) $(INTERNALCFLAGS) -c $< -o $@

%.o: %.S freestanding_headers
	$(CC) -Ifreestanding_headers -Ic $(CFLAGS) $(INTERNALCFLAGS) -c $< -o $@

$(KERNEL): blob.o $(COBJ) freestanding_headers
	$(LD) blob.o $(COBJ) $(LDFLAGS) $(INTERNALLDFLAGS) -o $@
	mv c/symbol_table.c symbol_table.c.tmp
	./gensyms.sh $(OBJDUMP) $@ > c/symbol_table.c
	$(CC) -Ifreestanding_headers -Ic $(CFLAGS) $(INTERNALCFLAGS) -c c/symbol_table.c -o c/symbol_table.o
	$(LD) blob.o $(COBJ) $(LDFLAGS) $(INTERNALLDFLAGS) -o $@
	mv symbol_table.c.tmp c/symbol_table.c
