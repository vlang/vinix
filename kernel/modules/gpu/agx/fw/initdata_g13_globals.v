// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module fw

import gpu.agx.hw

// Host/firmware operation guard used to keep the GPU awake while submitted
// work is outstanding. This is an AtomicU32 in the v12.3 firmware ABI.
pub const g13_globals_pending_submissions_offset = u64(0x8904)

// macOS 12.3 / G13 global firmware state. Firmware mutates most of this
// object, so preserve the full ABI extent and initialize only host-owned
// configuration words recovered from the reference driver.
@[packed]
pub struct G13Globals {
pub mut:
	bytes [0x11d40]u8
}

fn g13_globals_put_u16(mut data G13Globals, offset u32, value u16) bool {
	if offset > u32(g13_globals_size) - 2 {
		return false
	}
	index := int(offset)
	data.bytes[index] = u8(value)
	data.bytes[index + 1] = u8(value >> 8)
	return true
}

fn g13_globals_put_u32(mut data G13Globals, offset u32, value u32) bool {
	if offset > u32(g13_globals_size) - 4 {
		return false
	}
	index := int(offset)
	data.bytes[index] = u8(value)
	data.bytes[index + 1] = u8(value >> 8)
	data.bytes[index + 2] = u8(value >> 16)
	data.bytes[index + 3] = u8(value >> 24)
	return true
}

fn g13_globals_set_power_zones(mut data G13Globals, power &hw.G13PowerConfig) bool {
	if power.power_zone_count > power.power_zones.len {
		return false
	}
	for index := u32(0); index < power.power_zone_count; index++ {
		zone := power.power_zones[index]
		if zone.target_offset > zone.target || zone.filter_tc == 0 {
			return false
		}
		base := u32(0x893c) + index * 0xc
		if !g13_globals_put_u32(mut data, base, zone.target)
			|| !g13_globals_put_u32(mut data, base + 4, zone.target - zone.target_offset)
			|| !g13_globals_put_u32(mut data, base + 8, zone.filter_tc) {
			return false
		}
	}
	return true
}

fn g13_globals_set_t8103_shared_data(mut data G13Globals) bool {
	shared1 := [i32(-1), 0x7282, 0x50ea, 0x370a, 0x25be, 0x1c1f, 0x16fb, -1, -1, -1, -1, -1, -1,
		-1, -1, -1]!
	for index := 0; index < shared1.len; index++ {
		if !g13_globals_put_u32(mut data, u32(0x89f8 + index * 4), u32(shared1[index])) {
			return false
		}
	}
	if !g13_globals_put_u32(mut data, 0x8a98, 0xffff) {
		return false
	}

	shared2 := [i32(0x800), 0x1555, -1, -1, -1, -1, -1, -1, 0, 0]!
	for index := 0; index < shared2.len; index++ {
		if !g13_globals_put_u32(mut data, u32(0x8aa0 + index * 4), u32(shared2[index])) {
			return false
		}
	}
	for index := u32(0); index < 0x10; index++ {
		data.bytes[int(0x8ac8 + index)] = 0xff
	}
	return g13_globals_put_u32(mut data, 0x8fa8, 0x00c0_0007)
}

pub fn populate_g13_globals(mut data G13Globals, config &hw.HwConfig) bool {
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
	ok = ok && g13_globals_put_u32(mut data, 0x028, 1)
	ok = ok && g13_globals_put_u32(mut data, 0x02c, 1)
	ok = ok && g13_globals_put_u32(mut data, 0x034, 120)
	ok = ok && g13_globals_put_u16(mut data, 0x054, 0xffff)
	ok = ok && g13_globals_put_u16(mut data, 0x056, 40)
	ok = ok && g13_globals_put_u16(mut data, 0x058, 0xffff)
	ok = ok && g13_globals_put_u32(mut data, 0x05e, 1)
	ok = ok && g13_globals_put_u32(mut data, 0x066, 1)

	ok = ok && g13_globals_put_u32(mut data, 0x8900, 1)
	ok = ok && g13_globals_put_u32(mut data, 0x8908, config.max_power_mw)
	ok = ok && g13_globals_put_u32(mut data, 0x890c, max_scaled)
	ok = ok && g13_globals_put_u32(mut data, 0x8910, max_scaled)
	ok = ok && g13_globals_put_u32(mut data, 0x891c, max_scaled)
	ok = ok && g13_globals_put_u32(mut data, 0x8924, power.power_zone_count)
	ok = ok && g13_globals_put_u32(mut data, 0x8928, avg_periods)
	ok = ok && g13_globals_put_u32(mut data, 0x892c, avg_ki_dt)
	ok = ok && g13_globals_put_u32(mut data, 0x8930, power.avg_power_kp_f32)
	ok = ok && g13_globals_put_u32(mut data, 0x8934, power.avg_power_min_duty_cycle)
	ok = ok && g13_globals_put_u32(mut data, 0x8938, power.avg_power_target_filter_tc)
	ok = ok && g13_globals_set_power_zones(mut data, power)
	ok = ok && g13_globals_put_u32(mut data, 0x89bc, 9880)
	ok = ok && g13_globals_put_u32(mut data, 0x89c0, release_temp)
	ok = ok && g13_globals_put_u32(mut data, 0x89c4, u32(-220))
	ok = ok && g13_globals_put_u32(mut data, 0x89c8, prop_delta)
	ok = ok && g13_globals_put_u32(mut data, 0x89cc, power.fast_die0_proportional_gain_f32)
	ok = ok && g13_globals_put_u32(mut data, 0x89d0, fast_ki_dt)
	ok = ok && g13_globals_put_u32(mut data, 0x89e0, 1)
	ok = ok && g13_globals_put_u32(mut data, 0x89e4, config.max_power_mw)
	ok = ok && g13_globals_put_u32(mut data, 0x89e8, power.ppm_kp_f32)
	ok = ok && g13_globals_put_u32(mut data, 0x89ec, ppm_ki_dt)
	ok = ok && g13_globals_set_t8103_shared_data(mut data)
	ok = ok && g13_globals_put_u32(mut data, 0x900c, 1)
	// fault_control remains zero (hard faults), matching the reference default.
	ok = ok && g13_globals_put_u32(mut data, 0x10e84, 1)
	ok = ok && g13_globals_put_u32(mut data, 0x11020, 40)
	ok = ok && g13_globals_put_u32(mut data, 0x11024, 10)
	ok = ok && g13_globals_put_u32(mut data, 0x11028, 250)
	ok = ok && g13_globals_put_u32(mut data, 0x11030, power.idle_off_delay_ms)
	ok = ok && g13_globals_put_u32(mut data, 0x11034, power.fender_idle_off_delay_ms)
	ok = ok && g13_globals_put_u32(mut data, 0x11038, power.fw_early_wake_timeout_ms)
	ok = ok && g13_globals_put_u32(mut data, 0x118e0, 40)
	return ok
}
