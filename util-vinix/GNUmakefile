# GNUmakefile: Makefile of util-vinix.
# Code is governed by the GPL-2.0 license.
# Copyright (C) 2021-2022 The Vinix authors.

ifeq ($(origin CC), default)
	CC := cc
endif
V       ?= v
PROD    ?= false
VFLAGS  ?= -gc none
CFLAGS  ?= -O2 -pipe -g
PREFIX  ?= /usr/local

ifeq ($(PROD), true)
	override VFLAGS += -prod
endif

# Targets and their rules.
override CHSH_DIR     := chsh
override CHSH_TARGET  := $(CHSH_DIR)/chsh
override FETCH_DIR    := fetch
override FETCH_TARGET := $(FETCH_DIR)/fetch
override LSCPU_DIR    := lscpu
override LSCPU_TARGET := $(LSCPU_DIR)/lscpu
override MOUNT_DIR    := mount
override MOUNT_TARGET := $(MOUNT_DIR)/mount

.PHONY: all clean install

all: $(CHSH_TARGET) $(FETCH_TARGET) $(LSCPU_TARGET) $(MOUNT_TARGET)

$(CHSH_TARGET): $(CHSH_DIR)/*
	while ! ( cd $(CHSH_DIR) && VCROSS_COMPILER_NAME="$(CC)" $(V) $(VFLAGS) -cflags "$(CFLAGS)" -os vinix . ); do \
		true; \
	done

$(FETCH_TARGET): $(FETCH_DIR)/*
	while ! ( cd $(FETCH_DIR) && VCROSS_COMPILER_NAME="$(CC)" $(V) $(VFLAGS) -cflags "$(CFLAGS)" -os vinix . ); do \
		true; \
	done

$(LSCPU_TARGET): $(LSCPU_DIR)/*
	while ! ( cd $(LSCPU_DIR) && VCROSS_COMPILER_NAME="$(CC)" $(V) $(VFLAGS) -cflags "$(CFLAGS)" -os vinix . ); do \
		true; \
	done

$(MOUNT_TARGET): $(MOUNT_DIR)/*
	while ! ( cd $(MOUNT_DIR) && VCROSS_COMPILER_NAME="$(CC)" $(V) $(VFLAGS) -cflags "$(CFLAGS)" -os vinix . ); do \
		true; \
	done

clean:
	rm -rf $(CHSH_TARGET) $(FETCH_TARGET) $(LSCPU_TARGET) $(MOUNT_TARGET)

install:
	install -d "$(DESTDIR)$(PREFIX)/bin"
	install -s --strip-program=x86_64-vinix-strip $(CHSH_TARGET)  "$(DESTDIR)$(PREFIX)/bin/"
	install -s --strip-program=x86_64-vinix-strip $(FETCH_TARGET) "$(DESTDIR)$(PREFIX)/bin/"
	install -s --strip-program=x86_64-vinix-strip $(LSCPU_TARGET) "$(DESTDIR)$(PREFIX)/bin/"
	install -s --strip-program=x86_64-vinix-strip $(MOUNT_TARGET) "$(DESTDIR)$(PREFIX)/bin/"
