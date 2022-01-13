# GNUmakefile: Makefile of util-vinix.
# Code is governed by the GPL-2.0 license.
# Copyright (C) 2021-2022 The Vinix authors.

ifeq ($(origin CC), default)
	CC := cc
endif
V       ?= v
PROD    ?= false
VFLAGS  ?=
PREFIX  ?= /usr/local

ifeq ($(PROD), true)
	VFLAGS += -prod
endif

# Targets and their rules.
override CHSH_DIR     := chsh
override CHSH_TARGET  := $(CHSH_DIR)/chsh
override FETCH_DIR    := fetch
override FETCH_TARGET := $(FETCH_DIR)/fetch
override SHARED_DIR   := $(realpath shared_utils)

.PHONY: all clean install

all: $(CHSH_TARGET) $(FETCH_TARGET)

$(CHSH_TARGET): $(CHSH_DIR)/* $(SHARED_DIR)/*
	cd $(CHSH_DIR) && VMODULES=$(SHARED_DIR) $(V) $(VFLAGS) -cc $(CC) -os vinix .

$(FETCH_TARGET): $(FETCH_DIR)/* $(SHARED_DIR)/*
	cd $(FETCH_DIR) && VMODULES=$(SHARED_DIR) $(V) $(VFLAGS) -cc $(CC) -os vinix .

clean:
	rm -rf $(CHSH_TARGET) $(FETCH_TARGET)

install:
	install -d "$(DESTDIR)$(PREFIX)/bin"
	install -s $(CHSH_TARGET)  "$(DESTDIR)$(PREFIX)/bin/"
	install -s $(FETCH_TARGET) "$(DESTDIR)$(PREFIX)/bin/"
