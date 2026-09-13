// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module fw

import gpu.agx.hw

// macOS 12.3 / G13 HwDataA. Most of this firmware-owned power-management
// record remains opaque. Store recovered fields by ABI offset so the unknown
// spans stay zero and unaligned words are always emitted byte-for-byte.
pub const g13_hwdata_a_size = u64(0x3d6c)

@[packed]
// Sized for the larger of the two ABIs. How much of it firmware is told to
// read is g13_hwdata_a_active_size(), and the writers refuse anything past that,
// so a 12.3 boot still publishes exactly 0x3d6c bytes.
pub struct G13HwDataA {
pub mut:
	bytes [0x421c]u8
}

// Write one 12.3-addressed field, wherever it lives at the selected ABI.
fn g13_hwdata_a_put_u32(mut data G13HwDataA, abi hw.FirmwareAbi, offset u32, value u32) bool {
	if g13_hwdata_a_offset_dropped(abi, offset) {
		return true
	}
	translated := g13_hwdata_a_offset(abi, offset) or { return false }
	return g13_hwdata_a_put_raw_u32(mut data, abi, translated, value)
}

// Write at an offset that is already correct for the selected ABI. Used for the
// fields 13.5 adds, which have no 12.3 offset to translate from.
fn g13_hwdata_a_put_raw_u32(mut data G13HwDataA, abi hw.FirmwareAbi, offset u32, value u32) bool {
	active := g13_hwdata_a_active_size(abi) or { return false }
	if offset > u32(active) - 4 {
		return false
	}
	index := int(offset)
	data.bytes[index] = u8(value)
	data.bytes[index + 1] = u8(value >> 8)
	data.bytes[index + 2] = u8(value >> 16)
	data.bytes[index + 3] = u8(value >> 24)
	return true
}

fn g13_hwdata_a_put_u64(mut data G13HwDataA, abi hw.FirmwareAbi, offset u32, value u64) bool {
	if g13_hwdata_a_offset_dropped(abi, offset) {
		return true
	}
	active := g13_hwdata_a_active_size(abi) or { return false }
	translated := g13_hwdata_a_offset(abi, offset) or { return false }
	if translated > u32(active) - 8 {
		return false
	}
	return g13_hwdata_a_store_u64(mut data, abi, translated, value)
}

fn g13_hwdata_a_store_u64(mut data G13HwDataA, abi hw.FirmwareAbi, offset u32, value u64) bool {
	if offset > u32(g13_v13_5_hw_data_a_size) - 8 {
		return false
	}
	return g13_hwdata_a_put_raw_u32(mut data, abi, offset, u32(value))
		&& g13_hwdata_a_put_raw_u32(mut data, abi, offset + 4, u32(value >> 32))
}

fn g13_checked_mul_u32(left u32, right u32) ?u32 {
	if left != 0 && right > u32(-1) / left {
		return none
	}
	return left * right
}

fn g13_set_filter(mut data G13HwDataA, abi hw.FirmwareAbi, neg_offset u32, value_offset u32,
	time_constant u32) bool {
	filter := firmware_fraction_to_f32_bits(1, time_constant) or { return false }
	negative := firmware_f32_one_minus_bits(filter) or { return false }
	return g13_hwdata_a_put_u32(mut data, abi, neg_offset, negative)
		&& g13_hwdata_a_put_u32(mut data, abi, value_offset, filter)
}

fn g13_set_power_zones(mut data G13HwDataA, abi hw.FirmwareAbi,
	power &hw.G13PowerConfig, period_ms u32) bool {
	zones_base := g13_hwdata_a_offset(abi, 0xc58) or { return false }
	zone_at := g13_power_zone_offsets(abi) or { return false }
	if power.power_zone_count > power.power_zones.len {
		return false
	}
	for index := u32(0); index < power.power_zone_count; index++ {
		zone := power.power_zones[index]
		if zone.filter_tc == 0 || zone.target_offset > zone.target {
			return false
		}
		base := zones_base + index * zone_at.stride
		filter := firmware_fraction_to_f32_bits(1, zone.filter_tc) or { return false }
		negative := firmware_f32_one_minus_bits(filter) or { return false }
		filter_x4 := g13_checked_mul_u32(4, zone.filter_tc) or { return false }
		filter_xperiod := g13_checked_mul_u32(period_ms, zone.filter_tc) or {
			return false
		}
		if !g13_hwdata_a_put_raw_u32(mut data, abi, base + zone_at.target, zone.target)
			|| !g13_hwdata_a_put_raw_u32(mut data, abi, base + zone_at.target_off, zone.target - zone.target_offset)
			|| !g13_hwdata_a_put_raw_u32(mut data, abi, base + zone_at.filter_tc_x4, filter_x4)
			|| !g13_hwdata_a_put_raw_u32(mut data, abi, base + zone_at.filter_tc_xperiod, filter_xperiod)
			|| !g13_hwdata_a_put_raw_u32(mut data, abi, base + zone_at.filter_a_neg, negative)
			|| !g13_hwdata_a_put_raw_u32(mut data, abi, base + zone_at.filter_a, filter) {
			return false
		}
		// 13.5 only, from m1n1's initdata.rs.
		if zone_at.has_unk_10 {
			if !g13_hwdata_a_put_raw_u32(mut data, abi, base + zone_at.unk_10, 1320000000) {
				return false
			}
		}
	}
	return true
}

fn g13_set_t8103_shared_data(mut data G13HwDataA, abi hw.FirmwareAbi) bool {
	// hws1 and hws2 keep their shape at 13.5; only their bases move.
	hws1_base := g13_hwdata_a_offset(abi, 0x3648) or { return false }
	hws2_base := g13_hwdata_a_offset(abi, 0x36f0) or { return false }
	hws2_fill := g13_hwdata_a_offset(abi, 0x3718) or { return false }
	shared1 := [i32(-1), 0x7282, 0x50ea, 0x370a, 0x25be, 0x1c1f, 0x16fb, -1, -1, -1, -1, -1, -1,
		-1, -1, -1]!
	for index := 0; index < shared1.len; index++ {
		if !g13_hwdata_a_put_raw_u32(mut data, abi, hws1_base + u32(index * 4), u32(shared1[index])) {
			return false
		}
	}
	// HwDataShared1::unk_a4 is named for a historical layout; in the G13
	// structure it is at byte 0xa0 and the complete object is 0xa8 bytes.
	if !g13_hwdata_a_put_u32(mut data, abi, 0x36e8, 0xffff) {
		return false
	}

	shared2 := [i32(0x800), 0x1555, -1, -1, -1, -1, -1, -1, 0, 0]!
	for index := 0; index < shared2.len; index++ {
		if !g13_hwdata_a_put_raw_u32(mut data, abi, hws2_base + u32(index * 4), u32(shared2[index])) {
			return false
		}
	}
	for index := u32(0); index < 0x10; index++ {
		data.bytes[int(hws2_fill + index)] = 0xff
	}
	return g13_hwdata_a_put_u32(mut data, abi, 0x3bf8, 0x00c0_0007)
}

// Construct the complete recovered t8103 HwDataA payload. Returning false is
// intentional fail-closed behavior: no approximate coefficient is published
// to firmware if a DT value falls outside the integer float implementation.
pub fn populate_g13_hwdata_a(mut data G13HwDataA, config &hw.HwConfig) bool {
	// Which layout to write. Only the two G13 ABIs have offset tables; any
	// other value has no business reaching a G13 InitData builder.
	abi := config.firmware_abi
	if !g13_initdata_abi_supported(abi) {
		return false
	}
	power := &config.g13_power
	if config.chip_id != 0x8103 || config.gpu_gen != .g13 || !power.valid
		|| config.perf_state_count < 2 || config.perf_state_count > 16
		|| config.perf_state_base >= config.perf_state_count || config.max_power_mw == 0
		|| config.gpu_power_sample_period == 0 || power.ppm_filter_time_constant_ms == 0
		|| power.avg_power_filter_tc_ms == 0 || power.pwr_min_duty_cycle > 0x7fff_ffff
		|| config.num_clusters == 0 || config.num_clusters > 8 {
		return false
	}
	period_ms := config.gpu_power_sample_period
	period_s := firmware_fraction_to_f32_bits(period_ms, 1000) or { return false }
	ppm_periods := power.ppm_filter_time_constant_ms / period_ms
	avg_periods := power.avg_power_filter_tc_ms / period_ms
	if ppm_periods == 0 || avg_periods == 0 {
		return false
	}
	ppm_periods_x4 := g13_checked_mul_u32(ppm_periods, 4) or { return false }
	avg_periods_x4 := g13_checked_mul_u32(avg_periods, 4) or { return false }
	base_scaled := g13_checked_mul_u32(100, config.perf_state_base) or { return false }
	max_state := config.perf_state_count - 1
	max_scaled := g13_checked_mul_u32(100, max_state) or { return false }
	max_power_f32 := firmware_u32_to_f32_bits(config.max_power_mw) or { return false }
	duty_f32 := firmware_u32_to_f32_bits(power.pwr_min_duty_cycle) or { return false }
	max_scaled_f32 := firmware_u32_to_f32_bits(max_scaled) or { return false }
	pwr_pstate_k := firmware_fraction_to_f32_bits(max_scaled, config.max_power_mw) or {
		return false
	}
	boost_numerator := g13_checked_mul_u32(max_state - config.perf_state_base, 100) or {
		return false
	}
	boost_k := firmware_fraction_to_f32_bits(boost_numerator, 95) or { return false }
	ppm_ki_dt := firmware_f32_multiply_bits(power.ppm_ki_f32, period_s) or {
		return false
	}
	fast_die_ki_dt := firmware_f32_multiply_bits(power.fast_die0_integral_gain_f32, period_s) or { return false }
	avg_power_ki_dt := firmware_f32_multiply_bits(power.avg_power_ki_only_f32, period_s) or { return false }

	mut ok := true
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x004, power.pwr_sample_period_aic_clks)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x00c, 4)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x010, 0x3f80_0000)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x028, 1)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x02c, 1)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x03c, base_scaled)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x040, 1)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x044, max_scaled)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x04c, 100)
	sram_k_base := g13_hwdata_a_offset(abi, 0x074) or { return false }
	for state := u32(0); state < config.perf_state_count; state++ {
		ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, sram_k_base + state * 4, 0x3f82_8f5c)
	}

	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x64c, 625)
	ok = ok && g13_set_filter(mut data, abi, 0x658, 0x660, power.pwr_filter_time_constant)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x668, power.pwr_integral_gain_f32)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x670, firmware_u32_to_f32_bits(power.pwr_integral_min_clamp) or { return false })
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x674, max_power_f32)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x678, power.pwr_proportional_gain_f32)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x680, pwr_pstate_k | 0x8000_0000)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x684, u32(i32(power.pwr_min_duty_cycle) - i32(max_scaled)))
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x68c, max_scaled)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x698, config.max_power_mw)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x6b8, max_scaled)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x6d4, ppm_periods_x4)
	ok = ok && g13_set_filter(mut data, abi, 0x6e0, 0x6e8, ppm_periods)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x6f0, ppm_ki_dt)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x6f8, power.pwr_integral_min_clamp)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x6fc, 0x4780_0000)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x700, power.ppm_kp_f32)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x70c, power.pwr_min_duty_cycle)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x710, max_scaled)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x720, config.max_power_mw)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x728, power.ppm_filter_time_constant_ms)

	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x75c, power.perf_tgt_utilization)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x764, power.perf_boost_min_util)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x768, power.perf_boost_ce_step)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x76c, power.perf_reset_iters)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x774, 6)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x778, 1)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x77c, power.perf_filter_drop_threshold)
	ok = ok && g13_set_filter(mut data, abi, 0x780, 0x788, power.perf_filter_time_constant)
	perf_filter2 := firmware_fraction_to_f32_bits(1, power.perf_filter_time_constant2) or {
		return false
	}
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x784, firmware_f32_one_minus_bits(perf_filter2) or { return false })
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x78c, perf_filter2)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x790, power.perf_integral_gain_f32)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x794, power.perf_integral_gain2_f32)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x798, firmware_u32_to_f32_bits(power.perf_integral_min_clamp) or { return false })
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x79c, 0x42be_0000)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x7a0, power.perf_proportional_gain_f32)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x7a4, power.perf_proportional_gain2_f32)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x7a8, boost_k)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x7ac, base_scaled)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x7b0, max_scaled)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x7b4, base_scaled)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x7c0, power.perf_tgt_utilization)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x7e0, base_scaled)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x7fc, 0x4780_0000)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x800, duty_f32)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x804, max_scaled_f32)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x808, config.perf_state_frequencies[max_state] / 1_000_000)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x818, power.pwr_min_duty_cycle)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x824, 0x42c8_0000)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x828, max_scaled)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x830, 0x3f4c_cccd)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x834, 0x3e4c_cccd)

	ok = ok && g13_hwdata_a_put_u64(mut data, abi, 0x870, 0x12)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x878, g13_checked_mul_u32(100, power.fast_die0_release_temp) or { return false })
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x87c, u32(-220))
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x880, 4)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x894, 0x3f80_0000)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x89c, fast_die_ki_dt)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x8a8, 0x4780_0000)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x8ac, power.fast_die0_proportional_gain_f32)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x8b8, power.pwr_min_duty_cycle)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x8bc, max_scaled)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x8c0, max_scaled)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x8c4, g13_checked_mul_u32(100, power.fast_die0_prop_tgt_delta) or { return false })
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x8cc, 9880)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x8ec, max_scaled)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xb94, max_scaled)

	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xc2c, 1)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xc30, power.power_zone_count)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xc34, config.max_power_mw)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xc38, config.max_power_mw)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xc3c, config.max_power_mw)
	ok = ok && g13_set_filter(mut data, abi, 0xc48, 0xc4c, power.avg_power_target_filter_tc)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xc50, g13_checked_mul_u32(4, power.avg_power_target_filter_tc) or { return false })
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xc54, g13_checked_mul_u32(period_ms, power.avg_power_target_filter_tc) or { return false })
	ok = ok && g13_set_power_zones(mut data, abi, power, period_ms)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xcf8, avg_periods_x4)
	ok = ok && g13_set_filter(mut data, abi, 0xd04, 0xd0c, avg_periods)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xd14, avg_power_ki_dt)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xd20, 0x4780_0000)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xd24, power.avg_power_kp_f32)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xd30, power.avg_power_min_duty_cycle)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xd34, max_scaled)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xd38, max_scaled)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xd40, max_power_f32)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xd44, config.max_power_mw)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xd4c, power.avg_power_filter_tc_ms)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xd64, max_scaled)

	// Exact pre-13.3 t8103 tail selected by Apple's builder.
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xd8c, 0x8000_0000)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xd90, 4)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xd9c, 0x3f19_999a)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xda4, 0x3ecc_cccd)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xdac, 0x3ec5_62e1)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xdb8, 0x4780_0000)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xdbc, 0x4158_f5c3)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xdcc, max_scaled)
	ok = ok && g13_hwdata_a_put_u64(mut data, abi, 0xe1c, 0x12)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xe24, 112)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0xe28, 1)
	ok = ok && g13_hwdata_a_put_u64(mut data, abi, 0x162c, 0x12)
	ok = ok && g13_hwdata_a_put_u64(mut data, abi, 0x1634, 1)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x163c, 1)
	ok = ok && g13_set_t8103_shared_data(mut data, abi)
	ok = ok && g13_hwdata_a_put_u32(mut data, abi, 0x3ce8, 1)
	// Translate each array base once; indexing a 12.3 offset and translating
	// the result only finds an entry for cluster zero.
	core_leak_base := g13_hwdata_a_offset(abi, 0x3cf4) or { return false }
	sram_leak_base := g13_hwdata_a_offset(abi, 0x3d14) or { return false }
	for cluster := u32(0); cluster < config.num_clusters; cluster++ {
		ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, core_leak_base + cluster * 4, power.core_leak_coef_f32[cluster])
		ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, sram_leak_base + cluster * 4, power.sram_leak_coef_f32[cluster])
	}
	if config.base_clock_hz == 0 {
		return false
	}
	inputs := G13V135Inputs{
		period_ms: period_ms
		period_s_f32: period_s
		base_clock_khz: u32(config.base_clock_hz / 1000)
		clocks_per_period: power.pwr_sample_period_aic_clks
		ppm_filter_tc_periods: ppm_periods
		avg_filter_tc_periods: avg_periods
		max_pstate_scaled: max_scaled
	}
	return ok && g13_hwdata_a_write_v13_5_additions(mut data, abi, power, inputs)
}

pub fn validate_g13_hwdata_a_layout() bool {
	return sizeof(G13HwDataA) == g13_v13_5_hw_data_a_size
		&& g13_v12_3_hw_data_a_size <= g13_v13_5_hw_data_a_size
}
