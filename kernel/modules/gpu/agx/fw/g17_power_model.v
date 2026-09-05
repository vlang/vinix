module fw

import gpu.agx.hw

// Runtime inputs to the recovered G17C power-matrix producers. The topology
// dimensions come from GPU_ID_CLUSTERCFG and enabled_uscs is the per-column
// population count of the 96-bit hardware core mask.
pub struct G17PowerModelInputs {
pub:
	chip_variant      u32
	group_count       u32
	columns_per_group u32
	column_count      u32
	units_per_column  u32
	enabled_uscs      [g17_leakage_core_capacity]u32
}

fn g17_checked_add_u64(left u64, right u64) ?u64 {
	if right > u64(0xffff_ffff_ffff_ffff) - left {
		return none
	}
	return left + right
}

// Exact low-level implementation of (left * right) >> 40 without relying on
// a 128-bit V integer. Values reaching this helper are positive Q24.40 power
// and voltage quantities, but every intermediate is still checked.
fn g17_q40_mul(left u64, right u64) ?u64 {
	left_high := left >> 32
	left_low := left & 0xffff_ffff
	right_high := right >> 32
	right_low := right & 0xffff_ffff
	high := left_high * right_high
	cross_left := left_high * right_low
	cross_right := left_low * right_high
	if cross_right > u64(0xffff_ffff_ffff_ffff) - cross_left
		|| high > (u64(0xffff_ffff_ffff_ffff) >> 24) {
		return none
	}
	cross := cross_left + cross_right
	low := left_low * right_low
	low_remainder := (low & ((u64(1) << g17_power_model_q_bits) - 1)) +
		((cross & 0xff) << 32)
	mut result := high << 24
	result = g17_checked_add_u64(result, cross >> 8) or { return none }
	result = g17_checked_add_u64(result, low >> g17_power_model_q_bits) or {
		return none
	}
	result = g17_checked_add_u64(result, low_remainder >> g17_power_model_q_bits) or {
		return none
	}
	return result
}

// Round a positive normal Q24.40 number to IEEE-754 binary32, including
// ties-to-even. The returned bits are manipulated as integers throughout;
// no kernel floating-point instruction is emitted.
fn g17_q40_to_f32_bits(value u64) ?u32 {
	if value == 0 {
		return 0
	}
	mut position := u32(0)
	mut scan := value
	for scan > 1 {
		scan >>= 1
		position++
	}
	mut exponent := i32(position) - i32(g17_power_model_q_bits)
	if exponent < -126 || exponent > 127 {
		return none
	}
	mut significand := u64(0)
	if position <= 23 {
		significand = value << (23 - position)
	} else {
		shift := position - 23
		significand = value >> shift
		remainder := value & ((u64(1) << shift) - 1)
		halfway := u64(1) << (shift - 1)
		if remainder > halfway || (remainder == halfway && significand & 1 != 0) {
			significand++
			if significand == u64(1) << 24 {
				significand >>= 1
				exponent++
			}
		}
	}
	if exponent > 127 {
		return none
	}
	return (u32(exponent + 127) << 23) | (u32(significand) & 0x7f_ffff)
}

// Convert the positive normal binary32 values used by Apple's producers to
// Q24.40. All supported voltage/power values are exactly representable at
// this precision; reject any future value that is not.
fn g17_f32_bits_to_q40(value u32) ?u64 {
	if value == 0 {
		return 0
	}
	exponent_bits := (value >> 23) & 0xff
	if value >> 31 != 0 || exponent_bits == 0 || exponent_bits == 0xff {
		return none
	}
	significand := u64((u32(1) << 23) | (value & 0x7f_ffff))
	shift := i32(exponent_bits) - 110
	if shift >= 0 {
		left := u32(shift)
		if left >= 64 || significand > (u64(0xffff_ffff_ffff_ffff) >> left) {
			return none
		}
		return significand << left
	}
	right := u32(-shift)
	if right >= 64 || significand & ((u64(1) << right) - 1) != 0 {
		return none
	}
	return significand >> right
}

fn g17_f32_mul_positive(left u32, right u32) ?u32 {
	if left == 0 || right == 0 {
		return 0
	}
	left_q40 := g17_f32_bits_to_q40(left) or { return none }
	right_q40 := g17_f32_bits_to_q40(right) or { return none }
	product := g17_q40_mul(left_q40, right_q40) or { return none }
	return g17_q40_to_f32_bits(product)
}

fn g17_f32_add_positive(left u32, right u32) ?u32 {
	left_q40 := g17_f32_bits_to_q40(left) or { return none }
	right_q40 := g17_f32_bits_to_q40(right) or { return none }
	sum := g17_checked_add_u64(left_q40, right_q40) or { return none }
	return g17_q40_to_f32_bits(sum)
}

fn g17_u32_to_f32_bits(value u32) ?u32 {
	if value == 0 {
		return 0
	}
	if u64(value) > (u64(0xffff_ffff_ffff_ffff) >> g17_power_model_q_bits) {
		return none
	}
	return g17_q40_to_f32_bits(u64(value) << g17_power_model_q_bits)
}

fn g17_fraction_to_f32_bits(numerator u32, denominator u32) ?u32 {
	if denominator == 0 {
		return none
	}
	if numerator == 0 {
		return 0
	}
	if u64(numerator) > (u64(0xffff_ffff_ffff_ffff) >> g17_power_model_q_bits) {
		return none
	}
	return g17_q40_to_f32_bits((u64(numerator) << g17_power_model_q_bits) /
		u64(denominator))
}

fn g17_f32_bits_to_u32_trunc(value u32) ?u32 {
	if value == 0 {
		return 0
	}
	exponent_bits := (value >> 23) & 0xff
	if value >> 31 != 0 || exponent_bits == 0 || exponent_bits == 0xff {
		return none
	}
	exponent := i32(exponent_bits) - 127
	if exponent < 0 {
		return 0
	}
	if exponent > 31 {
		return none
	}
	significand := u64((u32(1) << 23) | (value & 0x7f_ffff))
	result := if exponent >= 23 {
		significand << u32(exponent - 23)
	} else {
		significand >> u32(23 - exponent)
	}
	if result > 0xffff_ffff {
		return none
	}
	return u32(result)
}

fn g17_power_model_voltage_index(millivolts u32) ?u32 {
	for index := 0; index < g17_power_model_voltage_count; index++ {
		if g17_power_model_voltages_mv[index] == millivolts {
			return u32(index)
		}
	}
	return none
}

fn g17_power_model_bucket(quarters u32, afr bool) ?u32 {
	for bucket := 0; bucket < g17_power_model_bucket_count; bucket++ {
		threshold := if afr {
			g17_power_model_afr_threshold_quarters[bucket]
		} else {
			g17_power_model_vdd_threshold_quarters[bucket]
		}
		if threshold == 0xffff_ffff || quarters < threshold {
			return u32(bucket)
		}
	}
	return none
}

fn g17_leakage_q40(quarters u32, voltage_index u32, afr bool) ?u64 {
	bucket := g17_power_model_bucket(quarters, afr) or { return none }
	index := bucket * u32(g17_power_model_voltage_count) + voltage_index
	factor := if afr {
		g17_power_model_afr_factor_q40[index]
	} else {
		g17_power_model_vdd_factor_q40[index]
	}
	if quarters != 0 && factor > u64(0xffff_ffff_ffff_ffff) / u64(quarters) {
		return none
	}
	return factor * u64(quarters) / 4
}

fn g17_afr_power(quarters u32, millivolts u32, megahertz u32) ?u32 {
	voltage_index := g17_power_model_voltage_index(millivolts) or { return none }
	voltage_bits := g17_power_model_voltage_f32_bits[voltage_index]
	// G17C (variant 0x22) selects 12.29f and the 24800 clamp. powf(V, 1.0f)
	// returns V exactly, so only the two selected float multiplications remain.
	mut dynamic_bits := g17_f32_mul_positive(voltage_bits, 0x4144_a3d7) or {
		return none
	}
	dynamic_bits = g17_f32_mul_positive(dynamic_bits,
		g17_u32_to_f32_bits(megahertz) or { return none }) or { return none }
	mut total_q40 := g17_leakage_q40(quarters, voltage_index, true) or { return none }
	total_q40 = g17_checked_add_u64(total_q40,
		g17_f32_bits_to_q40(dynamic_bits) or { return none }) or { return none }
	clamp_q40 := u64(24800) << g17_power_model_q_bits
	if total_q40 > clamp_q40 {
		total_q40 = clamp_q40
	}
	scaled_q40 := g17_q40_mul(total_q40,
		g17_f32_bits_to_q40(voltage_bits) or { return none }) or { return none }
	return g17_f32_bits_to_u32_trunc(g17_q40_to_f32_bits(scaled_q40) or {
		return none
	})
}

fn g17_main_power(quarters u32, millivolts u32, megahertz u32,
	enabled_uscs u32, afr_share u32) ?u32 {
	voltage_index := g17_power_model_voltage_index(millivolts) or { return none }
	voltage_bits := g17_power_model_voltage_f32_bits[voltage_index]
	// The generated coefficient has already reproduced powf(V, 1.28f) and
	// the immediately following multiplication by 20.15f.
	mut dynamic_bits := g17_power_model_main_dynamic_f32_bits[voltage_index]
	dynamic_bits = g17_f32_mul_positive(dynamic_bits,
		g17_u32_to_f32_bits(megahertz) or { return none }) or { return none }
	dynamic_bits = g17_f32_mul_positive(dynamic_bits,
		g17_fraction_to_f32_bits(enabled_uscs, 10) or { return none }) or { return none }
	mut total_q40 := g17_leakage_q40(quarters, voltage_index, false) or { return none }
	total_q40 = g17_checked_add_u64(total_q40,
		g17_f32_bits_to_q40(dynamic_bits) or { return none }) or { return none }
	mut total_bits := g17_q40_to_f32_bits(total_q40) or { return none }
	// Positive binary32 bit patterns preserve numeric ordering.
	if total_bits > u32(0x473d_7400) { // 48500.0f
		total_bits = 0x473d_7400
	}
	mut power_bits := g17_f32_mul_positive(total_bits, voltage_bits) or { return none }
	power_bits = g17_f32_add_positive(power_bits,
		g17_u32_to_f32_bits(afr_share) or { return none }) or { return none }
	return g17_f32_bits_to_u32_trunc(power_bits)
}

// Reproduce populateMaximumPerformancePowerCS followed by
// populateMaximumPerformancePower and then fill the two 0..100 transfer
// curves in the firmware hardware configuration. State zero is explicitly
// left clear by both Apple producers.
pub fn populate_g17_power_model(mut config G17HardwareConfig, hardware &hw.HwConfig,
	calibration &G17LeakageCalibration, inputs G17PowerModelInputs) bool {
	if inputs.chip_variant != 0x22 || inputs.group_count == 0
		|| inputs.group_count > g17_leakage_group_capacity
		|| inputs.column_count == 0 || inputs.column_count > g17_leakage_core_capacity
		|| inputs.columns_per_group == 0
		|| inputs.column_count / inputs.group_count != inputs.columns_per_group
		|| inputs.column_count % inputs.group_count != 0
		|| inputs.units_per_column == 0 || inputs.units_per_column > 32
		|| calibration.core_count != inputs.column_count
		|| calibration.group_count != inputs.group_count
		|| hardware.perf_state_table_count != inputs.column_count
		|| hardware.afr_perf_states.table_count != inputs.group_count
		|| hardware.perf_state_count != hardware.afr_perf_states.state_count
		|| hardware.perf_state_count < 2
		|| hardware.perf_state_count > g17_performance_state_capacity {
		return false
	}

	mut afr := G17PowerMatrix{
		state_count: hardware.afr_perf_states.state_count
		columns: inputs.group_count
		stride: g17_aux_voltage_table_columns
	}
	for group := u32(0); group < inputs.group_count; group++ {
		for state := u32(1); state < hardware.afr_perf_states.state_count; state++ {
			index := state * g17_aux_voltage_table_columns + group
			voltage := hardware.afr_perf_states.voltages[index]
			megahertz := hardware.afr_perf_states.frequencies[state] / 1_000_000
			afr.values[index] = g17_afr_power(calibration.group_quarters[group],
				voltage, megahertz) or { return false }
		}
	}

	mut primary := G17PowerMatrix{
		state_count: hardware.perf_state_count
		columns: inputs.column_count
		stride: g17_voltage_table_columns
	}
	for column := u32(0); column < inputs.column_count; column++ {
		if inputs.enabled_uscs[column] > inputs.units_per_column {
			return false
		}
		group := column / inputs.columns_per_group
		for state := u32(1); state < hardware.perf_state_count; state++ {
			index := state * g17_voltage_table_columns + column
			voltage := hardware.perf_state_voltages[index]
			megahertz := hardware.perf_state_frequencies[state] / 1_000_000
			afr_share := afr.values[state * g17_aux_voltage_table_columns + group] /
				inputs.columns_per_group
			primary.values[index] = g17_main_power(
				calibration.core_combined_quarters[column], voltage, megahertz,
				inputs.enabled_uscs[column], afr_share) or { return false }
		}
	}
	return populate_g17_linear_power_transfer_tables(mut config, &primary, &afr)
}
