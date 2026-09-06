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
	// property. Its missing OPP-v2 data keeps that path fail-closed before
	// hardware access. Accept the old Vinix property as a compatibility aid,
	// but prefer the property used by current m1n1/Linux device trees.
	if native_adt {
		C.printf(c'agx: native t8103 firmware compatibility is unavailable\n')
		return true
	}
	mut property_name := 'apple,firmware-abi'
	compat := devicetree.get_u32_array(gpu_node, property_name) or {
		property_name = 'apple,firmware-compat'
		devicetree.get_u32_array(gpu_node, property_name) or {
			C.printf(c'agx: t8103 device tree has no apple,firmware-abi\n')
			return false
		}
	}
	if compat.len != 3 {
		C.printf(c'agx: malformed t8103 %s tuple\n', property_name.str)
		return false
	}
	C.printf(c'agx: t8103 %s %u.%u.%u\n', property_name.str, compat[0], compat[1], compat[2])
	if compat[0] != 12 || compat[1] != 3 || compat[2] != 0 {
		C.printf(c'agx: only the G13 12.3.0 firmware ABI is being implemented\n')
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
		C.printf(c'agx: ignoring malformed firmware version tuple\n')
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
		C.printf(c'agx: t6050 chip-id mismatch 0x%x != 0x%x\n', chip_id, cfg.chip_id)
		return false
	}
	cfg.soc_revision_major = chip_revision >> 4
	cfg.soc_revision_minor = chip_revision & 7
	C.printf(c'agx: loaded native chip info 0x%x revision %u.%u\n', chip_id, cfg.soc_revision_major, cfg.soc_revision_minor)
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
	C.printf(c'agx: loaded native GPU power sample period %u\n', sample_period)
	return true
}

// The native Apple DeviceTree carries no OPP-v2 table, and the gap is larger
// than a rename. G13's hwdata refuses to initialise with a zero max_power_mw,
// but the Apple GPU node carries only frequency and voltage: on a live M5 Max
// tree the sgx node's 66 properties include perf-states, perf-states-sram and
// gpu-pwr-perf-scale0/1, and no per-state power under any spelling.
//
// Apple's driver does not read that figure, it computes it: the recovered G17
// ABI exposes per-domain leakage equations and a fused chip-leakage table
// (calculateVddGpuLeakage, applyLeakageEquation, populateChipLeakageData) that
// turn voltage, frequency and per-die fuses into power. Reproducing that for
// G13 needs the equivalent model out of an M1's AGXG13X kext, which is not
// available here. So this is not a translation that can be written from the
// device tree at all, on any chip.
//
// Report what the node actually carries instead of guessing property names for
// a path whose whole purpose is to open GPU hardware access.
fn report_native_t8103_opp_gap(gpu_node &devicetree.DTNode) {
	println('agx: native t8103 OPP translation is not implemented')
	println('agx: expected an m1n1/Linux FDT (apple,agx-g13g) with operating-points-v2;')
	println('agx: this boot supplied the Apple DeviceTree (gpu,t8103) instead.')
	C.printf(c'agx: native t8103 GPU node exposes %u properties:\n',
		u32(gpu_node.properties.len))
	for property in gpu_node.properties {
		if property.len == 4 {
			C.printf(c'agx:   %s len=%u value=0x%x\n', property.name.str, property.len,
				read_le_u32_at(property.data, 0))
		} else if property.len >= 8 && property.len % 4 == 0 {
			C.printf(c'agx:   %s len=%u first=0x%x,0x%x\n', property.name.str,
				property.len, read_le_u32_at(property.data, 0),
				read_le_u32_at(property.data, 4))
		} else {
			C.printf(c'agx:   %s len=%u\n', property.name.str, property.len)
		}
	}
}

fn read_le_u32_at(data voidptr, offset u32) u32 {
	value := unsafe { &u8(u64(data) + offset) }
	return unsafe {
		u32(value[0]) | (u32(value[1]) << 8) | (u32(value[2]) << 16) | (u32(value[3]) << 24)
	}
}

// G13 receives its operating points through the standard OPP-v2 FDT binding.
// m1n1 derives this table from the machine's Apple DeviceTree, so it reflects
// the exact voltage and power data for both seven- and eight-core t8103 parts.
// Native Apple DeviceTree does not contain the phandle-based representation.
fn load_t8103_performance_config(gpu_node &devicetree.DTNode, mut cfg hw.HwConfig) bool {
	opp_table := devicetree.get_phandle_node(gpu_node, 'operating-points-v2', 0) or {
		println('agx: t8103 has no operating-points-v2 table')
		return false
	}
	if opp_table.children.len < 2 {
		C.printf(c'agx: invalid t8103 OPP count %u\n', u32(opp_table.children.len))
		return false
	}

	mut frequencies := [16]u32{}
	mut powers := [16]u32{}
	mut voltages := [256]u32{}
	mut sram_voltages := [256]u32{}
	min_sram_microvolt := devicetree.get_u32(gpu_node, 'apple,min-sram-microvolt') or {
		println('agx: t8103 has no apple,min-sram-microvolt')
		return false
	}
	if min_sram_microvolt < 1000 {
		println('agx: t8103 has an invalid minimum SRAM voltage')
		return false
	}
	min_sram_mv := min_sram_microvolt / 1000
	mut state_count := u32(0)
	mut max_power_mw := u32(0)
	for opp in opp_table.children {
		if status := devicetree.get_string_list(opp, 'status') {
			if status.len > 0 && status[0] == 'disabled' {
				continue
			}
		}
		if state_count >= 16 {
			println('agx: t8103 has too many enabled OPPs')
			return false
		}
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
		if frequency_hz == 0 || frequency_hz > 0xffff_ffff || voltage_uv.len != int(cfg.num_clusters)
			|| power_uw < 1000 {
			C.printf(c'agx: invalid t8103 OPP %u dimensions or values\n', state_count)
			return false
		}
		frequency := u32(frequency_hz)
		if state_count > 0 && frequency <= frequencies[state_count - 1] {
			C.printf(c'agx: t8103 OPP %u is not frequency ordered\n', state_count)
			return false
		}
		frequencies[state_count] = frequency
		power_mw := power_uw / 1000
		powers[state_count] = power_mw
		if power_mw > max_power_mw {
			max_power_mw = power_mw
		}
		for cluster := u32(0); cluster < cfg.num_clusters; cluster++ {
			if voltage_uv[cluster] < 1000 {
				C.printf(c'agx: invalid t8103 OPP %u cluster %u voltage\n', state_count, cluster)
				return false
			}
			voltage_mv := voltage_uv[cluster] / 1000
			destination := state_count * 16 + cluster
			voltages[destination] = voltage_mv
			sram_voltages[destination] = if voltage_mv > min_sram_mv {
				voltage_mv
			} else {
				min_sram_mv
			}
		}
		state_count++
	}
	if state_count < 2 || max_power_mw == 0 {
		println('agx: t8103 has too few valid operating points')
		return false
	}
	base_state := devicetree.get_u32(gpu_node, 'apple,perf-base-pstate') or { u32(1) }
	if base_state >= state_count {
		C.printf(c'agx: invalid t8103 base performance state %u/%u\n', base_state, state_count)
		return false
	}
	power_sample_period := devicetree.get_u32(gpu_node, 'apple,power-sample-period') or {
		println('agx: t8103 has no apple,power-sample-period')
		return false
	}
	if power_sample_period == 0 {
		println('agx: t8103 has a zero power sample period')
		return false
	}

	cfg.perf_state_count = state_count
	cfg.min_sram_microvolt = min_sram_microvolt
	cfg.perf_state_base = base_state
	cfg.perf_state_table_count = cfg.num_clusters
	cfg.perf_state_frequencies = frequencies
	cfg.perf_state_powers = powers
	cfg.perf_state_voltages = voltages
	cfg.perf_state_sram_voltages = sram_voltages
	cfg.max_power_mw = max_power_mw
	cfg.gpu_power_sample_period = power_sample_period
	C.printf(c'agx: loaded %u t8103 operating points (%u..%u MHz, %u mW max)\n', state_count, frequencies[base_state] / 1000000, frequencies[state_count - 1] / 1000000, max_power_mw)
	return true
}

fn get_g13_required_u32(node &devicetree.DTNode, name string) ?u32 {
	value := devicetree.get_u32(node, name) or {
		C.printf(c'agx: t8103 has no %s\n', name.str)
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
fn load_t8103_power_controller_config(gpu_node &devicetree.DTNode,
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
	if _ := devicetree.get_property(gpu_node, 'apple,power-zones') {
		zones := devicetree.get_u32_array(gpu_node, 'apple,power-zones') or {
			println('agx: malformed t8103 apple,power-zones')
			return false
		}
		if zones.len > 15 || zones.len % 3 != 0 {
			println('agx: invalid t8103 apple,power-zones length')
			return false
		}
		power.power_zone_count = u32(zones.len / 3)
		for index := u32(0); index < power.power_zone_count; index++ {
			base := index * 3
			if zones[base + 2] == 0 || zones[base + 1] > zones[base] {
				C.printf(c'agx: invalid t8103 power zone %u\n', index)
				return false
			}
			power.power_zones[index] = hw.G13PowerZoneConfig{
				target: zones[base]
				target_offset: zones[base + 1]
				filter_tc: zones[base + 2]
			}
		}
	}

	core_leak := devicetree.get_u32_array(gpu_node, 'apple,core-leak-coef') or {
		println('agx: t8103 has no apple,core-leak-coef')
		return false
	}
	sram_leak := devicetree.get_u32_array(gpu_node, 'apple,sram-leak-coef') or {
		println('agx: t8103 has no apple,sram-leak-coef')
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

	power.avg_power_filter_tc_ms = get_g13_required_u32(gpu_node, 'apple,avg-power-filter-tc-ms') or { return false }
	power.avg_power_ki_only_f32 = get_g13_required_u32(gpu_node, 'apple,avg-power-ki-only') or { return false }
	power.avg_power_kp_f32 = get_g13_required_u32(gpu_node, 'apple,avg-power-kp') or { return false }
	power.avg_power_min_duty_cycle = get_g13_required_u32(gpu_node, 'apple,avg-power-min-duty-cycle') or { return false }
	power.avg_power_target_filter_tc = get_g13_required_u32(gpu_node, 'apple,avg-power-target-filter-tc') or { return false }
	power.fast_die0_integral_gain_f32 = get_g13_required_u32(gpu_node, 'apple,fast-die0-integral-gain') or { return false }
	power.fast_die0_proportional_gain_f32 = get_g13_required_u32(gpu_node, 'apple,fast-die0-proportional-gain') or { return false }
	power.fast_die0_prop_tgt_delta = devicetree.get_u32(gpu_node, 'apple,fast-die0-prop-tgt-delta') or { u32(0) }
	power.fast_die0_release_temp = devicetree.get_u32(gpu_node, 'apple,fast-die0-release-temp') or { u32(80) }
	power.fender_idle_off_delay_ms = devicetree.get_u32(gpu_node, 'apple,fender-idle-off-delay-ms') or { u32(40) }
	power.fw_early_wake_timeout_ms = devicetree.get_u32(gpu_node, 'apple,fw-early-wake-timeout-ms') or { u32(5) }
	power.idle_off_delay_ms = devicetree.get_u32(gpu_node, 'apple,idle-off-delay-ms') or { u32(2) }
	power.idle_off_standby_timer = devicetree.get_u32(gpu_node, 'apple,idleoff-standby-timer') or { u32(0) }
	power.perf_boost_ce_step = devicetree.get_u32(gpu_node, 'apple,perf-boost-ce-step') or { u32(25) }
	power.perf_boost_min_util = devicetree.get_u32(gpu_node, 'apple,perf-boost-min-util') or { u32(100) }
	power.perf_filter_drop_threshold = get_g13_required_u32(gpu_node, 'apple,perf-filter-drop-threshold') or { return false }
	power.perf_filter_time_constant2 = get_g13_required_u32(gpu_node, 'apple,perf-filter-time-constant2') or { return false }
	power.perf_filter_time_constant = get_g13_required_u32(gpu_node, 'apple,perf-filter-time-constant') or { return false }
	power.perf_integral_gain2_f32 = get_g13_required_u32(gpu_node, 'apple,perf-integral-gain2') or { return false }
	power.perf_integral_gain_f32 = devicetree.get_u32(gpu_node, 'apple,perf-integral-gain') or { u32(0x40fca970) }
	power.perf_integral_min_clamp = get_g13_required_u32(gpu_node, 'apple,perf-integral-min-clamp') or { return false }
	power.perf_proportional_gain2_f32 = get_g13_required_u32(gpu_node, 'apple,perf-proportional-gain2') or { return false }
	power.perf_proportional_gain_f32 = devicetree.get_u32(gpu_node, 'apple,perf-proportional-gain') or { u32(0x416b53d1) }
	power.perf_reset_iters = devicetree.get_u32(gpu_node, 'apple,perf-reset-iters') or { u32(6) }
	power.perf_tgt_utilization = get_g13_required_u32(gpu_node, 'apple,perf-tgt-utilization') or { return false }
	power.ppm_filter_time_constant_ms = get_g13_required_u32(gpu_node, 'apple,ppm-filter-time-constant-ms') or { return false }
	power.ppm_ki_f32 = get_g13_required_u32(gpu_node, 'apple,ppm-ki') or { return false }
	power.ppm_kp_f32 = get_g13_required_u32(gpu_node, 'apple,ppm-kp') or { return false }
	power.pwr_filter_time_constant = devicetree.get_u32(gpu_node, 'apple,pwr-filter-time-constant') or { u32(313) }
	power.pwr_integral_gain_f32 = devicetree.get_u32(gpu_node, 'apple,pwr-integral-gain') or { u32(0x3ca59586) }
	power.pwr_integral_min_clamp = devicetree.get_u32(gpu_node, 'apple,pwr-integral-min-clamp') or { u32(0) }
	power.pwr_min_duty_cycle = get_g13_required_u32(gpu_node, 'apple,pwr-min-duty-cycle') or { return false }
	power.pwr_proportional_gain_f32 = devicetree.get_u32(gpu_node, 'apple,pwr-proportional-gain') or { u32(0x40a90fdb) }
	power.se_engagement_criteria = i32(devicetree.get_u32(gpu_node, 'apple,se-engagement-criteria') or { u32(-1) })
	power.se_filter_time_constant = devicetree.get_u32(gpu_node, 'apple,se-filter-time-constant') or { u32(9) }
	power.se_filter_time_constant_1 = devicetree.get_u32(gpu_node, 'apple,se-filter-time-constant-1') or { u32(3) }
	power.se_inactive_threshold = devicetree.get_u32(gpu_node, 'apple,se-inactive-threshold') or { u32(2500) }
	power.se_ki_f32 = devicetree.get_u32(gpu_node, 'apple,se-ki') or { u32(0xc2480000) }
	power.se_ki_1_f32 = devicetree.get_u32(gpu_node, 'apple,se-ki-1') or { u32(0xc2c80000) }
	power.se_kp_f32 = devicetree.get_u32(gpu_node, 'apple,se-kp') or { u32(0xc0a00000) }
	power.se_kp_1_f32 = devicetree.get_u32(gpu_node, 'apple,se-kp-1') or { u32(0xc1200000) }
	power.se_reset_criteria = devicetree.get_u32(gpu_node, 'apple,se-reset-criteria') or { u32(50) }

	default_clocks := cfg.base_clock_hz / 1000 * u64(cfg.gpu_power_sample_period)
	clocks := devicetree.get_u32(gpu_node, 'apple,pwr-sample-period-aic-clks') or {
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
	C.printf(c'agx: loaded t8103 power controller (%u zones, %u ms period)\n', power.power_zone_count, period)
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
		C.printf(c'agx: invalid t6050 performance dimensions states=%u tables=%u base=%u max=%u\n', state_count, table_count, base_state, max_state)
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
		C.printf(c'agx: invalid t6050 performance table lengths core=%u sram=%u expected=%u\n', u32(states.len), u32(sram_states.len), u32(expected_words))
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
				C.printf(c'agx: t6050 performance table %u state %u has mismatched frequency\n', table, state)
				return false
			}
			if sram_states[source] != frequency {
				C.printf(c'agx: t6050 SRAM table %u state %u has mismatched frequency\n', table, state)
				return false
			}
			cfg.perf_state_voltages[destination] = states[source + 1]
			cfg.perf_state_sram_voltages[destination] = sram_states[source + 1]
		}
	}
	cfg.perf_state_count = state_count
	cfg.perf_state_table_count = table_count
	cfg.perf_state_base = base_state
	C.printf(c'agx: loaded %u x %u native performance states (%u..%u MHz)\n', state_count, table_count, cfg.perf_state_frequencies[0] / 1000000, cfg.perf_state_frequencies[state_count - 1] / 1000000)
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
		C.printf(c'agx: invalid t6050 %s dimensions\n', name.str)
		return none
	}
	table_count := u32(values[0])
	state_count := u32(values[1])
	expected_values := 2 + int(table_count) * (int(state_count) * 2 + 1)
	if values.len != expected_values {
		C.printf(c'agx: invalid t6050 %s length=%u expected=%u\n', name.str, u32(values.len), u32(expected_values))
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
				C.printf(c'agx: invalid t6050 %s state value\n', name.str)
				return none
			}
			if table == 0 {
				result.frequencies[state] = u32(frequency)
			} else if frequency != result.frequencies[state] {
				C.printf(c'agx: t6050 %s table %u state %u has mismatched frequency\n', name.str, table, state)
				return none
			}
			result.voltages[state * 2 + table] = u32(voltage_uv / 1_000)
		}
	}

	defaults_base := 2 + int(table_count * state_count * 2)
	for table := u32(0); table < table_count; table++ {
		default_uv := values[defaults_base + int(table)]
		if default_uv % 1_000 != 0 || default_uv / 1_000 > 0xffff_ffff {
			C.printf(c'agx: invalid t6050 %s SRAM default\n', name.str)
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
	C.printf(c'agx: loaded native CS/AFR performance states (%u/%u states)\n', cs.state_count, afr.state_count)
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
			C.printf(c'agx: unresolved power-domain phandle 0x%x\n', handle)
			return false
		}
		cells := devicetree.get_u32(domain, '#power-domain-cells') or { u32(0) }
		if cells != 0 || !is_pmgr_power_domain(domain) {
			C.printf(c'agx: unsupported power-domain provider %s\n', domain.name.str)
			return false
		}
		if !enable_device_power_domains(domain, depth + 1) {
			return false
		}
		offset := devicetree.get_u32(domain, 'reg') or {
			C.printf(c'agx: power domain %s has no register offset\n', domain.name.str)
			return false
		}
		if domain.parent == unsafe { nil } {
			return false
		}
		apertures := devicetree.get_translated_reg_ranges(domain.parent) or {
			C.printf(c'agx: power domain %s has no PMGR aperture\n', domain.name.str)
			return false
		}
		if apertures.len == 0 || !pmgr.enable_region(apertures[0].base, apertures[0].size, offset) {
			C.printf(c'agx: failed to enable power domain %s\n', domain.name.str)
			return false
		}
		C.printf(c'agx: enabled power domain %s\n', domain.name.str)
	}
	return true
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
		C.printf(c'agx: No hardware configuration for chip 0x%x\n', chip_id)
		return
	}
	load_fdt_firmware_version(gpu_node, native_adt, mut cfg)
	mut g13_performance_config_complete := false
	if chip_id == 0x8103 {
		if native_adt {
			report_native_t8103_opp_gap(gpu_node)
		} else {
			g13_performance_config_complete = load_t8103_performance_config(gpu_node, mut cfg)
				&& load_t8103_power_controller_config(gpu_node, mut cfg)
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
	if chip_id == 0x8103
		&& (!regs.validate_g13_identity_decoder() || !regs.validate_g13_fault_decoder()
			|| !fw.validate_g13_channel_layouts() || !fw.validate_g13_initdata_layouts()
			|| !fw.validate_g13_hwdata_layouts()
			|| !fw.validate_g13_workqueue_layouts() || !fw.validate_g13_event_layouts()
			|| !fw.validate_g13_microsequence_layouts() || !fw.validate_g13_job_layouts()
			|| !fw.validate_g13_compute_layouts() || !fw.validate_g13_buffer_layouts()
			|| !fw.validate_g13_vertex_layouts() || !fw.validate_g13_fragment_layouts()) {
		println('agx: internal G13 register/queue ABI validation failed')
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
		C.printf(c'agx: detected t6050 / G17C, %u cores in %u GPU partitions\n', cfg.gpu_core_count, cfg.num_mgpus)
	} else {
		C.printf(c'agx: detected chip 0x%x, up to %u cores\n', chip_id, cfg.gpu_core_count)
	}

	// Step 2: Resolve all addresses without touching hardware. Native Apple
	// nodes and m1n1/Linux nodes expose different layouts.
	platform := get_platform_resources(gpu_node, native_adt, chip_id) or {
		println('agx: platform resources are incomplete')
		return
	}
	if chip_id == 0x8103 && !validate_g13_firmware_compat(gpu_node, native_adt) {
		return
	}
	cfg.gpu_mmio_base = platform.sgx_base
	cfg.gpu_mmio_size = platform.sgx_size
	agx_driver_inst.detected = true
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
		C.printf(c'agx: chip 0x%x firmware ABI %s is not complete; leaving hardware untouched\n', chip_id, cfg.firmware_abi_name())
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
		C.printf(c'agx: t8103 topology %u/%u active cores, mask=0x%x\n', identity.total_active_cores, identity.num_clusters * identity.num_cores_per_cluster, identity.core_masks[0])
	}
	agx_driver_inst.hw_config = cfg
	C.printf(c'agx: ASC=0x%llx SGX=0x%llx mailbox=0x%llx TTBs=0x%llx+0x%llx\n', platform.asc_base, platform.sgx_base, platform.mailbox_base, platform.ttbs_base, platform.ttbs_size)
	if platform.firmware_role_count == 2 {
		C.printf(c'agx: GFX1 ASC=0x%llx mailbox=0x%llx\n', platform.secondary_asc_base, platform.secondary_mailbox_base)
	}
	C.printf(c'agx: UAT handoff=0x%llx+0x%llx page tables=0x%llx+0x%llx\n', platform.handoff_base, platform.handoff_size, platform.pagetables_base, platform.pagetables_size)

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
	if !mgr.initialize_g13_event_resources() {
		println('agx: Failed to initialize native G13 event stamps')
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
