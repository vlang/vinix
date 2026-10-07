module g17power

import math
import math.big
import strconv
import traceanalysis as j

#flag -ffp-contract=off

pub const q_bits = 40
pub const temperature_c = 110.0

pub fn binary32(value f64) !f64 {
	encoded := f32(value)
	if !math.is_inf(value, 0) && math.is_inf(f64(encoded), 0) {
		return error('float too large to pack with f format')
	}
	return f64(encoded)
}

pub fn f32_bits(value f64) !u32 { return math.f32_bits(f32(binary32(value)!)) }

pub fn bits_f32(value u32) f64 { return f64(math.f32_from_bits(value)) }

pub fn powf(base f64, exponent f64) f64 { return f64(math.powf(f32(base), f32(exponent))) }

pub fn f32_mul(left f64, right f64) !f64 { return binary32(binary32(left)! * binary32(right)!)! }

pub fn voltage_f32(millivolts int) !f64 {
	// The producer performs UCVTF S followed by FDIV S with 1000.0f.
	return binary32(binary32(f64(millivolts))! / binary32(1000.0)!)!
}

fn voltage_integer_f32(millivolts big.Integer) !f64 {
	value := floating(j.Value(j.Number{millivolts.str()}))!
	if math.is_inf(value, 0) { return error('int too large to convert to float') }
	return binary32(binary32(value)! / binary32(1000.0)!)!
}

pub fn leakage_factor(record []f64, millivolts int) !f64 {
	if record.len != 11 { return error('G17 leakage record no longer has 11 doubles') }
	return leakage_at_voltage(record, voltage_f32(millivolts)!)
}

fn leakage_at_voltage(record []f64, voltage f64) !f64 {
	if record.len != 11 { return error('G17 leakage record no longer has 11 doubles') }
	c1, c2, c3, c4, c5 := record[1], record[2], record[3], record[4], record[5]
	c6, c7, c8, c9, c10 := record[6], record[7], record[8], record[9], record[10]
	delta := temperature_c - 105.0
	first := checked_pow(2.0, divided(delta, c1)!)!
	second := checked_pow(divided(math.min(voltage, c7), math.min(c7, 0.75))!, c4 * (1.0 - c5 * delta / 20.0))!
	linear := divided(math.min(math.min(voltage, c7), c6), math.min(math.min(c7, c6), 0.75))!
	third := checked_pow(1.0 + c2 * (1.0 - c3 * delta / 20.0), (math.max(voltage, c6) - math.max(c6, 0.75)) / 0.05)!
	fourth := checked_pow(c9, c8 * math.max(voltage - 1.06, 0.0) * (1.0 + c10 * delta * delta / (temperature_c + 273.15)))!
	return first * second * linear * third * fourth
}

fn divided(left f64, right f64) !f64 {
	if right == 0 { return error('float division by zero') }
	return left / right
}

fn checked_pow(base f64, exponent f64) !f64 {
	result := math.pow(base, exponent)
	if math.is_nan(result) && !math.is_nan(base) && !math.is_nan(exponent) {
		return error('math domain error')
	}
	if math.is_inf(result, 0) && !math.is_inf(base, 0) && !math.is_inf(exponent, 0) {
		return error(if base == 0 { 'math domain error' } else { 'math range error' })
	}
	return result
}

pub fn q40(value f64) !big.Integer {
	encoded := math.round_to_even(value * f64(u64(1) << q_bits))
	if math.is_nan(encoded) { return error('cannot convert float NaN to integer') }
	if math.is_inf(encoded, 0) { return error('cannot convert float infinity to integer') }
	if encoded < 0 || encoded >= 18446744073709551616.0 {
		return error('Q24.40 value is out of range: ${float_text(value)}')
	}
	return big.integer_from_u64(u64(encoded))
}

fn float_text(value f64) string { return j.string_value(j.Value(j.Number{value.str()})) }

fn small(value big.Integer) u64 { return strconv.parse_uint(value.str(), 10, 64) or { panic(err) } }

fn floor_div(value big.Integer, divisor big.Integer) big.Integer {
	quotient, remainder := value.div_mod(divisor)
	return if value.signum < 0 && remainder.signum != 0 { quotient - big.one_int } else { quotient }
}

pub fn q40_to_f32_bits(value big.Integer) !u32 {
	if value == big.zero_int { return 0 }
	position := value.bit_len() - 1
	mut exponent := position - q_bits
	if exponent < -126 || exponent > 127 {
		return error('Q24.40 value is outside the normal binary32 range')
	}
	mut significand := big.zero_int
	if position <= 23 {
		significand = value.left_shift(u32(23 - position))
	} else {
		shift := position - 23
		divisor := big.one_int.left_shift(u32(shift))
		significand = floor_div(value, divisor)
		remainder := value - significand * divisor
		halfway := big.one_int.left_shift(u32(shift - 1))
		if remainder > halfway || (remainder == halfway && significand % big.integer_from_int(2) != big.zero_int) {
			significand += big.one_int
			if significand == big.one_int.left_shift(24) {
				significand = significand.right_shift(1)
				exponent++
			}
		}
	}
	modulus := big.one_int.left_shift(23)
	mut fraction := significand % modulus
	if fraction.signum < 0 { fraction += modulus }
	return u32((exponent + 127) << 23) | u32(small(fraction))
}

pub fn f32_bits_to_q40(value u32) !big.Integer {
	if value == 0 { return big.zero_int }
	exponent := (value >> 23) & 255
	if value >> 31 != 0 || exponent == 0 || exponent == 255 {
		return error('only positive normal binary32 values are supported')
	}
	significand := big.integer_from_u64(u64((u32(1) << 23) | (value & 0x7fffff)))
	shift := int(exponent) - 110
	if shift >= 0 { return significand.left_shift(u32(shift)) }
	divisor := big.one_int.left_shift(u32(-shift))
	if significand % divisor != big.zero_int {
		return error('binary32 value is not exactly representable in Q24.40')
	}
	return significand / divisor
}

pub fn q40_mul(left big.Integer, right big.Integer) big.Integer {
	return floor_div(left * right, big.one_int.left_shift(q_bits))
}

pub fn f32_mul_bits(left u32, right u32) !u32 {
	return q40_to_f32_bits(q40_mul(f32_bits_to_q40(left)!, f32_bits_to_q40(right)!))
}

pub fn f32_add_bits(left u32, right u32) !u32 {
	return q40_to_f32_bits(f32_bits_to_q40(left)! + f32_bits_to_q40(right)!)
}

pub fn u32_to_f32_bits(value u32) !u32 {
	return q40_to_f32_bits(big.integer_from_u64(u64(value)).left_shift(q_bits))
}

pub fn f32_bits_to_u32_trunc(value u32) big.Integer {
	if value == 0 { return big.zero_int }
	exponent := int((value >> 23) & 255) - 127
	significand := big.integer_from_u64(u64((u32(1) << 23) | (value & 0x7fffff)))
	if exponent < 0 { return big.zero_int }
	return if exponent >= 23 {
		significand.left_shift(u32(exponent - 23))
	} else {
		significand.right_shift(u32(23 - exponent))
	}
}

fn float_integer(value f64) !big.Integer {
	if math.is_nan(value) { return error('cannot convert float NaN to integer') }
	if math.is_inf(value, 0) { return error('cannot convert float infinity to integer') }
	bits := math.f64_bits(value)
	exponent := int((bits >> 52) & 2047) - 1023
	if exponent < 0 { return big.zero_int }
	significand := big.integer_from_u64((u64(1) << 52) | (bits & 0xfffffffffffff))
	integer := if exponent >= 52 {
		significand.left_shift(u32(exponent - 52))
	} else {
		significand.right_shift(u32(52 - exponent))
	}
	return if bits >> 63 != 0 { integer.neg() } else { integer }
}

pub fn threshold_quarters(record []f64) !big.Integer {
	if record.len == 0 { return error('list index out of range') }
	if record[0] < 0 { return big.integer_from_u64(0xffffffff) }
	return float_integer(math.ceil(record[0] * 4.0))
}

pub fn leakage_bucket(records [][]f64, quarters int) !int {
	for index, record in records {
		threshold := threshold_quarters(record)!
		if threshold == big.integer_from_u64(0xffffffff) || big.integer_from_int(quarters) < threshold {
			return index
		}
	}
	return error('leakage model has no catch-all bucket')
}

pub fn fixed_leakage_q40(records [][]f64, quarters int, millivolts int) !big.Integer {
	record := records[leakage_bucket(records, quarters)!]
	return floor_div(q40(leakage_factor(record, millivolts)!)! * big.integer_from_int(quarters), big.integer_from_int(4))
}

pub fn reference_afr_power(records [][]f64, quarters int, millivolts int, megahertz u32) !int {
	voltage := voltage_f32(millivolts)!
	leakage := binary32(f64(quarters) / 4.0)! * leakage_factor(records[leakage_bucket(records, quarters)!], millivolts)!
	dynamic := f32_mul(f32_mul(powf(voltage, binary32(1.0)!), binary32(12.29)!)!, f64(megahertz))!
	return int(binary32(math.min(leakage + dynamic, 24800.0) * voltage)!)
}

pub fn fixed_afr_power(records [][]f64, quarters int, millivolts int, megahertz u32) !big.Integer {
	voltage := f32_bits(voltage_f32(millivolts)!)!
	dynamic := f32_mul_bits(f32_mul_bits(voltage, f32_bits(12.29)!)!, u32_to_f32_bits(megahertz)!)!
	mut total := fixed_leakage_q40(records, quarters, millivolts)! + f32_bits_to_q40(dynamic)!
	limit := big.integer_from_int(24800).left_shift(q_bits)
	if total > limit { total = limit }
	return f32_bits_to_u32_trunc(q40_to_f32_bits(q40_mul(total, f32_bits_to_q40(voltage)!))!)
}

pub fn reference_main_power(records [][]f64, quarters int, millivolts int, megahertz u32, enabled_units u32, afr_share u32) !int {
	voltage := voltage_f32(millivolts)!
	leakage := binary32(f64(quarters) / 4.0)! * leakage_factor(records[leakage_bucket(records, quarters)!], millivolts)!
	enabled_scale := binary32(binary32(f64(enabled_units))! / binary32(10.0)!)!
	dynamic := f32_mul(f32_mul(f32_mul(powf(voltage, binary32(1.28)!), binary32(20.15)!)!, f64(megahertz))!, enabled_scale)!
	total := math.min(binary32(leakage + dynamic)!, binary32(48500.0)!)
	return int(binary32(binary32(total * voltage)! + binary32(f64(afr_share))!)!)
}

pub fn fixed_main_power(records [][]f64, quarters int, millivolts int, megahertz u32, enabled_units u32, afr_share u32) !big.Integer {
	voltage := f32_bits(voltage_f32(millivolts)!)!
	coefficient := f32_bits(f32_mul(powf(bits_f32(voltage), binary32(1.28)!), binary32(20.15)!)!)!
	mut dynamic := f32_mul_bits(coefficient, u32_to_f32_bits(megahertz)!)!
	enabled_scale := q40_to_f32_bits(big.integer_from_u64(u64(enabled_units)).left_shift(q_bits) / big.integer_from_int(10))!
	dynamic = f32_mul_bits(dynamic, enabled_scale)!
	total := fixed_leakage_q40(records, quarters, millivolts)! + f32_bits_to_q40(dynamic)!
	mut total_bits := q40_to_f32_bits(total)!
	if total_bits > f32_bits(48500.0)! { total_bits = f32_bits(48500.0)! }
	scaled := f32_add_bits(f32_mul_bits(total_bits, voltage)!, u32_to_f32_bits(afr_share)!)!
	return f32_bits_to_u32_trunc(scaled)
}
