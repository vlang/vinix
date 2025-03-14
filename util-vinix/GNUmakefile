MAKEFLAGS += -rR
.SUFFIXES:

override USER_VARIABLE = $(if $(filter $(origin $(1)),default undefined),$(eval override $(1) := $(2)))

$(call USER_VARIABLE,CC,cc)
$(call USER_VARIABLE,V,v)

$(call USER_VARIABLE,VFLAGS,)
$(call USER_VARIABLE,CFLAGS,-g -O2 -pipe)
$(call USER_VARIABLE,LDFLAGS,)

$(call USER_VARIABLE,DESTDIR,)
$(call USER_VARIABLE,PREFIX,/usr/local)

$(call USER_VARIABLE,PROD,)

ifeq ($(PROD),true)
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
	cd $(CHSH_DIR) && VCROSS_COMPILER_NAME="$(CC)" $(V) $(VFLAGS) -cflags "$(CFLAGS)" -ldflags "$(LDFLAGS)" .

$(FETCH_TARGET): $(FETCH_DIR)/*
	cd $(FETCH_DIR) && VCROSS_COMPILER_NAME="$(CC)" $(V) $(VFLAGS) -cflags "$(CFLAGS)" -ldflags "$(LDFLAGS)" .

$(LSCPU_TARGET): $(LSCPU_DIR)/*
	cd $(LSCPU_DIR) && VCROSS_COMPILER_NAME="$(CC)" $(V) $(VFLAGS) -cflags "$(CFLAGS)" -ldflags "$(LDFLAGS)" .

$(MOUNT_TARGET): $(MOUNT_DIR)/*
	cd $(MOUNT_DIR) && VCROSS_COMPILER_NAME="$(CC)" $(V) $(VFLAGS) -cflags "$(CFLAGS)" -ldflags "$(LDFLAGS)" .

clean:
	rm -rf $(CHSH_TARGET) $(FETCH_TARGET) $(LSCPU_TARGET) $(MOUNT_TARGET)

install:
	install -d "$(DESTDIR)$(PREFIX)/bin"
	install $(CHSH_TARGET)  "$(DESTDIR)$(PREFIX)/bin/"
	install $(FETCH_TARGET) "$(DESTDIR)$(PREFIX)/bin/"
	install $(LSCPU_TARGET) "$(DESTDIR)$(PREFIX)/bin/"
	install $(MOUNT_TARGET) "$(DESTDIR)$(PREFIX)/bin/"
