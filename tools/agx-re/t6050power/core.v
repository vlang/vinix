module t6050power

import appleadt as a
import g17decode as g
import math
import math.big
import traceanalysis as j

fn C.strtod(&char, &&char) f64

// Function addresses retain their integer width until an instruction decoder
// applies the original modulo-64-bit address semantics. Code is borrowed for
// the synchronous proof; returned metadata contains no pointer into it.
pub struct Function {
pub:
	address j.Value
	code    []u8
}

fn function(functions map[string]Function, name string) !Function {
	return functions[name] or { return error('KeyError: ' + name) }
}

fn encoded_words(words []u32) []u8 {
	mut data := []u8{cap: words.len * 4}
	for word in words { data << [u8(word), u8(word >> 8), u8(word >> 16), u8(word >> 24)] }
	return data
}

fn branch_count(body Function, target j.Value) !int {
	// Python's original address arithmetic happens only for decoded B/BL words.
	// A branch-free body still returns zero with a malformed address. Do not let
	// the JSON decoder coerce a string or integral float into an integer here.
	for offset := 0; offset + 4 <= body.code.len; offset += 4 {
		word := u32(body.code[offset]) | (u32(body.code[offset + 1]) << 8) |
			(u32(body.code[offset + 2]) << 16) | (u32(body.code[offset + 3]) << 24)
		if word & 0x7c000000 != 0x14000000 { continue }
		match body.address {
			bool, int, i64, u8, u32, u64 {}
			j.Number {
				if body.address.text.contains_any('.eE') {
					return error("TypeError: unsupported operand type(s) for &: 'float' and 'int'")
				}
			}
			string { return error('TypeError: can only concatenate str (not "int") to str') }
			[]j.Value { return error('TypeError: can only concatenate list (not "int") to list') }
			map[string]j.Value {
				return error("TypeError: unsupported operand type(s) for +: 'dict' and 'int'")
			}
			else {
				return error("TypeError: unsupported operand type(s) for +: 'NoneType' and 'int'")
			}
		}
		break
	}
	return a.query(body.code, 'direct_branch_count', {
		'function_address': body.address
		'target':           target
	})!.int()
}

fn branch_target_exists(body Function, target j.Value) !bool {
	count := branch_count(body, target)!
	// The original membership test hashes its target even when the set is empty.
	match target {
		map[string]j.Value { return error("TypeError: unhashable type: 'dict'") }
		[]j.Value { return error("TypeError: unhashable type: 'list'") }
		else { return count != 0 }
	}
}

fn exact_integer(value j.Value) ?big.Integer {
	match value {
		bool { return big.integer_from_int(if value { 1 } else { 0 }) }
		int, i64, u8, u32, u64 { return g.integer(value) or { return none } }
		j.Number {
			if !value.text.contains_any('.eE') { return g.integer(value) or { return none } }
			parsed := unsafe { C.strtod(&char(value.text.str), nil) }
			bits := math.f64_bits(parsed)
			if bits & 0x7fffffffffffffff == 0 { return big.zero_int }
			exponent := int((bits >> 52) & 0x7ff) - 1023
			if exponent < 0 || exponent == 1024 { return none }
			significand := (bits & 0xfffffffffffff) | (u64(1) << 52)
			mut integer := big.integer_from_u64(significand)
			if exponent >= 52 {
				integer = integer.left_shift(u32(exponent - 52))
			} else {
				shift := u32(52 - exponent)
				if significand & ((u64(1) << shift) - 1) != 0 { return none }
				integer = big.integer_from_u64(significand >> shift)
			}
			return if bits >> 63 != 0 { big.zero_int - integer } else { integer }
		}
		else { return none }
	}
}

fn integer_equal(left j.Value, right j.Value) bool {
	first := exact_integer(left) or { return false }
	second := exact_integer(right) or { return false }
	return first == second
}

fn tuple_equal(values []j.Value, expected []u64) bool {
	if values.len != expected.len { return false }
	for i, value in values {
		if !integer_equal(value, j.Value(expected[i])) { return false }
	}
	return true
}

fn element_repr(value j.Value) string {
	return if value is string { j.quoted(value) } else { j.string_value(value) }
}

fn tuple_repr(values []j.Value) string {
	return '(' + values.map(element_repr(it)).join(', ') + if values.len == 1 {
		',)'
	} else {
		')'
	}
}
