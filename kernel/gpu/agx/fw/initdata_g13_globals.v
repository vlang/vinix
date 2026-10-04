// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module fw

import gpu.agx.hw

// Host/firmware operation guard used to keep the GPU awake while submitted
// work is outstanding. This is an AtomicU32 in the v12.3 firmware ABI.
pub fn g13_globals_pending_submissions_offset(abi hw.FirmwareAbi) ?u64 {
	return match abi {
		.v12_3 { u64(0x8904) }
		.v13_5_partial { u64(0x8974) }
		else { none }
	}
}

// macOS 12.3 / G13 global firmware state. Firmware mutates most of this
// object, so preserve the full ABI extent and initialize only host-owned
// configuration words recovered from the reference driver.
@[packed]
// Sized for the larger of the two ABIs; see G13HwDataA.
pub struct G13Globals {
pub mut:
	bytes [0x12394]u8
}

fn g13_globals_put_u16(mut data G13Globals, abi hw.FirmwareAbi, offset u32, value u16) bool {
	if g13_globals_offset_dropped(abi, offset) {
		return true
	}
	active := g13_globals_active_size(abi) or { return false }
	translated := g13_globals_offset(abi, offset) or { return false }
	if translated > u32(active) - 2 {
		return false
	}
	return g13_globals_store_u16(mut data, translated, value)
}

// The caller has already limited the offset to the active ABI's size; this
// bounds the buffer itself, which is allocated for the larger of the two.
fn g13_globals_store_u16(mut data G13Globals, offset u32, value u16) bool {
	if offset > u32(g13_v13_5_globals_size) - 2 {
		return false
	}
	index := int(offset)
	data.bytes[index] = u8(value)
	data.bytes[index + 1] = u8(value >> 8)
	return true
}

fn g13_globals_put_u32(mut data G13Globals, abi hw.FirmwareAbi, offset u32, value u32) bool {
	if g13_globals_offset_dropped(abi, offset) {
		return true
	}
	translated := g13_globals_offset(abi, offset) or { return false }
	return g13_globals_put_raw_u32(mut data, abi, translated, value)
}

fn g13_globals_put_raw_u32(mut data G13Globals, abi hw.FirmwareAbi, offset u32, value u32) bool {
	active := g13_globals_active_size(abi) or { return false }
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

fn g13_globals_set_power_zones(mut data G13Globals, abi hw.FirmwareAbi,
	power &hw.G13PowerConfig) bool {
	if power.power_zone_count > power.power_zones.len {
		return false
	}
	for index := u32(0); index < power.power_zone_count; index++ {
		zone := power.power_zones[index]
		if zone.target_offset > zone.target || zone.filter_tc == 0 {
			return false
		}
		// The array moves at 13.5 but each entry keeps its shape, so the
		// base is translated once and indexed off directly.
		zones_base := g13_globals_offset(abi, 0x893c) or { return false }
		base := zones_base + index * 0xc
		if !g13_globals_put_raw_u32(mut data, abi, base, zone.target)
			|| !g13_globals_put_raw_u32(mut data, abi, base + 4, zone.target - zone.target_offset)
			|| !g13_globals_put_raw_u32(mut data, abi, base + 8, zone.filter_tc) {
			return false
		}
	}
	return true
}

fn g13_globals_set_t8103_shared_data(mut data G13Globals, abi hw.FirmwareAbi) bool {
	shared1 := [i32(-1), 0x7282, 0x50ea, 0x370a, 0x25be, 0x1c1f, 0x16fb, -1, -1, -1, -1, -1, -1,
		-1, -1, -1]!
	hws1_base := g13_globals_offset(abi, 0x89f8) or { return false }
	for index := 0; index < shared1.len; index++ {
		if !g13_globals_put_raw_u32(mut data, abi, hws1_base + u32(index * 4), u32(shared1[index])) {
			return false
		}
	}
	if !g13_globals_put_u32(mut data, abi, 0x8a98, 0xffff) {
		return false
	}

	shared2 := [i32(0x800), 0x1555, -1, -1, -1, -1, -1, -1, 0, 0]!
	hws2_base := g13_globals_offset(abi, 0x8aa0) or { return false }
	for index := 0; index < shared2.len; index++ {
		if !g13_globals_put_raw_u32(mut data, abi, hws2_base + u32(index * 4), u32(shared2[index])) {
			return false
		}
	}
	for index := u32(0); index < 0x10; index++ {
		data.bytes[int(hws2_base + 0x28 + index)] = 0xff
	}
	return g13_globals_put_u32(mut data, abi, 0x8fa8, 0x00c0_0007)
}

pub fn populate_g13_globals(mut data G13Globals, config &hw.HwConfig) bool {
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
		|| config.gpu_power_sample_period == 0 || power.avg_power_filter_tc_ms == 0
		|| power.power_zone_count > 5 {
		return false
	}
	period_ms := config.gpu_power_sample_period
	avg_periods := power.avg_power_filter_tc_ms / period_ms
	if avg_periods == 0 {
		return false
	}
	period_s := firmware_fraction_to_f32_bits(period_ms, 1000) or { return false }
	avg_ki_dt := firmware_f32_multiply_bits(power.avg_power_ki_only_f32, period_s) or {
		return false
	}
	fast_ki_dt := firmware_f32_multiply_bits(power.fast_die0_integral_gain_f32, period_s) or { return false }
	ppm_ki_dt := firmware_f32_multiply_bits(power.ppm_ki_f32, period_s) or {
		return false
	}
	max_scaled := g13_checked_mul_u32(100, config.perf_state_count - 1) or {
		return false
	}
	release_temp := g13_checked_mul_u32(100, power.fast_die0_release_temp) or {
		return false
	}
	prop_delta := g13_checked_mul_u32(100, power.fast_die0_prop_tgt_delta) or {
		return false
	}

	mut ok := true
	// GlobalsSub is packed and contains deliberately unaligned u32 words.
	ok = ok && g13_globals_put_u32(mut data, abi, 0x028, 1)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x02c, 1)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x034, 120)
	ok = ok && g13_globals_put_u16(mut data, abi, 0x054, 0xffff)
	ok = ok && g13_globals_put_u16(mut data, abi, 0x056, 40)
	ok = ok && g13_globals_put_u16(mut data, abi, 0x058, 0xffff)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x05e, 1)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x066, 1)

	ok = ok && g13_globals_put_u32(mut data, abi, 0x8900, 1)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x8908, config.max_power_mw)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x890c, max_scaled)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x8910, max_scaled)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x891c, max_scaled)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x8924, power.power_zone_count)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x8928, avg_periods)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x892c, avg_ki_dt)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x8930, power.avg_power_kp_f32)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x8934, power.avg_power_min_duty_cycle)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x8938, power.avg_power_target_filter_tc)
	ok = ok && g13_globals_set_power_zones(mut data, abi, power)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x89bc, 9880)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x89c0, release_temp)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x89c4, u32(-220))
	ok = ok && g13_globals_put_u32(mut data, abi, 0x89c8, prop_delta)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x89cc, power.fast_die0_proportional_gain_f32)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x89d0, fast_ki_dt)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x89e0, 1)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x89e4, config.max_power_mw)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x89e8, power.ppm_kp_f32)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x89ec, ppm_ki_dt)
	ok = ok && g13_globals_set_t8103_shared_data(mut data, abi)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x900c, 1)
	// fault_control remains zero (hard faults), matching the reference default.
	ok = ok && g13_globals_put_u32(mut data, abi, 0x10e84, 1)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x11020, 40)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x11024, 10)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x11028, 250)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x11030, power.idle_off_delay_ms)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x11034, power.fender_idle_off_delay_ms)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x11038, power.fw_early_wake_timeout_ms)
	ok = ok && g13_globals_put_u32(mut data, abi, 0x118e0, 40)
	return ok && g13_globals_write_v13_5_additions(mut data, abi, power)
}
