@[has_globals]
module driver

// Top-level GPU driver probe and registration
// Discovers the Apple AGX GPU from the device tree, initializes all
// subsystems (UAT, channels, firmware, RTKit), creates the
// GpuManager, and registers a DRM driver with GEM, render, and compute
// capabilities.
import gpu.agx.gpu
import gpu.agx.hw
import gpu.agx.regs
import gpu.agx.mmu
import gpu.agx.pgtable
import gpu.agx.power as agx_power
import gpu.agx.fw
import gpu.agx.file as agx_file
import gpu.dcp
import drm
import drm.ioctl as drm_ioctl
import apple.rtkit
import devicetree
import aarch64.pmgr

pub struct AgxDriver {
pub mut:
	gpu         &gpu.GpuManager = unsafe { nil }
	dcp         &dcp.AppleDCP = unsafe { nil }
	drm_dev     &drm.DrmDevice = unsafe { nil }
	hw_config   hw.HwConfig
	detected    bool
	initialized bool
}

__global (
	agx_driver_inst AgxDriver
)

struct PlatformResources {
pub:
	asc_base               u64
	asc_size               u64
	secondary_asc_base     u64
	secondary_asc_size     u64
	sgx_base               u64
	sgx_size               u64
	mailbox_base           u64
	secondary_mailbox_base u64
	firmware_role_count    u32
	handoff_base           u64
	handoff_size           u64
	pagetables_base        u64
	pagetables_size        u64
	ttbs_base              u64
	ttbs_size              u64
}

fn find_gpu_node() ?(&devicetree.DTNode, u32, bool) {
	// Apple DeviceTree uses gpu,tXXXX. Linux names GPU generations rather
	// than SoCs (G13G is the base M1 GPU), while older downstream trees used
	// apple,agx-tXXXX. Retain all three spellings so a current m1n1 FDT boots
	// without requiring a Vinix-specific device-tree edit.
	if node := devicetree.find_compatible('gpu,t6050') {
		return node, u32(0x6050), true
	}
	if node := devicetree.find_compatible('apple,agx-t6050') {
		return node, u32(0x6050), false
	}
	if node := devicetree.find_compatible('gpu,t8103') {
		return node, u32(0x8103), true
	}
	if node := devicetree.find_compatible('apple,agx-g13g') {
		return node, u32(0x8103), false
	}
	if node := devicetree.find_compatible('apple,agx-t8103') {
		return node, u32(0x8103), false
	}
	return none
}

fn find_native_asc_node(role u32) ?&devicetree.DTNode {
	name := if role == 0 { 'gfx-asc' } else { 'gfx1-asc' }
	if node := devicetree.find_node('/arm-io/${name}') {
		return node
	}
	if node := devicetree.find_node('/soc/${name}') {
		return node
	}
	return none
}

fn validate_g13_firmware_compat(gpu_node &devicetree.DTNode, native_adt bool) bool {
	// m1n1 patches apple,firmware-abi with the negotiated tuple as standard
	// big-endian FDT cells. Native Apple DeviceTree does not expose this Linux
	// property, so there is nothing to check the loaded firmware against and
	// this returns false rather than deferring to a later gate: whoever
	// implements the native ADT path has to supply the ABI tuple here too.
	// Accept the old Vinix property as a compatibility aid, but prefer the
	// property used by current m1n1/Linux device trees.
	if native_adt {
		println('agx: native t8103 boot data carries no firmware ABI tuple')
		return false
	}
	mut property_name := 'apple,firmware-abi'
	compat := devicetree.get_u32_array(gpu_node, property_name) or {
		property_name = 'apple,firmware-compat'
		devicetree.get_u32_array(gpu_node, property_name) or {
			println('agx: t8103 device tree has no apple,firmware-abi')
			return false
		}
	}
	if compat.len != 3 {
		println('agx: malformed t8103 ${property_name} tuple')
		return false
	}
	println('agx: t8103 ${property_name} ${compat[0]}.${compat[1]}.${compat[2]}')
	if compat[0] != 12 || compat[1] != 3 || compat[2] != 0 {
		println('agx: only the G13 12.3.0 firmware ABI is being implemented')
		return false
	}
	return true
}

fn load_fdt_firmware_version(gpu_node &devicetree.DTNode, native_adt bool,
	mut cfg hw.HwConfig) {
	if native_adt {
		return
	}
	version := devicetree.get_u32_array(gpu_node, 'apple,firmware-version') or { return }
	if version.len > cfg.firmware_version.len {
		println('agx: ignoring malformed firmware version tuple')
		return
	}
	for index := 0; index < version.len; index++ {
		cfg.firmware_version[index] = version[index]
	}
}

fn get_platform_resources(gpu_node &devicetree.DTNode, native_adt bool,
	chip_id u32) ?PlatformResources {
	gpu_regs := devicetree.get_translated_reg_ranges(gpu_node) or {
		println('agx: failed to translate GPU register ranges')
		return none
	}
	if native_adt {
		if gpu_regs.len == 0 {
			println('agx: native SGX node has no registers')
			return none
		}
		asc_node := find_native_asc_node(0) or {
			println('agx: native gfx-asc node not found')
			return none
		}
		asc_regs := devicetree.get_translated_reg_ranges(asc_node) or {
			println('agx: failed to translate native gfx-asc registers')
			return none
		}
		if asc_regs.len == 0 || asc_regs[0].size < 0x9000 {
			println('agx: native gfx-asc register window is incomplete')
			return none
		}
		mut secondary_asc_base := u64(0)
		mut secondary_asc_size := u64(0)
		mut secondary_mailbox_base := u64(0)
		mut firmware_role_count := u32(1)
		if chip_id == 0x6050 {
			secondary_node := find_native_asc_node(1) or {
				println('agx: native G17 gfx1-asc node not found')
				return none
			}
			secondary_regs := devicetree.get_translated_reg_ranges(secondary_node) or {
				println('agx: failed to translate native gfx1-asc registers')
				return none
			}
			if secondary_regs.len == 0 || secondary_regs[0].size < 0x9000 {
				println('agx: native gfx1-asc register window is incomplete')
				return none
			}
			secondary_asc_base = secondary_regs[0].base
			secondary_asc_size = secondary_regs[0].size
			secondary_mailbox_base = secondary_regs[0].base + 0x8000
			firmware_role_count = 2
		}
		ttbs_base := devicetree.get_le_u64(gpu_node, 'gpu-region-base') or {
			println('agx: native SGX node has no gpu-region-base')
			return none
		}
		ttbs_size := devicetree.get_le_u64(gpu_node, 'gpu-region-size') or {
			println('agx: native SGX node has no gpu-region-size')
			return none
		}
		handoff_base := devicetree.get_le_u64(gpu_node, 'gfx-handoff-base') or {
			println('agx: native SGX node has no gfx-handoff-base')
			return none
		}
		handoff_size := devicetree.get_le_u64(gpu_node, 'gfx-handoff-size') or {
			println('agx: native SGX node has no gfx-handoff-size')
			return none
		}
		pagetables_base := devicetree.get_le_u64(gpu_node, 'gfx-shared-region-base') or {
			println('agx: native SGX node has no gfx-shared-region-base')
			return none
		}
		pagetables_size := devicetree.get_le_u64(gpu_node, 'gfx-shared-region-size') or {
			println('agx: native SGX node has no gfx-shared-region-size')
			return none
		}
		return PlatformResources{
			asc_base: asc_regs[0].base
			asc_size: asc_regs[0].size
			secondary_asc_base: secondary_asc_base
			secondary_asc_size: secondary_asc_size
			sgx_base: gpu_regs[0].base
			sgx_size: gpu_regs[0].size
			mailbox_base: asc_regs[0].base + 0x8000
			secondary_mailbox_base: secondary_mailbox_base
			firmware_role_count: firmware_role_count
			handoff_base: handoff_base
			handoff_size: handoff_size
			pagetables_base: pagetables_base
			pagetables_size: pagetables_size
			ttbs_base: ttbs_base
			ttbs_size: ttbs_size
		}
	}

	asc := devicetree.get_named_reg(gpu_node, 'asc') or {
		if gpu_regs.len < 1 {
			println('agx: GPU node has no ASC register range')
			return none
		}
		gpu_regs[0]
	}
	sgx := devicetree.get_named_reg(gpu_node, 'sgx') or {
		if gpu_regs.len < 2 {
			println('agx: GPU node has no SGX register range')
			return none
		}
		gpu_regs[1]
	}
	mailbox_node := devicetree.get_phandle_node(gpu_node, 'mboxes', 0) or {
		println('agx: GPU mailbox phandle is missing')
		return none
	}
	mailbox_regs := devicetree.get_translated_reg_ranges(mailbox_node) or {
		println('agx: failed to translate GPU mailbox registers')
		return none
	}
	if mailbox_regs.len == 0 {
		println('agx: GPU mailbox has no register range')
		return none
	}
	ttbs_node := devicetree.get_named_phandle_node(gpu_node, 'memory-region', 'memory-region-names', 'ttbs') or {
		println('agx: GPU TTB reserved-memory region is missing')
		return none
	}
	ttbs_regs := devicetree.get_translated_reg_ranges(ttbs_node) or {
		println('agx: failed to translate GPU TTB region')
		return none
	}
	handoff_node := devicetree.get_named_phandle_node(gpu_node, 'memory-region', 'memory-region-names', 'handoff') or {
		println('agx: GPU handoff reserved-memory region is missing')
		return none
	}
	handoff_regs := devicetree.get_translated_reg_ranges(handoff_node) or {
		println('agx: failed to translate GPU handoff region')
		return none
	}
	pagetables_node := devicetree.get_named_phandle_node(gpu_node, 'memory-region', 'memory-region-names', 'pagetables') or {
		println('agx: GPU page-table reserved-memory region is missing')
		return none
	}
	pagetables_regs := devicetree.get_translated_reg_ranges(pagetables_node) or {
		println('agx: failed to translate GPU page-table region')
		return none
	}
	if ttbs_regs.len == 0 || handoff_regs.len == 0 || pagetables_regs.len == 0 {
		println('agx: GPU reserved-memory region has no address')
		return none
	}
	return PlatformResources{
		asc_base: asc.base
		asc_size: asc.size
		sgx_base: sgx.base
		sgx_size: sgx.size
		mailbox_base: mailbox_regs[0].base
		firmware_role_count: 1
		handoff_base: handoff_regs[0].base
		handoff_size: handoff_regs[0].size
		pagetables_base: pagetables_regs[0].base
		pagetables_size: pagetables_regs[0].size
		ttbs_base: ttbs_regs[0].base
		ttbs_size: ttbs_regs[0].size
	}
}

// Match the three-word record produced by Apple's retrieveChipInfo method.
// These Apple DeviceTree scalar properties are little endian.
fn load_t6050_chip_info(mut cfg hw.HwConfig) bool {
	chosen := devicetree.find_node('/chosen') or {
		println('agx: t6050 has no /chosen node')
		return false
	}
	arm_io := devicetree.find_node('/arm-io') or {
		println('agx: t6050 has no /arm-io node')
		return false
	}
	chip_id := devicetree.get_le_u32(chosen, 'chip-id') or {
		println('agx: t6050 has no chip-id')
		return false
	}
	chip_revision := devicetree.get_le_u32(arm_io, 'chip-revision') or {
		println('agx: t6050 has no chip-revision')
		return false
	}
	if chip_id != cfg.chip_id {
		println('agx: t6050 chip-id mismatch 0x${chip_id:x} != 0x${cfg.chip_id:x}')
		return false
	}
	cfg.soc_revision_major = chip_revision >> 4
	cfg.soc_revision_minor = chip_revision & 7
	println('agx: loaded native chip info 0x${chip_id:x} revision ${cfg.soc_revision_major}.${cfg.soc_revision_minor}')
	return true
}

// Apple's base configureDevice producer copies this little-endian DeviceTree
// scalar into accelerator +0xf84c. The selected G17 getSamplePeriod method
// returns it unchanged for publication at firmware hardware-config +0xed8.
fn load_t6050_power_sample_period(gpu_node &devicetree.DTNode, mut cfg hw.HwConfig) bool {
	sample_period := devicetree.get_le_u32(gpu_node, 'gpu-power-sample-period') or {
		println('agx: t6050 has no gpu-power-sample-period')
		return false
	}
	if sample_period == 0 {
		println('agx: t6050 has an invalid zero GPU power sample period')
		return false
	}
	cfg.gpu_power_sample_period = sample_period
	println('agx: loaded native GPU power sample period ${sample_period}')
	return true
}

// Report what a native Apple DeviceTree boot is still missing for G13.
//
// This used to say the translation could not be written from the device tree at
// all, on any chip. It can, mostly: tools/agx-re/recover_t8103_adt.py reads a
// base-M1 DeviceTree and AGXG13G -- both staged under Preboot on any Mac, no M1
// needed -- and finds 22 of the 26 inputs load_t8103_* requires already there
// under gpu-* names, carrying the same values m1n1 republishes as apple,* FDT
// cells. load_t8103_power_controller_config() now reads either spelling.
//
// Four inputs have no Apple DeviceTree source at any spelling:
//
//   per-state power    perf-states is {frequency_hz, voltage_mV} pairs and
//                      carries no power column. Apple does not compute one
//                      either: AGXFirmware::setupConfig reads a published
//                      figure (gpu-device-max-power, else gpu-max-power) with
//                      no fallback behind it, and neither name is in a base-M1
//                      tree. Firmware refuses a zero max_power_mw, so the
//                      performance table stays unbuildable until this has a
//                      source.
//   min SRAM voltage   an m1n1 invention: it clamps the ADT core voltages to a
//                      floor that Apple's own boot data never states.
//   core/SRAM leakage  fused, not published. AGXAcceleratorG13G_B0::
//                      calculateGPULeakage reads one 64-bit word from the fuse
//                      aperture, shifts it, masks it, adds one and scales it by
//                      a driver-held f32. HwDataA wants the two resulting
//                      coefficients at 0x3cf4 and 0x3d14, so reproducing that
//                      read is the remaining work, not inventing a power model.
//
// A staged DeviceTree is only a template as well: its perf-states is
// zero-filled and iBoot writes the fused table in at boot, so a live tree is
// the only place the frequencies and voltages exist.
fn report_native_t8103_performance_gap(gpu_node &devicetree.DTNode, power_loaded bool) {
	state_count := devicetree.get_le_u32(gpu_node, 'perf-state-count') or { u32(0) }
	max_state := devicetree.get_le_u32(gpu_node, 'gpu-num-perf-states') or { u32(0) }
	state_words := (devicetree.get_le_u32_array(gpu_node, 'perf-states') or { []u32{} }).len
	println('agx: native t8103 GPU boot data is incomplete')
	println('agx:   perf-states: ${state_count} states, max ${max_state}, ${state_words} words')
	println('agx:   power controller: ${if power_loaded { 'complete' } else { 'incomplete' }}')
	println('agx:   missing: per-state power, minimum SRAM voltage, core and SRAM leakage')
	println('agx:   see tools/agx-re/recover_t8103_adt.py for where each one comes from')
}

// G13 receives its operating points through the standard OPP-v2 FDT binding.
// m1n1 derives this table from the machine's Apple DeviceTree, so it reflects
// the exact voltage and power data for both seven- and eight-core t8103 parts.
// Native Apple DeviceTree does not contain the phandle-based representation.
//
// The table m1n1 emits starts at an off state: opp00 is enabled and carries a
// zero frequency with zero power, because calc_power_t8103() yields zero there.
// Read it verbatim and let hw.apply_opp_table() decide what a valid table is,
// so that the firmware state numbering matches the device tree index for index.
fn load_t8103_performance_config(gpu_node &devicetree.DTNode, mut cfg hw.HwConfig) bool {
	opp_table := devicetree.get_phandle_node(gpu_node, 'operating-points-v2', 0) or {
		println('agx: t8103 has no operating-points-v2 table')
		return false
	}
	if opp_table.children.len < 2 {
		println('agx: invalid t8103 OPP count ${u32(opp_table.children.len)}')
		return false
	}
	min_sram_microvolt := devicetree.get_u32(gpu_node, 'apple,min-sram-microvolt') or {
		println('agx: t8103 has no apple,min-sram-microvolt')
		return false
	}
	base_state := devicetree.get_u32(gpu_node, 'apple,perf-base-pstate') or { u32(1) }
	power_sample_period := devicetree.get_u32(gpu_node, 'apple,power-sample-period') or {
		println('agx: t8103 has no apple,power-sample-period')
		return false
	}
	if power_sample_period == 0 {
		println('agx: t8103 has a zero power sample period')
		return false
	}

	mut entries := []hw.OppEntry{cap: opp_table.children.len}
	for opp in opp_table.children {
		if status := devicetree.get_string_list(opp, 'status') {
			if status.len > 0 && status[0] == 'disabled' {
				continue
			}
		}
		if u32(entries.len) >= hw.perf_state_capacity {
			println('agx: t8103 has too many enabled OPPs')
			return false
		}
		// A zero opp-hz or opp-microwatt is data, not a missing property, so
		// each value still has to be present before the entry is accepted.
		frequency_hz := devicetree.get_u64(opp, 'opp-hz') or {
			println('agx: t8103 OPP has no 64-bit opp-hz')
			return false
		}
		voltage_uv := devicetree.get_u32_array(opp, 'opp-microvolt') or {
			println('agx: t8103 OPP has no opp-microvolt array')
			return false
		}
		power_uw := devicetree.get_u32(opp, 'opp-microwatt') or {
			println('agx: t8103 OPP has no opp-microwatt value')
			return false
		}
		entries << hw.OppEntry{
			frequency_hz: frequency_hz
			voltage_uv: voltage_uv
			power_uw: power_uw
		}
	}
	if !cfg.apply_opp_table(entries, min_sram_microvolt, base_state) {
		println('agx: t8103 operating-point table was rejected')
		return false
	}

	cfg.gpu_power_sample_period = power_sample_period
	// println, not C.printf: kernel/c/printf.c makes _putchar a no-op under
	// -DPROD, so this bring-up evidence would never reach a real serial log.
	base_mhz := cfg.perf_state_frequencies[cfg.perf_state_base] / 1_000_000
	max_mhz := cfg.perf_state_frequencies[cfg.perf_state_count - 1] / 1_000_000
	println('agx: loaded ${cfg.perf_state_count} t8103 operating points (${cfg.perf_state_off_count()} off, ${base_mhz}..${max_mhz} MHz, ${cfg.max_power_mw} mW max)')
	return true
}

// One GPU control-loop scalar, under whichever spelling the boot data uses.
//
// Apple's DeviceTree publishes these as little-endian gpu-* scalars; m1n1
// republishes the identical set as big-endian apple,* FDT cells, and the names
// differ by that prefix and nothing else. The rule and its exceptions were
// recovered from a base-M1 DeviceTree and AGXG13G's own string table by
// tools/agx-re/recover_t8103_adt.py, so both boot paths can share one reader
// instead of keeping two transcriptions of forty-two property names in step.
fn g13_power_property(native_adt bool, name string) string {
	return if native_adt { 'gpu-${name}' } else { 'apple,${name}' }
}

fn get_g13_power_u32(node &devicetree.DTNode, native_adt bool, name string) ?u32 {
	property := g13_power_property(native_adt, name)
	if native_adt {
		return devicetree.get_le_u32(node, property)
	}
	return devicetree.get_u32(node, property)
}

fn get_g13_power_required_u32(node &devicetree.DTNode, native_adt bool, name string) ?u32 {
	value := get_g13_power_u32(node, native_adt, name) or {
		println('agx: t8103 boot data has no ${g13_power_property(native_adt, name)}')
		return none
	}
	return value
}

fn get_g13_power_u32_array(node &devicetree.DTNode, native_adt bool, name string) ?[]u32 {
	property := g13_power_property(native_adt, name)
	if native_adt {
		return devicetree.get_le_u32_array(node, property)
	}
	return devicetree.get_u32_array(node, property)
}

fn get_g13_power_required_u32_array(node &devicetree.DTNode, native_adt bool,
	name string) ?[]u32 {
	value := get_g13_power_u32_array(node, native_adt, name) or {
		println('agx: t8103 boot data has no ${g13_power_property(native_adt, name)}')
		return none
	}
	return value
}

fn valid_f32_bits(value u32) bool {
	return value & 0x7f800000 != 0x7f800000
}

// Preserve all PID/filter coefficients as raw IEEE-754 words. The values are
// consumed by the G13 firmware ABI and must not make the ARM kernel execute
// floating-point instructions while constructing InitData.
fn load_t8103_power_controller_config(gpu_node &devicetree.DTNode, native_adt bool,
	mut cfg hw.HwConfig) bool {
	mut power := hw.G13PowerConfig{
		fast_die0_release_temp: 80
		fender_idle_off_delay_ms: 40
		fw_early_wake_timeout_ms: 5
		idle_off_delay_ms: 2
		perf_boost_ce_step: 25
		perf_boost_min_util: 100
		perf_integral_gain_f32: 0x40fca970 // 7.8956833f
		perf_proportional_gain_f32: 0x416b53d1 // 14.707963f
		perf_reset_iters: 6
		pwr_filter_time_constant: 313
		pwr_integral_gain_f32: 0x3ca59586 // 0.0202129f
		pwr_proportional_gain_f32: 0x40a90fdb // 5.2831855f
		se_engagement_criteria: -1
		se_filter_time_constant: 9
		se_filter_time_constant_1: 3
		se_inactive_threshold: 2500
		se_ki_f32: 0xc2480000 // -50.0f
		se_ki_1_f32: 0xc2c80000 // -100.0f
		se_kp_f32: 0xc0a00000 // -5.0f
		se_kp_1_f32: 0xc1200000 // -10.0f
		se_reset_criteria: 50
	}
	if _ := devicetree.get_property(gpu_node, g13_power_property(native_adt, 'power-zones')) {
		zones := get_g13_power_u32_array(gpu_node, native_adt, 'power-zones') or {
			println('agx: malformed t8103 ${g13_power_property(native_adt, "power-zones")}')
			return false
		}
		if zones.len > 15 || zones.len % 3 != 0 {
			println('agx: invalid t8103 ${g13_power_property(native_adt, "power-zones")} length')
			return false
		}
		power.power_zone_count = u32(zones.len / 3)
		for index := u32(0); index < power.power_zone_count; index++ {
			base := index * 3
			if zones[base + 2] == 0 || zones[base + 1] > zones[base] {
				println('agx: invalid t8103 power zone ${index}')
				return false
			}
			power.power_zones[index] = hw.G13PowerZoneConfig{
				target: zones[base]
				target_offset: zones[base + 1]
				filter_tc: zones[base + 2]
			}
		}
	}

	core_leak := get_g13_power_required_u32_array(gpu_node, native_adt, 'core-leak-coef') or {
		return false
	}
	sram_leak := get_g13_power_required_u32_array(gpu_node, native_adt, 'sram-leak-coef') or {
		return false
	}
	if core_leak.len != int(cfg.num_clusters) || sram_leak.len != int(cfg.num_clusters) {
		println('agx: invalid t8103 leakage coefficient count')
		return false
	}
	for cluster := u32(0); cluster < cfg.num_clusters; cluster++ {
		if !valid_f32_bits(core_leak[cluster]) || !valid_f32_bits(sram_leak[cluster]) {
			println('agx: non-finite t8103 leakage coefficient')
			return false
		}
		power.core_leak_coef_f32[cluster] = core_leak[cluster]
		power.sram_leak_coef_f32[cluster] = sram_leak[cluster]
	}

	power.avg_power_filter_tc_ms = get_g13_power_required_u32(gpu_node, native_adt, 'avg-power-filter-tc-ms') or { return false }
	power.avg_power_ki_only_f32 = get_g13_power_required_u32(gpu_node, native_adt, 'avg-power-ki-only') or { return false }
	power.avg_power_kp_f32 = get_g13_power_required_u32(gpu_node, native_adt, 'avg-power-kp') or { return false }
	power.avg_power_min_duty_cycle = get_g13_power_required_u32(gpu_node, native_adt, 'avg-power-min-duty-cycle') or { return false }
	power.avg_power_target_filter_tc = get_g13_power_required_u32(gpu_node, native_adt, 'avg-power-target-filter-tc') or { return false }
	power.fast_die0_integral_gain_f32 = get_g13_power_required_u32(gpu_node, native_adt, 'fast-die0-integral-gain') or { return false }
	power.fast_die0_proportional_gain_f32 = get_g13_power_required_u32(gpu_node, native_adt, 'fast-die0-proportional-gain') or { return false }
	power.fast_die0_prop_tgt_delta = get_g13_power_u32(gpu_node, native_adt, 'fast-die0-prop-tgt-delta') or { u32(0) }
	power.fast_die0_release_temp = get_g13_power_u32(gpu_node, native_adt, 'fast-die0-release-temp') or { u32(80) }
	power.fender_idle_off_delay_ms = get_g13_power_u32(gpu_node, native_adt, 'fender-idle-off-delay-ms') or { u32(40) }
	power.fw_early_wake_timeout_ms = get_g13_power_u32(gpu_node, native_adt, 'fw-early-wake-timeout-ms') or { u32(5) }
	power.idle_off_delay_ms = get_g13_power_u32(gpu_node, native_adt, 'idle-off-delay-ms') or { u32(2) }
	power.idle_off_standby_timer = get_g13_power_u32(gpu_node, native_adt, 'idleoff-standby-timer') or { u32(0) }
	power.perf_boost_ce_step = get_g13_power_u32(gpu_node, native_adt, 'perf-boost-ce-step') or { u32(25) }
	power.perf_boost_min_util = get_g13_power_u32(gpu_node, native_adt, 'perf-boost-min-util') or { u32(100) }
	power.perf_filter_drop_threshold = get_g13_power_required_u32(gpu_node, native_adt, 'perf-filter-drop-threshold') or { return false }
	power.perf_filter_time_constant2 = get_g13_power_required_u32(gpu_node, native_adt, 'perf-filter-time-constant2') or { return false }
	power.perf_filter_time_constant = get_g13_power_required_u32(gpu_node, native_adt, 'perf-filter-time-constant') or { return false }
	power.perf_integral_gain2_f32 = get_g13_power_required_u32(gpu_node, native_adt, 'perf-integral-gain2') or { return false }
	power.perf_integral_gain_f32 = get_g13_power_u32(gpu_node, native_adt, 'perf-integral-gain') or { u32(0x40fca970) }
	power.perf_integral_min_clamp = get_g13_power_required_u32(gpu_node, native_adt, 'perf-integral-min-clamp') or { return false }
	power.perf_proportional_gain2_f32 = get_g13_power_required_u32(gpu_node, native_adt, 'perf-proportional-gain2') or { return false }
	power.perf_proportional_gain_f32 = get_g13_power_u32(gpu_node, native_adt, 'perf-proportional-gain') or { u32(0x416b53d1) }
	power.perf_reset_iters = get_g13_power_u32(gpu_node, native_adt, 'perf-reset-iters') or { u32(6) }
	power.perf_tgt_utilization = get_g13_power_required_u32(gpu_node, native_adt, 'perf-tgt-utilization') or { return false }
	power.ppm_filter_time_constant_ms = get_g13_power_required_u32(gpu_node, native_adt, 'ppm-filter-time-constant-ms') or { return false }
	power.ppm_ki_f32 = get_g13_power_required_u32(gpu_node, native_adt, 'ppm-ki') or { return false }
	power.ppm_kp_f32 = get_g13_power_required_u32(gpu_node, native_adt, 'ppm-kp') or { return false }
	power.pwr_filter_time_constant = get_g13_power_u32(gpu_node, native_adt, 'pwr-filter-time-constant') or { u32(313) }
	power.pwr_integral_gain_f32 = get_g13_power_u32(gpu_node, native_adt, 'pwr-integral-gain') or { u32(0x3ca59586) }
	power.pwr_integral_min_clamp = get_g13_power_u32(gpu_node, native_adt, 'pwr-integral-min-clamp') or { u32(0) }
	power.pwr_min_duty_cycle = get_g13_power_required_u32(gpu_node, native_adt, 'pwr-min-duty-cycle') or { return false }
	power.pwr_proportional_gain_f32 = get_g13_power_u32(gpu_node, native_adt, 'pwr-proportional-gain') or { u32(0x40a90fdb) }
	power.se_engagement_criteria = i32(get_g13_power_u32(gpu_node, native_adt, 'se-engagement-criteria') or { u32(-1) })
	power.se_filter_time_constant = get_g13_power_u32(gpu_node, native_adt, 'se-filter-time-constant') or { u32(9) }
	power.se_filter_time_constant_1 = get_g13_power_u32(gpu_node, native_adt, 'se-filter-time-constant-1') or { u32(3) }
	power.se_inactive_threshold = get_g13_power_u32(gpu_node, native_adt, 'se-inactive-threshold') or { u32(2500) }
	power.se_ki_f32 = get_g13_power_u32(gpu_node, native_adt, 'se-ki') or { u32(0xc2480000) }
	power.se_ki_1_f32 = get_g13_power_u32(gpu_node, native_adt, 'se-ki-1') or { u32(0xc2c80000) }
	power.se_kp_f32 = get_g13_power_u32(gpu_node, native_adt, 'se-kp') or { u32(0xc0a00000) }
	power.se_kp_1_f32 = get_g13_power_u32(gpu_node, native_adt, 'se-kp-1') or { u32(0xc1200000) }
	power.se_reset_criteria = get_g13_power_u32(gpu_node, native_adt, 'se-reset-criteria') or { u32(50) }

	default_clocks := cfg.base_clock_hz / 1000 * u64(cfg.gpu_power_sample_period)
	clocks := get_g13_power_u32(gpu_node, native_adt, 'pwr-sample-period-aic-clks') or {
		if default_clocks > 0xffff_ffff {
			return false
		}
		u32(default_clocks)
	}
	power.pwr_sample_period_aic_clks = clocks
	float_fields := [power.avg_power_ki_only_f32, power.avg_power_kp_f32,
		power.fast_die0_integral_gain_f32, power.fast_die0_proportional_gain_f32,
		power.perf_integral_gain_f32, power.perf_integral_gain2_f32,
		power.perf_proportional_gain_f32, power.perf_proportional_gain2_f32, power.ppm_ki_f32,
		power.ppm_kp_f32, power.pwr_integral_gain_f32, power.pwr_proportional_gain_f32,
		power.se_ki_f32, power.se_ki_1_f32, power.se_kp_f32, power.se_kp_1_f32]
	for value in float_fields {
		if !valid_f32_bits(value) {
			println('agx: t8103 power configuration contains a non-finite coefficient')
			return false
		}
	}
	period := cfg.gpu_power_sample_period
	if clocks == 0 || period == 0 || power.ppm_filter_time_constant_ms / period == 0
		|| power.avg_power_filter_tc_ms / period == 0 || power.avg_power_target_filter_tc == 0
		|| power.perf_filter_time_constant == 0 || power.perf_filter_time_constant2 == 0
		|| power.pwr_filter_time_constant == 0 || power.se_filter_time_constant == 0
		|| power.se_filter_time_constant_1 == 0 {
		println('agx: t8103 power configuration has an invalid zero filter period')
		return false
	}
	power.valid = true
	cfg.g13_power = power
	println('agx: loaded t8103 power controller (${power.power_zone_count} zones, ${period} ms period)')
	return true
}

// The unprefixed performance properties are Apple DeviceTree binary records,
// not big-endian FDT cells. Each record is { frequency_hz, voltage_mv } in
// little endian, grouped as one complete state table per GPU partition.
fn load_t6050_performance_config(gpu_node &devicetree.DTNode, mut cfg hw.HwConfig) bool {
	state_count := devicetree.get_le_u32(gpu_node, 'perf-state-count') or {
		println('agx: t6050 has no perf-state-count')
		return false
	}
	table_count := devicetree.get_le_u32(gpu_node, 'perf-state-table-count') or {
		println('agx: t6050 has no perf-state-table-count')
		return false
	}
	max_state := devicetree.get_le_u32(gpu_node, 'gpu-num-perf-states') or {
		println('agx: t6050 has no gpu-num-perf-states')
		return false
	}
	base_state := devicetree.get_le_u32(gpu_node, 'gpu-perf-base-pstate') or {
		println('agx: t6050 has no gpu-perf-base-pstate')
		return false
	}
	if state_count == 0 || state_count > 16 || table_count == 0 || table_count > 16
		|| max_state + 1 != state_count || base_state == 0 || base_state >= max_state {
		println('agx: invalid t6050 performance dimensions states=${state_count} tables=${table_count} base=${base_state} max=${max_state}')
		return false
	}
	states := devicetree.get_le_u32_array(gpu_node, 'perf-states') or {
		println('agx: t6050 has no perf-states')
		return false
	}
	sram_states := devicetree.get_le_u32_array(gpu_node, 'perf-states-sram') or {
		println('agx: t6050 has no perf-states-sram')
		return false
	}
	expected_words := int(state_count * table_count * 2)
	if states.len != expected_words || sram_states.len != expected_words {
		println('agx: invalid t6050 performance table lengths core=${u32(states.len)} sram=${u32(sram_states.len)} expected=${u32(expected_words)}')
		return false
	}

	for table := u32(0); table < table_count; table++ {
		for state := u32(0); state < state_count; state++ {
			source := int((table * state_count + state) * 2)
			destination := state * 16 + table
			frequency := states[source]
			if table == 0 {
				cfg.perf_state_frequencies[state] = frequency
			} else if frequency != cfg.perf_state_frequencies[state] {
				println('agx: t6050 performance table ${table} state ${state} has mismatched frequency')
				return false
			}
			if sram_states[source] != frequency {
				println('agx: t6050 SRAM table ${table} state ${state} has mismatched frequency')
				return false
			}
			cfg.perf_state_voltages[destination] = states[source + 1]
			cfg.perf_state_sram_voltages[destination] = sram_states[source + 1]
		}
	}
	cfg.perf_state_count = state_count
	cfg.perf_state_table_count = table_count
	cfg.perf_state_base = base_state
	println('agx: loaded ${state_count} x ${table_count} native performance states (${cfg.perf_state_frequencies[0] / 1000000}..${cfg.perf_state_frequencies[state_count - 1] / 1000000} MHz)')
	return true
}

// The auxiliary clock-domain format recovered from Apple's G17 producer is:
// {rail_count, state_count}, followed by voltage_uV/frequency_Hz pairs for
// each rail, then one default SRAM voltage_uV per rail. The producer converts
// voltages to mV and clamps SRAM voltage to max(core, default).
fn load_t6050_aux_performance_domain(gpu_node &devicetree.DTNode, name string) ?hw.AuxPerfStateConfig {
	values := devicetree.get_le_u64_array(gpu_node, name) or {
		println('agx: t6050 has no ${name}')
		return none
	}
	if values.len < 2 || values[0] == 0 || values[0] > 2 || values[1] == 0
		|| values[1] > 16 {
		println('agx: invalid t6050 ${name} dimensions')
		return none
	}
	table_count := u32(values[0])
	state_count := u32(values[1])
	expected_values := 2 + int(table_count) * (int(state_count) * 2 + 1)
	if values.len != expected_values {
		println('agx: invalid t6050 ${name} length=${u32(values.len)} expected=${u32(expected_values)}')
		return none
	}

	mut result := hw.AuxPerfStateConfig{
		state_count: state_count
		table_count: table_count
	}
	for table := u32(0); table < table_count; table++ {
		for state := u32(0); state < state_count; state++ {
			source := 2 + int((table * state_count + state) * 2)
			voltage_uv := values[source]
			frequency := values[source + 1]
			if voltage_uv % 1_000 != 0 || voltage_uv / 1_000 > 0xffff_ffff
				|| frequency > 0xffff_ffff {
				println('agx: invalid t6050 ${name} state value')
				return none
			}
			if table == 0 {
				result.frequencies[state] = u32(frequency)
			} else if frequency != result.frequencies[state] {
				println('agx: t6050 ${name} table ${table} state ${state} has mismatched frequency')
				return none
			}
			result.voltages[state * 2 + table] = u32(voltage_uv / 1_000)
		}
	}

	defaults_base := 2 + int(table_count * state_count * 2)
	for table := u32(0); table < table_count; table++ {
		default_uv := values[defaults_base + int(table)]
		if default_uv % 1_000 != 0 || default_uv / 1_000 > 0xffff_ffff {
			println('agx: invalid t6050 ${name} SRAM default')
			return none
		}
		default_mv := u32(default_uv / 1_000)
		for state := u32(0); state < state_count; state++ {
			index := state * 2 + table
			core_mv := result.voltages[index]
			result.sram_voltages[index] = if core_mv > default_mv { core_mv } else { default_mv }
		}
	}
	return result
}

fn load_t6050_aux_performance_config(gpu_node &devicetree.DTNode, mut cfg hw.HwConfig) bool {
	cs := load_t6050_aux_performance_domain(gpu_node, 'cs-perf-states') or { return false }
	afr := load_t6050_aux_performance_domain(gpu_node, 'afr-perf-states') or { return false }
	cfg.cs_perf_states = cs
	cfg.afr_perf_states = afr
	println('agx: loaded native CS/AFR performance states (${cs.state_count}/${afr.state_count} states)')
	return true
}

fn is_pmgr_power_domain(node &devicetree.DTNode) bool {
	compatibles := devicetree.get_string_list(node, 'compatible') or { return false }
	for compatible in compatibles {
		if compatible == 'apple,pmgr-pwrstate' || compatible == 'apple,t8103-pmgr-pwrstate' {
			return true
		}
	}
	return false
}

// Power-domain providers on the m1n1/Linux t8103 tree use zero argument
// cells. Enable every parent first (pmp before gfx), then transition the leaf
// using the PMGR aperture containing that provider.
fn enable_device_power_domains(node &devicetree.DTNode, depth u32) bool {
	if depth > 8 {
		println('agx: power-domain hierarchy is too deep')
		return false
	}
	domains := devicetree.get_u32_array(node, 'power-domains') or {
		if depth == 0 {
			println('agx: GPU node has no power-domain provider')
			return false
		}
		return true
	}
	if depth == 0 && domains.len == 0 {
		println('agx: GPU node has an empty power-domain list')
		return false
	}
	for handle in domains {
		domain := devicetree.find_phandle(handle) or {
			println('agx: unresolved power-domain phandle 0x${handle:x}')
			return false
		}
		cells := devicetree.get_u32(domain, '#power-domain-cells') or { u32(0) }
		if cells != 0 || !is_pmgr_power_domain(domain) {
			println('agx: unsupported power-domain provider ${domain.name}')
			return false
		}
		if !enable_device_power_domains(domain, depth + 1) {
			return false
		}
		offset := devicetree.get_u32(domain, 'reg') or {
			println('agx: power domain ${domain.name} has no register offset')
			return false
		}
		if domain.parent == unsafe { nil } {
			return false
		}
		apertures := devicetree.get_translated_reg_ranges(domain.parent) or {
			println('agx: power domain ${domain.name} has no PMGR aperture')
			return false
		}
		if apertures.len == 0 || !pmgr.enable_region(apertures[0].base, apertures[0].size, offset) {
			println('agx: failed to enable power domain ${domain.name}')
			return false
		}
		println('agx: enabled power domain ${domain.name}')
	}
	return true
}

// Run the G13 firmware ABI self-checks and name whichever ones failed.
//
// These are all deterministic layout and decoder checks, so a failure is a bug
// in this tree rather than anything about the machine. They used to sit behind
// one `||` chain and one message, which is how a fragment command whose two
// parameter blocks were eight bytes short of their recovered sizes cost a
// deploy and a reboot to identify. Every check is run and every failure is
// named, so one boot reports all of them.
fn g13_abi_check(passed bool, name string) bool {
	if !passed {
		println('agx: G13 ABI self-check failed: ${name}')
	}
	return passed
}

fn report_g13_internal_abi() bool {
	mut ok := true
	ok = g13_abi_check(regs.validate_g13_identity_decoder(), 'register identity decoder') && ok
	ok = g13_abi_check(regs.validate_g13_fault_decoder(), 'register fault decoder') && ok
	ok = g13_abi_check(fw.validate_g13_channel_layouts(), 'channel layouts') && ok
	ok = g13_abi_check(fw.validate_g13_initdata_layouts(), 'InitData layouts') && ok
	ok = g13_abi_check(fw.validate_g13_hwdata_layouts(), 'HwData layouts') && ok
	ok = g13_abi_check(fw.validate_g13_workqueue_layouts(), 'work-queue layouts') && ok
	ok = g13_abi_check(fw.validate_g13_event_layouts(), 'event layouts') && ok
	ok = g13_abi_check(fw.validate_g13_microsequence_layouts(), 'microsequence layouts') && ok
	ok = g13_abi_check(fw.validate_g13_job_layouts(), 'job layouts') && ok
	ok = g13_abi_check(fw.validate_g13_compute_layouts(), 'compute command layouts') && ok
	ok = g13_abi_check(fw.validate_g13_buffer_layouts(), 'buffer layouts') && ok
	ok = g13_abi_check(fw.validate_g13_vertex_layouts(), 'vertex command layouts') && ok
	ok = g13_abi_check(fw.validate_g13_fragment_layouts(), 'fragment command layouts') && ok
	return ok
}

// Probe GPU from device tree and bring up all supported subsystems.
pub fn initialise() {
	println('agx: Probing Apple GPU')

	// Step 1: Find and identify the GPU node.
	gpu_node, chip_id, native_adt := find_gpu_node() or {
		println('agx: GPU not found in device tree')
		return
	}
	mut cfg := hw.get_config(chip_id) or {
		println('agx: No hardware configuration for chip 0x${chip_id:x}')
		return
	}
	load_fdt_firmware_version(gpu_node, native_adt, mut cfg)
	mut g13_performance_config_complete := false
	if chip_id == 0x8103 {
		if native_adt {
			// Load everything the native tree does carry. The gate further
			// down stays shut on the four inputs it does not.
			native_power_loaded := load_t8103_power_controller_config(gpu_node, true, mut
				cfg)
			report_native_t8103_performance_gap(gpu_node, native_power_loaded)
		} else {
			g13_performance_config_complete = load_t8103_performance_config(gpu_node, mut cfg)
				&& load_t8103_power_controller_config(gpu_node, false, mut cfg)
		}
	}
	if chip_id == 0x6050 {
		if !native_adt || !agx_power.validate_t6050_contract(gpu_node)
			|| !load_t6050_chip_info(mut cfg)
			|| !load_t6050_power_sample_period(gpu_node, mut cfg)
			|| !load_t6050_performance_config(gpu_node, mut cfg)
			|| !load_t6050_aux_performance_config(gpu_node, mut cfg) {
			println('agx: t6050 native configuration is incomplete')
			return
		}
	}
	if chip_id == 0x8103 && !report_g13_internal_abi() {
		return
	}
	if !drm_ioctl.validate_asahi_25_layouts() {
		println('agx: Mesa 25.0.5 DRM UAPI layout validation failed')
		return
	}

	if chip_id == 0x6050 {
		if !fw.validate_g17_bootstrap_allocations() || !fw.validate_g17_accelerator_layouts()
			|| !fw.validate_g17_channel_layouts() {
			println('agx: internal G17 firmware layout validation failed')
			return
		}
		println('agx: detected t6050 / G17C, ${cfg.gpu_core_count} cores in ${cfg.num_mgpus} GPU partitions')
	} else {
		println('agx: detected chip 0x${chip_id:x}, up to ${cfg.gpu_core_count} cores')
	}

	// Step 2: Resolve all addresses without touching hardware. Native Apple
	// nodes and m1n1/Linux nodes expose different layouts.
	platform := get_platform_resources(gpu_node, native_adt, chip_id) or {
		println('agx: platform resources are incomplete')
		return
	}
	cfg.gpu_mmio_base = platform.sgx_base
	cfg.gpu_mmio_size = platform.sgx_size
	agx_driver_inst.detected = true
	if chip_id == 0x8103 && !validate_g13_firmware_compat(gpu_node, native_adt) {
		return
	}
	if platform.ttbs_size < 64 * 16 {
		println('agx: TTB region is too small for 64 UAT contexts')
		return
	}
	if platform.handoff_size < sizeof(mmu.UatHandoff) || platform.pagetables_size < pgtable.uat_pgsz {
		println('agx: UAT handoff or page-table reserved region is too small')
		return
	}
	if platform.asc_size < u64(regs.asc_ctl) + 4
		|| platform.sgx_size < u64(regs.gpu_id_clustercfg) + 4 {
		println('agx: ASC or SGX register window is too small')
		return
	}
	if chip_id == 0x6050 && (platform.firmware_role_count != 2
		|| platform.secondary_asc_size < u64(regs.asc_ctl) + 4) {
		println('agx: G17 requires complete GFX and GFX1 ASC resources')
		return
	}

	// Never power a GPU whose private firmware ABI or platform performance
	// inputs are incomplete. This check precedes every power-domain/ASC write.
	if !cfg.can_boot_firmware() {
		println('agx: chip 0x${chip_id:x} firmware ABI ${cfg.firmware_abi_name()} is not complete; leaving hardware untouched')
		return
	}
	if chip_id == 0x8103 && !g13_performance_config_complete {
		println('agx: t8103 performance configuration is incomplete; leaving hardware untouched')
		return
	}
	if !native_adt && !enable_device_power_domains(gpu_node, 0) {
		println('agx: failed to enable GPU power-domain hierarchy')
		return
	}

	// The identity registers are valid after the gfx power domain is active.
	// Reading the fused core mask here distinguishes the 7-core base M1 Air.
	gpu_res := regs.new_resources(platform.asc_base, platform.asc_size, platform.secondary_asc_base, platform.secondary_asc_size, platform.firmware_role_count, platform.sgx_base, platform.sgx_size)
	if chip_id == 0x8103 {
		identity := gpu_res.get_g13_identity() or {
			println('agx: invalid G13 hardware identity')
			return
		}
		if !cfg.apply_g13_identity(identity.revision_code, identity.num_clusters, identity.num_cores_per_cluster, identity.num_frags_per_cluster, identity.num_gps_per_cluster, identity.total_active_cores, identity.core_masks) {
			println('agx: G13 hardware identity exceeds t8103 limits')
			return
		}
		println('agx: t8103 topology ${identity.total_active_cores}/${identity.num_clusters * identity.num_cores_per_cluster} active cores, mask=0x${identity.core_masks[0]:x}')
	}
	agx_driver_inst.hw_config = cfg
	println('agx: ASC=0x${platform.asc_base:x} SGX=0x${platform.sgx_base:x} mailbox=0x${platform.mailbox_base:x} TTBs=0x${platform.ttbs_base:x}+0x${platform.ttbs_size:x}')
	if platform.firmware_role_count == 2 {
		println('agx: GFX1 ASC=0x${platform.secondary_asc_base:x} mailbox=0x${platform.secondary_mailbox_base:x}')
	}
	println('agx: UAT handoff=0x${platform.handoff_base:x}+0x${platform.handoff_size:x} page tables=0x${platform.pagetables_base:x}+0x${platform.pagetables_size:x}')

	// Step 3: Initialize the AGX-internal UAT from its reserved TTB region.
	handoff_abi := if cfg.firmware_abi == .g17_26_5_partial {
		mmu.UatHandoffAbi.g17_26_5
	} else {
		mmu.UatHandoffAbi.v12_3
	}
	_ := mmu.new_manager(platform.ttbs_base, platform.handoff_base, platform.pagetables_base, cfg.uat_ias, cfg.uat_oas, cfg.map_kernel_to_user, handoff_abi) or {
		println('agx: Failed to initialize UAT manager')
		return
	}

	// Step 4: Create RTKit and GpuManager using the mapped GPU resources.
	gpu_rtk := rtkit.new_rtkit(platform.mailbox_base, 'agx')
	mut gpu_secondary_rtk := rtkit.RTKit{}
	if platform.firmware_role_count == 2 {
		gpu_secondary_rtk = rtkit.new_rtkit(platform.secondary_mailbox_base, 'agx-gfx1')
	}

	mut mgr := gpu.new_gpu_manager(&gpu_res, &cfg, &gpu_rtk, &gpu_secondary_rtk) or {
		println('agx: Failed to create GPU manager')
		return
	}
	if !mgr.initialize_event_resources() {
		println('agx: Failed to initialize firmware event resources')
		return
	}

	// Step 5: Init GPU (RTKit boot, firmware init)
	if !mgr.init() {
		println('agx: GPU initialization failed')
		return
	}

	agx_driver_inst.gpu = &mgr
	gpu.set_global_manager(agx_driver_inst.gpu)

	// Step 7: Register DRM driver (name "asahi", features GEM|RENDER|COMPUTE)
	agx_drm_driver := &drm.DrmDriver{
		name: 'asahi'
		desc: 'Apple AGX GPU'
		major: 1
		minor: 0
		patchlevel: 0
		features: drm.driver_gem | drm.driver_render | drm.driver_compute
		ioctls: agx_file.drm_ioctls()
		file_close: agx_file.release_handle
		gem_close: agx_file.close_gem_handle
		gem_export: agx_file.gem_export_handler
		gem_import: agx_file.gem_import_handler
		mmap: agx_file.mmap_handle
	}

	agx_driver_inst.drm_dev = drm.register_driver(agx_drm_driver) or {
		println('agx: Failed to register DRM driver')
		return
	}

	agx_driver_inst.initialized = true

	// Step 8: Log success
	println('agx: Apple GPU driver initialized successfully')
	println('agx: DRM device registered as card${agx_driver_inst.drm_dev.dev_id}')
}

// Tear down the GPU driver and release all resources.
pub fn shutdown() {
	if !agx_driver_inst.initialized {
		return
	}

	println('agx: Shutting down Apple GPU driver')

	// Unregister DRM device
	if agx_driver_inst.drm_dev != unsafe { nil } {
		drm.unregister_device(agx_driver_inst.drm_dev)
		agx_driver_inst.drm_dev = unsafe { nil }
	}

	// Shutdown GPU manager (stops firmware, ASC)
	if agx_driver_inst.gpu != unsafe { nil } {
		mut g := unsafe { agx_driver_inst.gpu }
		g.shutdown()
		gpu.set_global_manager(unsafe { nil })
		agx_driver_inst.gpu = unsafe { nil }
	}

	agx_driver_inst.initialized = false
	println('agx: GPU driver shutdown complete')
}
