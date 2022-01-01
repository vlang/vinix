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
override FETCH_DIR    := fetch
override FETCH_TARGET := $(FETCH_DIR)/fetch
override MOUNT_DIR    := mount
override MOUNT_TARGET := $(MOUNT_DIR)/mount
override SHARED_DIR   := $(realpath shared_utils)

.PHONY: all clean install

all: $(FETCH_TARGET) $(MOUNT_TARGET)

$(FETCH_TARGET):
	cd $(FETCH_DIR) && VMODULES=$(SHARED_DIR) $(V) $(VFLAGS) -cc $(CC) -os vinix .

$(MOUNT_TARGET):
	cd $(MOUNT_DIR) && VMODULES=$(SHARED_DIR) $(V) $(VFLAGS) -cc $(CC) -os vinix .

clean:
	rm -rf $(FETCH_TARGET) $(MOUNT_TARGET)

install:
	install -d "$(DESTDIR)$(PREFIX)/bin"
	install -s $(FETCH_TARGET) "$(DESTDIR)$(PREFIX)/bin/"
	install -s $(MOUNT_TARGET) "$(DESTDIR)$(PREFIX)/bin/"
