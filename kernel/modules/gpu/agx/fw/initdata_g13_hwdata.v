// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module fw

import gpu.agx.hw

// macOS 12.3 / G13 HwDataB. This is the pre-13.0b4 layout used by t8103.
// U64 fields in the reference ABI are explicitly unaligned, so the complete
// structure is packed here as well.
pub const g13_hwdata_b_size = u64(0xb6c)
pub const g13_io_mapping_count = 20

@[packed]
pub struct G13IoMapping {
pub mut:
	physical_address u64
	virtual_address  u64
	total_size       u32
	element_size     u32
	readwrite        u64
}

@[packed]
pub struct G13HwDataB {
pub mut:
	unk_000             u64
	unk_008             u64
	unk_010             u64
	unk_018             u64
	usc_start           u64
	usc_end             u64
	unknown_page        u64
	unkptr_038          u64
	pad_040             [0x20]u8
	yuv_matrices        [0x168]u8
	pad_1c8             [0x8]u8
	io_mappings         [g13_io_mapping_count]G13IoMapping
	chip_id             u32
	unk_454             u32
	unk_458             u32
	unk_45c             u32
	unk_460             u32
	unk_464             u32
	unk_468             u32
	unk_46c             u32
	unk_470             u32
	unk_474             u32
	unk_478             u32
	unk_47c             u32
	unk_480             u32
	unk_484             u32
	unk_488             u32
	unk_48c             u32
	base_clock_khz      u32
	power_sample_period u32
	pad_498             u32
	unk_49c             u32
	unk_4a0             u32
	unk_4a4             u32
	pad_4a8             u32
	unk_4ac             u32
	pad_4b0             [0x8]u8
	unk_4b8             u32
	unk_4bc             [0x4]u8
	unk_4c0             u32
	unk_4c4             u32
	unk_4c8             u32
	unk_4cc             u32
	unk_4d0             u32
	unk_4d4             u32
	unk_4d8             [0x4]u8
	unk_4dc             u32
	unk_4e0             u64
	unk_4e8             u32
	unk_4ec             u32
	unk_4f0             u32
	unk_4f4             u32
	unk_4f8             u32
	unk_4fc             u32
	unk_500             u32
	unk_504             u32
	unk_508             u32
	unk_50c             u32
	unk_510             u32
	unk_514             u32
	unk_518             u32
	unk_51c             u32
	unk_520             u32
	unk_524             u32
	unk_528             u32
	unk_52c             u32
	unk_530             u32
	unk_534             u32
	unk_538             u32
	num_frags           u32
	unk_540             u32
	unk_544             u32
	unk_548             u32
	unk_54c             u32
	unk_550             u32
	unk_554             u32
	uat_ttb_base        u64
	gpu_core_id         u32
	gpu_revision_id     u32
	num_cores           u32
	max_pstate          u32
	num_pstates         u32
	frequencies_mhz     [16]u32
	voltages_mv         [16][8]u32
	sram_voltages_mv    [16][8]u32
	sram_k_f32          [16]u32
	unk_9f4             [16]u32
	rel_max_powers      [16]u32
	rel_boost_freqs     [16]u32
	min_sram_voltage_mv u32
	unk_ab8             u32
	unk_abc             u32
	unk_ac0             u32
	pad_ac4             [0x8]u8
	unk_acc             u32
	unk_ad0             u32
	pad_ad4             [0x10]u8
	unk_ae4             [4]u32
	pad_af4             u32
	unk_af8             u32
	pad_afc             [0x8]u8
	unk_b04             u32
	unk_b08             u32
	unk_b0c             u32
	unk_b10             u32
	timer_offset        u64
	unk_b1c             u32
	unk_b20             u32
	unk_b24             u32
	unk_b28             u32
	unk_b2c             u32
	unk_b30             u32
	unk_b34             u32
	unk_b38             [12]u32
	unk_b68             u32
}

fn g13_firmware_revision_id(revision hw.GpuRevision) ?u32 {
	return match revision {
		.a0 { u32(1) }
		.a1 { u32(2) }
		.b0 { u32(3) }
		.b1 { u32(4) }
		.c0 { u32(5) }
		.c1 { u32(6) }
		.unknown { none }
	}
}

// Populate fields that are independent of the eventual firmware IOVA chosen
// for each MMIO record. The caller installs io_mappings after mapping them.
pub fn populate_g13_hwdata_b(mut data G13HwDataB, config &hw.HwConfig,
	uat_ttb_base u64, unknown_page u64) bool {
	if config.chip_id != 0x8103 || config.gpu_gen != .g13 || config.perf_state_count < 2
		|| config.perf_state_count > 16 || config.perf_state_table_count == 0
		|| config.perf_state_table_count > 8 || config.perf_state_base >= config.perf_state_count
		|| config.max_power_mw == 0 || config.gpu_power_sample_period == 0 || uat_ttb_base == 0
		|| unknown_page == 0 || config.min_sram_microvolt < 1000 {
		return false
	}
	revision_id := g13_firmware_revision_id(config.gpu_rev) or { return false }
	base_frequency := config.perf_state_frequencies[config.perf_state_base]
	max_frequency := config.perf_state_frequencies[config.perf_state_count - 1]
	if base_frequency == 0 || max_frequency <= base_frequency
		|| (max_frequency - base_frequency) / 100 == 0 {
		return false
	}

	data.unk_000 = 0x13_00000000
	data.unk_008 = 0x14_00000000
	data.unk_010 = 0x1_00000000
	data.unk_018 = 0xffc00000
	data.unknown_page = unknown_page
	data.unkptr_038 = 0xffffffa0_11800000
	data.chip_id = config.chip_id
	data.unk_454 = 1
	data.unk_458 = 1
	data.unk_460 = 1
	data.unk_464 = 1
	data.unk_468 = 1
	data.unk_47c = 1
	data.unk_484 = 1
	data.unk_48c = 1
	data.base_clock_khz = u32(config.base_clock_hz / 1000)
	data.power_sample_period = config.gpu_power_sample_period
	data.unk_49c = 1
	data.unk_4a0 = 1
	data.unk_4a4 = 1
	data.unk_4c0 = 0x1f
	data.unk_4f0 = 1
	data.unk_4f4 = 1
	data.unk_504 = 0x31
	data.unk_524 = 1
	data.num_frags = config.num_frags
	data.unk_554 = 1
	data.uat_ttb_base = uat_ttb_base
	data.gpu_core_id = config.firmware_gpu_core_id
	data.gpu_revision_id = revision_id
	data.num_cores = config.gpu_core_count
	data.max_pstate = config.perf_state_count - 1
	data.num_pstates = config.perf_state_count
	data.min_sram_voltage_mv = config.min_sram_microvolt / 1000
	data.unk_ab8 = 0x48
	data.unk_abc = 0x8
	data.unk_ac0 = 0x1020
	data.unk_ae4 = [u32(0), 0xf, 0x3f, 0x3f]!
	data.unk_b10 = 1
	data.unk_b24 = 1
	data.unk_b28 = 1
	data.unk_b2c = 1
	for index := 0; index < data.unk_b38.len; index++ {
		data.unk_b38[index] = 0xffff_ffff
	}

	boost_divisor := (max_frequency - base_frequency) / 100
	for state := u32(0); state < config.perf_state_count; state++ {
		frequency := config.perf_state_frequencies[state]
		power := config.perf_state_powers[state]
		if config.perf_state_is_active(state) {
			if power == 0 {
				return false
			}
		} else if power != 0 || state >= config.perf_state_base {
			// A stock t8103 table opens with an off state, and firmware wants
			// it published as zero frequency at zero power rather than dropped.
			// Only states below the base pstate may be off.
			return false
		}
		data.frequencies_mhz[state] = frequency / 1_000_000
		data.rel_max_powers[state] = power * 100 / config.max_power_mw
		data.rel_boost_freqs[state] = if state > config.perf_state_base {
			(frequency - base_frequency) / boost_divisor
		} else {
			0
		}
		data.sram_k_f32[state] = 0x3f828f5c // IEEE-754 1.02f
		for table := u32(0); table < config.perf_state_table_count; table++ {
			source := state * 16 + table
			core_mv := config.perf_state_voltages[source]
			sram_mv := config.perf_state_sram_voltages[source]
			if core_mv == 0 || sram_mv < core_mv {
				return false
			}
			data.voltages_mv[state][table] = core_mv
			data.sram_voltages_mv[state][table] = sram_mv
		}
		for table := config.perf_state_table_count; table < 8; table++ {
			data.voltages_mv[state][table] = data.voltages_mv[state][0]
			data.sram_voltages_mv[state][table] = data.sram_voltages_mv[state][0]
		}
	}
	return true
}

pub fn validate_g13_hwdata_layouts() bool {
	return sizeof(G13IoMapping) == 0x20 && sizeof(G13HwDataB) == g13_hwdata_b_size
		&& validate_g13_hwdata_a_layout()
}
