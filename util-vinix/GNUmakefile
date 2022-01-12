# GNUmakefile: Makefile of the project.
# Copyright (C) 2022 streaksu
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# Flags for the user to customize and replace.
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
