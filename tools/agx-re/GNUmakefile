CC := xcrun clang
CFLAGS := -O2 -Wall -Wextra -Werror
BUILD := build

.PHONY: all firmware pmp-firmware inspect kernel-kexts recover-t6050-power recover-g17-abi generate-g17-power-model check-g17-power-model generate-fake-g17-encoder check-fake-g17-encoder layout test trace trace-resources trace-depth-resources clean
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

pmp-firmware:
	./extract_pmp_firmware.py

kernel-kexts:
	./extract_fileset.py

recover-t6050-power: kernel-kexts pmp-firmware
	./recover_t6050_power.py

recover-g17-abi: firmware kernel-kexts
	./recover_g17_abi.py > $(BUILD)/recovered-g17-abi.json.tmp
	mv $(BUILD)/recovered-g17-abi.json.tmp $(BUILD)/recovered-g17-abi.json

generate-g17-power-model:
	./generate_g17_power_model.py

check-g17-power-model:
	./generate_g17_power_model.py --check

generate-fake-g17-encoder:
	./generate_fake_g17_3d_encoder.py

check-fake-g17-encoder:
	./generate_fake_g17_3d_encoder.py --check

test:
	python3 -m unittest -v test_inspect_macos.py test_extract_firmware.py \
		test_extract_pmp_firmware.py test_extract_fileset.py \
		test_recover_t6050_power.py test_recover_g17_abi.py \
		test_generate_g17_power_model.py \
		test_generate_fake_g17_3d_encoder.py \
		test_compile_fake_g17_plan.py \
		test_map_g17_resource_descriptors.py \
		test_trace_diff.py

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

trace-depth-resources: all
	rm -f $(BUILD)/agx_trace_depth_resources.jsonl
	AGX_TRACE_FILE=$(CURDIR)/$(BUILD)/agx_trace_depth_resources.jsonl \
		AGX_TRACE_BYTES=65536 \
		AGX_TRACE_RESOURCES=1 \
		DYLD_INSERT_LIBRARIES=$(CURDIR)/$(BUILD)/agx_trace.dylib \
		$(CURDIR)/$(BUILD)/metal_triangle depth-pair
	./trace_diff.py $(BUILD)/agx_trace_depth_resources.jsonl \
		--left depth-clear --right depth-triangle

clean:
	rm -rf $(BUILD)
