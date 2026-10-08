module g17power

import math.big
import os
import strings
import traceanalysis as j

#include <stdlib.h>

fn C.strtod(text &char, end &&char) f64

pub fn floating(value j.Value) !f64 {
	text := match value {
		j.Number { value.text }
		int, i64, u8, u32, u64 { value.str() }
		else { return error('leakage parameter must be a number') }
	}
	return unsafe { C.strtod(&char(text.str), nil) }
}

pub fn records(value j.Value) ![][]f64 {
	mut result := [][]f64{}
	for row in value.arr() {
		mut record := []f64{}
		for item in row.arr() { record << floating(item)! }
		result << record
	}
	return result
}

// Python int() accepts signed decimal strings, separators and Unicode digits.
fn decimal_digit(r rune) int {
	for zero in [0x30, 0x660, 0x6f0, 0x7c0, 0x966, 0x9e6, 0xa66, 0xae6, 0xb66, 0xbe6, 0xc66, 0xce6,
		0xd66, 0xde6, 0xe50, 0xed0, 0xf20, 0x1040, 0x1090, 0x17e0, 0x1810, 0x1946, 0x19d0, 0x1a80,
		0x1a90, 0x1b50, 0x1bb0, 0x1c40, 0x1c50, 0xa620, 0xa8d0, 0xa900, 0xa9d0, 0xa9f0, 0xaa50,
		0xabf0, 0xff10, 0x104a0, 0x10d30, 0x11066, 0x110f0, 0x11136, 0x111d0, 0x112f0, 0x11450,
		0x114d0, 0x11650, 0x116c0, 0x11730, 0x118e0, 0x11950, 0x11c50, 0x11d50, 0x11da0, 0x16a60,
		0x16b50, 0x1d7ce, 0x1d7d8, 0x1d7e2, 0x1d7ec, 0x1d7f6, 0x1e140, 0x1e2f0, 0x1e950, 0x1fbf0] {
		if int(r) >= zero && int(r) < zero + 10 { return int(r) - zero }
	}
	return -1
}

fn integer_space(r rune) bool {
	return r in [rune(9), 10, 11, 12, 13, 32, 0x85, 0xa0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003,
		0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x2028, 0x2029, 0x202f, 0x205f,
		0x3000]
}

fn decimal_string(text string) !big.Integer {
	mut runes := text.runes()
	for runes.len > 0 && integer_space(runes[0]) { runes.delete(0) }
	for runes.len > 0 && integer_space(runes.last()) { runes.pop() }
	mut negative := false
	if runes.len > 0 && runes[0] in [rune(`+`), `-`] {
		negative = runes[0] == `-`
		runes.delete(0)
	}
	mut digits := ''
	mut separator := false
	for r in runes {
		if r == `_` && digits != '' && !separator {
			separator = true
			continue
		}
		digit := decimal_digit(r)
		if digit < 0 { return error('invalid literal for int() with base 10: ${j.quoted(text)}') }
		digits += digit.str()
		separator = false
	}
	if digits == '' || separator {
		return error('invalid literal for int() with base 10: ${j.quoted(text)}')
	}
	number := big.integer_from_string(digits)!
	return if negative { number.neg() } else { number }
}

pub fn decimal_integer(value j.Value) !big.Integer {
	return match value {
		bool { big.integer_from_int(if value { 1 } else { 0 }) }
		j.Number {
			if value.text.contains_any('.eE') || value.text in ['NaN', 'Infinity', '-Infinity'] {
				float_integer(floating(value)!)!
			} else {
				big.integer_from_string(value.text)!
			}
		}
		string { decimal_string(value)! }
		int, i64, u8, u32, u64 { big.integer_from_string(value.str())! }
		else { return error('DeviceTree voltage is not an integer') }
	}
}

fn decoded_strings_contain(source string, marker string) bool {
	mut start := -1
	mut escaped := false
	for index, byte in source.bytes() {
		if start < 0 {
			if byte == `"` { start = index }
			continue
		}
		if escaped {
			escaped = false
			continue
		}
		if byte == `\\` {
			escaped = true
			continue
		}
		if byte == `"` {
			value := j.decode(source[start..index + 1]) or {
				start = -1
				continue
			}
			match value {
				string {
					if value.contains(marker) { return true }
				}
				else {}
			}
			start = -1
		}
	}
	return false
}

// Python's JSON reader accepts three non-finite numeric constants. Give the
// strict JSON decoder unique string tokens, then restore their numeric kind.
pub fn decode_device_json(source string) !j.Value {
	mut marker := '__vinix_g17_nonfinite_'
	for source.contains(marker) || decoded_strings_contain(source, marker) { marker += '_' }
	mut rewritten := strings.new_builder(source.len)
	mut quoted := false
	mut escaped := false
	mut index := 0
	for index < source.len {
		byte := source[index]
		if quoted {
			rewritten.write_u8(byte)
			if escaped {
				escaped = false
			} else if byte == `\\` {
				escaped = true
			} else if byte == `"` {
				quoted = false
			}
			index++
			continue
		}
		if byte == `"` {
			quoted = true
			rewritten.write_u8(byte)
			index++
			continue
		}
		mut found := false
		for token in ['NaN', 'Infinity', '-Infinity'] {
			end := index + token.len
			if end <= source.len && source[index..end] == token && (index == 0 || source[index - 1] in [
				u8(`:`),
				`[`,
				`,`,
				` `,
				`\t`,
				`\n`,
				`\r`,
			]) && (end == source.len || source[end] in [u8(`]`), `}`, `,`, ` `, `\t`, `\n`, `\r`]) {
				rewritten.write_string('"' + marker + token + '"')
				index = end
				found = true
				break
			}
		}
		if !found {
			rewritten.write_u8(byte)
			index++
		}
	}
	return restore_constants(j.decode(rewritten.str())!, marker)
}

fn restore_constants(value j.Value, marker string) j.Value {
	return match value {
		string {
			if value.starts_with(marker) { j.Value(j.Number{value[marker.len..]}) } else { value }
		}
		[]j.Value {
			mut result := []j.Value{}
			for item in value { result << restore_constants(item, marker) }
			j.Value(result)
		}
		map[string]j.Value {
			mut result := map[string]j.Value{}
			for key, item in value { result[key] = restore_constants(item, marker) }
			j.Value(result)
		}
		else { value }
	}
}

pub fn device_voltages_text(source string) ![]big.Integer {
	document := j.object(decode_device_json(source)!)!
	tree := j.object(j.value(document, 'device_tree'))!
	mut values := []big.Integer{}
	for table in j.value(tree, 'perf_states').arr() {
		for state in table.arr() {
			voltage := decimal_integer(j.value(state.as_map(), 'voltage_mv'))!
			if voltage !in values { values << voltage }
		}
	}
	for domain in ['cs_perf_states', 'afr_perf_states'] {
		for table in j.value(j.value(tree, domain).as_map(), 'tables').arr() {
			for state in table.arr() {
				number := decimal_integer(j.value(state.as_map(), 'voltage_uv'))!
				voltage := floor_div(number, big.integer_from_int(1000))
				if voltage !in values { values << voltage }
			}
		}
	}
	values.sort_with_compare(fn (left &big.Integer, right &big.Integer) int {
		return if *left < *right {
			-1
		} else if *left > *right {
			1
		} else {
			0
		}
	})
	if values.len == 0 || values[0] <= big.zero_int {
		return error('live DeviceTree contains no usable GPU voltages')
	}
	return values
}

pub fn device_voltages(path string) ![]big.Integer {
	return device_voltages_text(os.read_file(path)!)
}

fn fixed_array(name string, kind string, values []big.Integer, width int) string {
	per_line := if width == 8 { 6 } else { 10 }
	mut lines := []string{}
	for offset := 0; offset < values.len; offset += per_line {
		end := if offset + per_line < values.len { offset + per_line } else { values.len }
		mut tokens := []string{}
		for index in offset .. end {
			number := values[index]
			mut digits := number.abs().hex()
			minimum := if width == 8 { 16 } else { 8 }
			sign := if number.signum < 0 { '-' } else { '' }
			if digits.len + sign.len < minimum {
				digits = '0'.repeat(minimum - digits.len - sign.len) + digits
			}
			mut literal := '0x' + sign + digits
			if index == 0 { literal = kind + '(' + literal + ')' }
			tokens << literal
		}
		lines << '\t' + tokens.join(', ') + ','
	}
	return 'const ${name} = [\n' + lines.join('\n') + '\n]!\n'
}

pub fn generated_source(uuid string, voltages []big.Integer, vdd [][]f64, afr [][]f64) !string {
	if vdd.len != 8 || afr.len != 8 {
		return error('G17C variant leakage model no longer has eight buckets')
	}
	mut mv := []big.Integer{}
	mut voltage_bits := []big.Integer{}
	mut main_dynamic := []big.Integer{}
	for voltage in voltages {
		mv << voltage
		voltage_bits << big.integer_from_u64(u64(f32_bits(voltage_integer_f32(voltage)!)!))
	}
	for voltage in voltages {
		main_dynamic << big.integer_from_u64(u64(f32_bits(f32_mul(powf(voltage_integer_f32(voltage)!, binary32(1.28)!), binary32(20.15)!)!)!))
	}
	mut factors := [][]big.Integer{}
	for table in [vdd, afr] {
		mut evaluated := []big.Integer{}
		for record in table {
			for voltage in voltages {
				evaluated << q40(leakage_at_voltage(record, voltage_integer_f32(voltage)!)!)!
			}
		}
		factors << evaluated
	}
	mut thresholds := [][]big.Integer{}
	for table in [vdd, afr] {
		mut limits := []big.Integer{}
		for record in table { limits << threshold_quarters(record)! }
		thresholds << limits
	}
	mut source := '// SPDX-License-Identifier: GPL-2.0-or-later\n' +
		'// Copyright (c) 2026 Alexander Medvednikov\n' +
		'// Code generated by tools/agx-re/generate_g17_power_model.py; DO NOT EDIT.\n' +
		'// Source AGXG17X UUID: ${uuid}\n' +
		'// Voltage set: the native Mac17,6 DeviceTree captured by inspect_macos.py.\n' +
		'// Factors are Q24.40 evaluations of applyLeakageEquation at 110 C.\n\n' +
		'module fw\n\n' +
		'pub const g17_power_model_q_bits = u32(40)\n' +
		'pub const g17_power_model_voltage_count = ${voltages.len}\n' +
		'pub const g17_power_model_bucket_count = 8\n\n'
	arrays := [fixed_array('g17_power_model_voltages_mv', 'u32', mv, 4),
		fixed_array('g17_power_model_voltage_f32_bits', 'u32', voltage_bits, 4),
		fixed_array('g17_power_model_main_dynamic_f32_bits', 'u32', main_dynamic, 4),
		fixed_array('g17_power_model_vdd_threshold_quarters', 'u32', thresholds[0], 4),
		fixed_array('g17_power_model_afr_threshold_quarters', 'u32', thresholds[1], 4),
		fixed_array('g17_power_model_vdd_factor_q40', 'u64', factors[0], 8),
		fixed_array('g17_power_model_afr_factor_q40', 'u64', factors[1], 8)]
	source += arrays.join('\n')
	return source.trim_right('\n') + '\n'
}
