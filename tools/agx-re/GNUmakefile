CC := xcrun clang
CFLAGS := -O2 -Wall -Wextra -Werror
BUILD := build

.PHONY: all firmware inspect kernel-kexts layout test trace trace-resources clean
all: $(BUILD)/agx_trace.dylib $(BUILD)/metal_triangle $(BUILD)/objc_layout

$(BUILD):
	mkdir -p $@

$(BUILD)/agx_trace.dylib: agx_trace.c agx_resource_trace.m agx_trace.h | $(BUILD)
	$(CC) $(CFLAGS) -fobjc-arc -dynamiclib -framework Foundation -framework IOKit \
		-F/System/Library/PrivateFrameworks -framework IOGPU -o $@ \
		agx_trace.c agx_resource_trace.m

$(BUILD)/metal_triangle: metal_triangle.m | $(BUILD)
	$(CC) $(CFLAGS) -fobjc-arc -framework Foundation -framework Metal -o $@ $<

$(BUILD)/objc_layout: objc_layout.m | $(BUILD)
	$(CC) $(CFLAGS) -fobjc-arc -framework Foundation -framework Metal -o $@ $<

inspect:
	./inspect_macos.py

firmware:
	./extract_firmware.py

kernel-kexts:
	./extract_fileset.py

test:
	python3 -m unittest -v test_inspect_macos.py test_extract_firmware.py \
		test_extract_fileset.py test_trace_diff.py

layout: all
	$(CURDIR)/$(BUILD)/objc_layout > $(BUILD)/objc_layout.jsonl

trace: all
	rm -f $(BUILD)/agx_trace.jsonl
	AGX_TRACE_FILE=$(CURDIR)/$(BUILD)/agx_trace.jsonl \
		AGX_TRACE_BYTES=16384 \
		DYLD_INSERT_LIBRARIES=$(CURDIR)/$(BUILD)/agx_trace.dylib \
		$(CURDIR)/$(BUILD)/metal_triangle pair
	./trace_diff.py $(BUILD)/agx_trace.jsonl

trace-resources: all
	rm -f $(BUILD)/agx_trace_resources.jsonl
	AGX_TRACE_FILE=$(CURDIR)/$(BUILD)/agx_trace_resources.jsonl \
		AGX_TRACE_BYTES=65536 \
		AGX_TRACE_RESOURCES=1 \
		DYLD_INSERT_LIBRARIES=$(CURDIR)/$(BUILD)/agx_trace.dylib \
		$(CURDIR)/$(BUILD)/metal_triangle pair
	./trace_diff.py $(BUILD)/agx_trace_resources.jsonl

clean:
	rm -rf $(BUILD)
