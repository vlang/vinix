// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module fw

import gpu.agx.hw

// The fields 13.5 adds to HwDataA and Globals.
//
// Moving the existing offsets is only half of the ABI: 13.5 also grows the
// structures, and most of what it adds stays zero. These are the ones that do
// not, taken from m1n1's initdata.rs at V13_5 -- see
// `make -C tools/agx-re report-g13-initdata-layout`, which lists every added
// field and separates the ones needing a value from the ones that do not, and
// from the three that cannot apply to a base M1 at all.
//
// Offsets here are 13.5 offsets and are written raw: these fields have no 12.3
// counterpart to translate from.

// Scalars the callers have already derived. Passing them keeps this from
// recomputing values whose rounding has to match what the rest of the blob was
// built with.
pub struct G13V135Inputs {
pub:
	period_ms             u32
	period_s_f32          u32
	base_clock_khz        u32
	clocks_per_period     u32
	ppm_filter_tc_periods u32
	avg_filter_tc_periods u32
	max_pstate_scaled     u32
}

// 13.5 grows HwDataA by a system-engagement control block. Every value it wants
// is one this tree already reads from the device tree as apple,se-*, whose
// defaults match m1n1's t8103 configuration exactly.
fn g13_hwdata_a_write_se_block(mut data G13HwDataA, abi hw.FirmwareAbi,
	power &hw.G13PowerConfig, inputs G13V135Inputs) bool {
	if power.se_filter_time_constant == 0 || power.se_filter_time_constant_1 == 0 {
		return false
	}
	filter_a := firmware_fraction_to_f32_bits(1, power.se_filter_time_constant) or {
		return false
	}
	filter_1_a := firmware_fraction_to_f32_bits(1, power.se_filter_time_constant_1) or {
		return false
	}
	filter_a_neg := firmware_f32_one_minus_bits(filter_a) or { return false }
	filter_1_a_neg := firmware_f32_one_minus_bits(filter_1_a) or { return false }
	ki_dt := firmware_f32_multiply_bits(power.se_ki_f32, inputs.period_s_f32) or {
		return false
	}
	ki_1_dt := firmware_f32_multiply_bits(power.se_ki_1_f32, inputs.period_s_f32) or {
		return false
	}
	// m1n1 spells these as float literals; deriving them keeps the bit pattern
	// honest rather than pasting one in.
	f32_65536 := firmware_u32_to_f32_bits(65536) or { return false }
	f32_8000 := firmware_u32_to_f32_bits(8000) or { return false }

	tc_clks := g13_checked_mul_u32(power.se_filter_time_constant, inputs.clocks_per_period) or {
		return false
	}
	tc_1_clks := g13_checked_mul_u32(power.se_filter_time_constant_1, inputs.clocks_per_period) or {
		return false
	}
	tc_ms := g13_checked_mul_u32(power.se_filter_time_constant, inputs.period_ms) or {
		return false
	}
	tc_1_ms := g13_checked_mul_u32(power.se_filter_time_constant_1, inputs.period_ms) or {
		return false
	}

	mut ok := true
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_unk_38_offset, 4)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_unk_3c_offset, 8000)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_gpu_se_inactive_threshold_offset, power.se_inactive_threshold)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_gpu_se_engagement_criteria_offset, u32(power.se_engagement_criteria))
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_gpu_se_reset_criteria_offset, power.se_reset_criteria)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_unk_54_offset, 50)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_unk_58_offset, 1)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_gpu_se_filter_a_neg_offset, filter_a_neg)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_gpu_se_filter_1_a_neg_offset, filter_1_a_neg)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_gpu_se_filter_a_offset, filter_a)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_gpu_se_filter_1_a_offset, filter_1_a)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_gpu_se_ki_dt_offset, ki_dt)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_gpu_se_ki_1_dt_offset, ki_1_dt)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_unk_7c_offset, f32_65536)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_gpu_se_kp_offset, power.se_kp_f32)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_gpu_se_kp_1_offset, power.se_kp_1_f32)
	// 100 at 13.3 and above, 40 below it. This tree only builds 13.5.
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_unk_8c_offset, 100)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_max_pstate_scaled_1_offset, inputs.max_pstate_scaled)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_unk_9c_offset, f32_8000)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_unk_a0_offset, 1400)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_gpu_se_filter_time_constant_ms_offset, tc_ms)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_gpu_se_filter_time_constant_1_ms_offset, tc_1_ms)
	ok = ok && g13_hwdata_a_store_u64(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_gpu_se_filter_time_constant_clks_offset, u64(tc_clks))
	ok = ok && g13_hwdata_a_store_u64(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_gpu_se_filter_time_constant_1_clks_offset, u64(tc_1_clks))
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_unk_c4_offset, f32_65536)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_unk_114_offset, f32_65536)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_unk_124_offset, 40)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_unk_e10_0_max_pstate_scaled_2_offset, inputs.max_pstate_scaled)
	return ok
}

pub fn g13_hwdata_a_write_v13_5_additions(mut data G13HwDataA, abi hw.FirmwareAbi,
	power &hw.G13PowerConfig, inputs G13V135Inputs) bool {
	if abi != .v13_5_partial {
		return true
	}
	ppm_tc_ms := g13_checked_mul_u32(inputs.ppm_filter_tc_periods, inputs.period_ms) or {
		return false
	}
	avg_tc_ms := g13_checked_mul_u32(inputs.avg_filter_tc_periods, inputs.period_ms) or {
		return false
	}
	ppm_tc_clks := g13_checked_mul_u32(ppm_tc_ms, inputs.base_clock_khz) or { return false }
	avg_tc_clks := g13_checked_mul_u32(avg_tc_ms, inputs.base_clock_khz) or { return false }
	avg_target_ms := g13_checked_mul_u32(inputs.period_ms, power.avg_power_target_filter_tc) or {
		return false
	}
	avg_target_clks := g13_checked_mul_u32(avg_target_ms, inputs.base_clock_khz) or {
		return false
	}

	mut ok := true
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_clocks_per_period_2_offset, inputs.clocks_per_period)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_ppm_filter_tc_clks_offset, ppm_tc_clks)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_avg_power_target_filter_tc_clks_offset, avg_target_clks)
	ok = ok && g13_hwdata_a_put_raw_u32(mut data, abi, g13_v13_5_hwdata_a_avg_power_filter_tc_clks_offset, avg_tc_clks)
	return ok && g13_hwdata_a_write_se_block(mut data, abi, power, inputs)
}

// Globals' additions are constants, bar the standby timer. m1n1's t8103
// configuration leaves unk_hws2_4 unset and unk_hws2_24 zero, so both stay at
// the zero the buffer already holds.
pub fn g13_globals_write_v13_5_additions(mut data G13Globals, abi hw.FirmwareAbi,
	power &hw.G13PowerConfig) bool {
	if abi != .v13_5_partial {
		return true
	}
	mut ok := true
	ok = ok && g13_globals_put_raw_u32(mut data, abi, g13_v13_5_globals_unk_24_0_offset, 3000)
	ok = ok && g13_globals_put_raw_u32(mut data, abi, g13_v13_5_globals_debug_offset, 0)
	// G13 leaves this generation-gated word clear; only G14X and newer set it.
	ok = ok && g13_globals_put_raw_u32(mut data, abi, g13_v13_5_globals_unk_2c_0_offset, 0)
	ok = ok && g13_globals_put_raw_u32(mut data, abi, g13_v13_5_globals_unk_89f4_8_offset, 1)
	ok = ok && g13_globals_put_raw_u32(mut data, abi, g13_v13_5_globals_idle_off_standby_timer_offset, power.idle_off_standby_timer)
	ok = ok && g13_globals_put_raw_u32(mut data, abi, g13_v13_5_globals_unk_9010_0_offset, 1)
	ok = ok && g13_globals_put_raw_u32(mut data, abi, g13_v13_5_globals_unk_1102c_0_offset, 1)
	ok = ok && g13_globals_put_raw_u32(mut data, abi, g13_v13_5_globals_unk_1102c_4_offset, 1)
	ok = ok && g13_globals_put_raw_u32(mut data, abi, g13_v13_5_globals_unk_1102c_8_offset, 100)
	ok = ok && g13_globals_put_raw_u32(mut data, abi, g13_v13_5_globals_unk_1102c_c_offset, 1)
	ok = ok && g13_globals_put_raw_u32(mut data, abi, g13_v13_5_globals_cl_kill_timeout_ms_offset, 50)
	ok = ok && g13_globals_put_raw_u32(mut data, abi, g13_v13_5_globals_unk_11edc_offset, 0)
	ok = ok && g13_globals_put_raw_u32(mut data, abi, g13_v13_5_globals_unk_11efc_offset, 0)
	return ok
}
