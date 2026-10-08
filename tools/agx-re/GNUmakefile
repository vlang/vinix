CC := xcrun clang
CFLAGS := -O2 -Wall -Wextra -Werror
BUILD := build
V_ARCH ?= $(if $(filter arm64,$(shell uname -m)),arm64,amd64)

.PHONY: report-g13-initdata-layout all firmware pmp-firmware inspect kernel-kexts recover-t6050-power recover-t8103-adt g13g-kexts generate-g13-initdata-layout check-g13-initdata-layout check-g13-reference recover-g17-abi generate-g17-power-model check-g17-power-model generate-fake-g17-encoder check-fake-g17-encoder layout test test-trace-v trace trace-resources trace-depth-resources trace-stencil-resources clean
all: $(BUILD)/agx_trace.dylib $(BUILD)/metal_triangle $(BUILD)/objc_layout

test-trace-v:
	python3 ../../tests/agx-trace/run.py

$(BUILD):
	mkdir -p $@

$(BUILD)/agx_trace_core.c: tracecore/core.v compile-v-trace.py | $(BUILD)
	python3 compile-v-trace.py $@ --arch $(V_ARCH)

$(BUILD)/agx_trace_core.o: $(BUILD)/agx_trace_core.c agx_trace_v.h
	$(CC) $(CFLAGS) -DVINIX_V_RUNTIME -I. -c $< -o $@

$(BUILD)/agx_trace_native.c: nativecore/core.v ../../build-support/compile-v-module.py | $(BUILD)
	python3 ../../build-support/compile-v-module.py nativecore $@ --arch $(V_ARCH)

$(BUILD)/agx_trace_native.o: $(BUILD)/agx_trace_native.c
	$(CC) $(CFLAGS) -Wno-unused-function -Wno-unused-label -Wno-unused-parameter -c $< -o $@

$(BUILD)/agx_trace.dylib: agx_resource_trace.m agx_trace.h agx_trace_v.h $(BUILD)/agx_trace_core.o $(BUILD)/agx_trace_native.o | $(BUILD)
	$(CC) $(CFLAGS) -fobjc-arc -dynamiclib -framework Foundation -framework IOKit \
		-F/System/Library/PrivateFrameworks -framework IOGPU -Wl,-u,_vagt_interpose_table -o $@ \
		agx_resource_trace.m $(BUILD)/agx_trace_core.o $(BUILD)/agx_trace_native.o

$(BUILD)/metal_triangle: metal_triangle.m | $(BUILD)
	$(CC) $(CFLAGS) -fobjc-arc -framework Foundation -framework Metal -o $@ $<

$(BUILD)/objc_layout: objc_layout.m | $(BUILD)
	$(CC) $(CFLAGS) -fobjc-arc -framework Foundation -framework Metal -o $@ $<

inspect:
	./inspect_macos.py

firmware:
	./extract_firmware

pmp-firmware:
	./extract_pmp_firmware

kernel-kexts:
	./extract_fileset

recover-t6050-power: kernel-kexts pmp-firmware
	./recover_t6050_power.py

# The base-M1 GPU driver and DeviceTree ship on every Mac, staged under Preboot
# for restore, so this needs no M1 to run.
g13g-kexts:
	./extract_fileset --platform mac13g --output build/kext/g13g \
		--entry com.apple.AGXG13G --entry com.apple.AGXFirmwareKextG13GRTBuddy

recover-t8103-adt: g13g-kexts
	./recover_t8103_adt.py > $(BUILD)/recovered-t8103-adt.json.tmp
	mv $(BUILD)/recovered-t8103-adt.json.tmp $(BUILD)/recovered-t8103-adt.json

recover-g17-abi: firmware kernel-kexts
	./recover_g17_abi.py > $(BUILD)/recovered-g17-abi.json.tmp
	mv $(BUILD)/recovered-g17-abi.json.tmp $(BUILD)/recovered-g17-abi.json

# The 13.5 firmware ABI layout, computed from m1n1's versioned definitions.
# Needs the m1n1 checkout: git clone https://github.com/AsahiLinux/m1n1 ~/code/3rd/m1n1
generate-g13-initdata-layout:
	./generate_g13_initdata_layout

check-g13-initdata-layout:
	./generate_g13_initdata_layout --check

# Compare the contracts that have caused hardware-only failures against the
# reverse-engineered m1n1 source. Set ASAHI_LINUX to include its MMU ordering.
check-g13-reference: check-g13-initdata-layout
	./check_g13_reference_contract $(if $(ASAHI_LINUX),--asahi-linux "$(ASAHI_LINUX)")

report-g13-initdata-layout:
	./generate_g13_initdata_layout --report

generate-g17-power-model:
	./generate_g17_power_model

check-g17-power-model:
	./generate_g17_power_model --check

generate-fake-g17-encoder:
	./generate_fake_g17_3d_encoder

check-fake-g17-encoder:
	./generate_fake_g17_3d_encoder --check

test:
	python3 -m unittest -v test_inspect_macos.py \
		test_recover_t6050_power.py test_recover_t8103_adt.py \
		test_recover_g17_abi.py
	. ../../build-support/find-v.sh; "$$V" -cc cc test g13layout g13contract traceanalysis imageextract g17plan g17decode g17power appleadt

layout: all
	$(CURDIR)/$(BUILD)/objc_layout > $(BUILD)/objc_layout.jsonl

trace: all
	rm -f $(BUILD)/agx_trace.jsonl
	AGX_TRACE_FILE=$(CURDIR)/$(BUILD)/agx_trace.jsonl \
		AGX_TRACE_BYTES=16384 \
		DYLD_INSERT_LIBRARIES=$(CURDIR)/$(BUILD)/agx_trace.dylib \
		$(CURDIR)/$(BUILD)/metal_triangle pair
	./trace_diff $(BUILD)/agx_trace.jsonl

trace-resources: all
	rm -f $(BUILD)/agx_trace_resources.jsonl
	AGX_TRACE_FILE=$(CURDIR)/$(BUILD)/agx_trace_resources.jsonl \
		AGX_TRACE_BYTES=65536 \
		AGX_TRACE_RESOURCES=1 \
		DYLD_INSERT_LIBRARIES=$(CURDIR)/$(BUILD)/agx_trace.dylib \
		$(CURDIR)/$(BUILD)/metal_triangle pair
	./trace_diff $(BUILD)/agx_trace_resources.jsonl

trace-depth-resources: all
	rm -f $(BUILD)/agx_trace_depth_resources.jsonl
	AGX_TRACE_FILE=$(CURDIR)/$(BUILD)/agx_trace_depth_resources.jsonl \
		AGX_TRACE_BYTES=65536 \
		AGX_TRACE_RESOURCES=1 \
		DYLD_INSERT_LIBRARIES=$(CURDIR)/$(BUILD)/agx_trace.dylib \
		$(CURDIR)/$(BUILD)/metal_triangle depth-pair
	./trace_diff $(BUILD)/agx_trace_depth_resources.jsonl \
		--left depth-clear --right depth-triangle

trace-stencil-resources: all
	rm -f $(BUILD)/agx_trace_stencil_resources.jsonl
	AGX_TRACE_FILE=$(CURDIR)/$(BUILD)/agx_trace_stencil_resources.jsonl \
		AGX_TRACE_BYTES=65536 \
		AGX_TRACE_RESOURCES=1 \
		DYLD_INSERT_LIBRARIES=$(CURDIR)/$(BUILD)/agx_trace.dylib \
		$(CURDIR)/$(BUILD)/metal_triangle stencil-pair
	./trace_diff $(BUILD)/agx_trace_stencil_resources.jsonl \
		--left stencil-clear --right stencil-triangle

clean:
	rm -rf $(BUILD)
