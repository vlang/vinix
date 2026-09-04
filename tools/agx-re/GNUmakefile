CC := xcrun clang
CFLAGS := -O2 -Wall -Wextra -Werror
BUILD := build

.PHONY: all inspect test trace clean
all: $(BUILD)/agx_trace.dylib $(BUILD)/metal_triangle

$(BUILD):
	mkdir -p $@

$(BUILD)/agx_trace.dylib: agx_trace.c | $(BUILD)
	$(CC) $(CFLAGS) -dynamiclib -framework IOKit -o $@ $<

$(BUILD)/metal_triangle: metal_triangle.m | $(BUILD)
	$(CC) $(CFLAGS) -fobjc-arc -framework Foundation -framework Metal -o $@ $<

inspect:
	./inspect_macos.py

test:
	python3 -m unittest -v test_inspect_macos.py

trace: all
	rm -f $(BUILD)/agx_trace.jsonl
	AGX_TRACE_FILE=$(CURDIR)/$(BUILD)/agx_trace.jsonl \
		DYLD_INSERT_LIBRARIES=$(CURDIR)/$(BUILD)/agx_trace.dylib \
		$(CURDIR)/$(BUILD)/metal_triangle

clean:
	rm -rf $(BUILD)
