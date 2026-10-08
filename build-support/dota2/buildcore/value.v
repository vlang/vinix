// SPDX-License-Identifier: GPL-2.0-or-later
module buildcore

import encoding.hex
import json2
import math.big
import math.bits

#include <stdlib.h>
fn C.strtod(&char, &&char) f64

pub struct Number {
pub:
	raw string
	integer bool
	identity string
}

pub type Value = []Value | bool | map[string]Value | string | Number | json2.Null

pub struct PolicyError {
pub:
	kind string
	message string
}

pub fn (failure PolicyError) msg() string { return failure.message }
pub fn (failure PolicyError) code() int { return 0 }

// Every value has an explicit transport tag; ordinary dictionaries cannot
// collide with tags. Strings cross as bytes to retain surrogate code points.
pub fn decode_value(value json2.Any) !Value {
	row := value.as_array()
	if row.len == 0 { return error('Empty policy transport value') }
	match row[0].str() {
		'null' { return Value(json2.Null{}) }
		'bool' { return Value(row[1].bool()) }
		'int', 'float' {
			return Value(Number{row[1].str(), row[0].str() == 'int', if row.len > 2 { row[2].str() } else { '' }})
		}
		'str' { return Value(hex.decode(row[1].str())!.bytestr()) }
		'list' {
			mut result := []Value{}
			for item in row[1].as_array() { result << decode_value(item)! }
			return Value(result)
		}
		'dict' {
			mut result := map[string]Value{}
			for item in row[1].as_array() {
				pair := item.as_array()
				result[hex.decode(pair[0].str())!.bytestr()] = decode_value(pair[1])!
			}
			return Value(result)
		}
		else { return error('Unknown policy transport tag') }
	}
}

fn typename(value Value) string {
	return match value {
		[]Value { 'list' }
		map[string]Value { 'dict' }
		bool { 'bool' }
		string { 'str' }
		Number { if value.integer { 'int' } else { 'float' } }
		json2.Null { 'NoneType' }
	}
}

fn get(value Value, key string, fallback Value) !Value {
	if value is map[string]Value { return value[key] or { fallback } }
	return PolicyError{'AttributeError', "'" + typename(value) + "' object has no attribute 'get'"}
}

fn length(value Value) !int {
	match value {
		string { return scalar_length(value) }
		[]Value { return value.len }
		map[string]Value { return value.len }
		else { return PolicyError{'TypeError', "object of type '" + typename(value) + "' has no len()"} }
	}
}

fn scalar_length(text string) int {
	// The bridge emits UTF-8 with surrogatepass. V's rune decoder rejects
	// surrogate encodings, so count their code-point-leading bytes explicitly.
	mut count := 0
	for ch in text.bytes() { if ch & 0xc0 != 0x80 { count++ } }
	return count
}

fn starts(value Value, prefix string) !bool {
	if value is string { return value.starts_with(prefix) }
	return PolicyError{'AttributeError', "'" + typename(value) + "' object has no attribute 'startswith'"}
}

fn truth(value Value) bool {
	return match value {
		bool { value }
		string { value != '' }
		[]Value { value.len != 0 }
		map[string]Value { value.len != 0 }
		json2.Null { false }
		Number { value.raw != '0' && value.raw != '0.0' && value.raw != '-0.0' }
	}
}

fn numeric_int(value Value) !big.Integer {
	if value is bool { return big.integer_from_int(if value { 1 } else { 0 }) }
	if value is Number {
		if value.integer { return big.integer_from_string(value.raw)! }
		f := unsafe { C.strtod(value.raw.str, nil) }
		representation := bits.f64_bits(f)
		exponent := int((representation >> 52) & 0x7ff) - 1023
		if exponent == 1024 { return error('Non-finite number') }
		if f == 0 { return big.integer_from_int(0) }
		if exponent < 0 { return error('Fractional number') }
		mantissa := (representation & 0xfffffffffffff) | (u64(1) << 52)
		mut result := big.integer_from_u64(mantissa)
		if exponent >= 52 {
			result = result.left_shift(u32(exponent - 52))
		} else {
			shift := 52 - exponent
			if mantissa & ((u64(1) << u32(shift)) - 1) != 0 { return error('Fractional number') }
			result = result.right_shift(u32(shift))
		}
		return if representation >> 63 != 0 { big.integer_from_int(0) - result } else { result }
	}
	return error('Not numeric')
}

fn equal(left Value, right Value) bool {
	if left is Number || left is bool {
		if right is Number || right is bool {
			if left is Number && right is Number && !left.integer && !right.integer {
				return unsafe { C.strtod(left.raw.str, nil) } == unsafe { C.strtod(right.raw.str, nil) }
			}
			first := numeric_int(left) or { return false }
			second := numeric_int(right) or { return false }
			return first == second
		}
		return false
	}
	match left {
		string { return right is string && left == right }
		json2.Null { return right is json2.Null }
		[]Value {
			if right !is []Value { return false }
			other_items := right as []Value
			if left.len != other_items.len { return false }
			for i, item in left { if !element_equal(item, other_items[i]) { return false } }
			return true
		}
		map[string]Value {
			if right !is map[string]Value { return false }
			other_items := right as map[string]Value
			if left.len != other_items.len { return false }
			for key, item in left {
				other := other_items[key] or { return false }
				if !element_equal(item, other) { return false }
			}
			return true
		}
		else { return false }
	}
}

fn element_equal(left Value, right Value) bool {
	// Python container comparison checks identity before scalar equality.
	// Standard json.loads reuses its NaN object, though NaN == NaN is false.
	if left is Number && right is Number && left.raw == 'nan' && right.raw == 'nan' && left.identity != '' && left.identity == right.identity { return true }
	return equal(left, right)
}

fn safe_relative(path string) bool { return !path.starts_with('/') && '..' !in path.split('/') }
