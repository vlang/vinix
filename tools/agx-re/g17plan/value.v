module g17plan

import traceanalysis { Value }
import json2
import math.big
import strconv

pub const descriptor_bytes = 0x15b0
pub const word_mask = ~u64(0)
const unresolved_code = 17

pub fn decode(text string) !map[string]Value {
	return traceanalysis.object(traceanalysis.decode(text)!)
}

fn val(node map[string]Value, key string) Value { return node[key] or { Value(json2.null) } }

fn obj(node map[string]Value, key string) map[string]Value { return val(node, key).as_map() }

fn text(node map[string]Value, key string) string {
	v := val(node, key)
	return match v {
		string { v }
		else { '' }
	}
}

fn truth(item Value) bool {
	return match item {
		bool { item }
		json2.Null { false }
		string { item.len > 0 }
		[]Value { item.len > 0 }
		map[string]Value { item.len > 0 }
		traceanalysis.Number {
			if item.text.contains_any('.eE') {
				strconv.atof64(item.text) or { return false } != 0
			} else {
				(big.integer_from_string(item.text) or { return false }).signum != 0
			}
		}
		else { item.u64() != 0 }
	}
}

fn default_value(node map[string]Value, key string, fallback Value) Value {
	return node[key] or { fallback }
}

fn required(node map[string]Value, key string) !Value {
	return node[key] or { return error(traceanalysis.quoted(key)) }
}

fn required_obj(node map[string]Value, key string) !map[string]Value {
	item := required(node, key)!
	return match item {
		map[string]Value { item }
		else { return error('${key} must be an object') }
	}
}

fn integer_text(item Value, name string) !string {
	return match item {
		traceanalysis.Number {
			if item.text.contains_any('.eE') { return error('${name} must be an integer') }
			item.text
		}
		int, i64, u8, u32, u64 { item.str() }
		else { return error('${name} must be an integer') }
	}
}

// Python integers are unbounded; evaluate their low word without a float or
// signed-width intermediate. Offsets and counts have separate checked paths.
pub fn masked_integer(item Value, name string) !u64 {
	number := big.integer_from_string(integer_text(item, name)!)!
	modulus := big.integer_from_u64(word_mask) + big.one_int
	_, rest := number.div_mod(modulus)
	positive := if rest < big.zero_int { rest + modulus } else { rest }
	return strconv.parse_uint(positive.str(), 10, 64)!
}

fn int_value(item Value, name string) !int {
	number := big.integer_from_string(integer_text(item, name)!)!
	if number < big.integer_from_string('-9223372036854775808')! || number > big.integer_from_u64(0x7fffffffffffffff) {
		return error('${name} is outside signed64')
	}
	return int(strconv.parse_int(number.str(), 10, 64)!)
}

fn field(node map[string]Value, key string, name string) !int {
	return int_value(required(node, key)!, name)
}

fn expression_width(node map[string]Value, label string) !int {
	return int_value(default_value(node, 'bytes', Value(8)), label)
}

fn mask_bits(bits int) u64 {
	return if bits >= 64 {
		word_mask
	} else if bits <= 0 {
		u64(0)
	} else {
		(u64(1) << bits) - 1
	}
}

fn width_mask(bytes int) !u64 {
	if bytes !in [1, 2, 4, 8] { return error('unsupported expression width ${bytes}') }
	return mask_bits(bytes * 8)
}

fn unresolved(message string) IError { return error_with_code(message, unresolved_code) }

fn repr(item Value) string {
	return match item {
		string { traceanalysis.quoted(item) }
		else { traceanalysis.string_value(item) }
	}
}

fn copy_object(node map[string]Value) map[string]Value {
	mut output := map[string]Value{}
	for key, item in node { output[key] = item }
	return output
}

fn deep_copy(item Value) Value {
	return match item {
		map[string]Value {
			mut output := map[string]Value{}
			for key, entry in item { output[key] = deep_copy(entry) }
			Value(output)
		}
		[]Value {
			mut output := []Value{}
			for entry in item { output << deep_copy(entry) }
			Value(output)
		}
		else { item }
	}
}

fn number_array(values []int) []Value { return values.map(Value(it)) }

fn offsets(item Value) ![]int {
	mut result := []int{}
	for entry in item.arr() {
		offset := int_value(entry, 'producer offset')!
		if offset !in result { result << offset }
	}
	return result
}

fn same_set(a []int, b []int) bool { return a.len == b.len && a.all(it in b) }

fn offset_union(a []int, b []int) []int {
	mut result := a.clone()
	for n in b { if n !in result { result << n } }
	return result
}

fn sort_offsets(items []Value) ![]map[string]Value {
	mut result := []map[string]Value{}
	for item in items { result << traceanalysis.object(item)! }
	result.sort_with_compare(offset_order)
	return result
}

fn json_quote(source string) string {
	// json.dumps defaults to ensure_ascii=True. Escape UTF-16 surrogate pairs
	// explicitly while keeping ordinary ASCII escaping in json2.
	mut output := '"'
	for r in source.runes() {
		if r >= 127 {
			if r <= 0xffff {
				output += '\\u${int(r):04x}'
			} else {
				n := int(r) - 0x10000
				output += '\\u${(0xd800 + (n >> 10)):04x}\\u${(0xdc00 + (n & 1023)):04x}'
			}
		} else {
			encoded := json2.encode(r.str())
			output += encoded[1..encoded.len - 1]
		}
	}
	return output + '"'
}

pub fn encode(item Value, pretty bool) string { return encode_depth(item, pretty, 0) }

fn encode_depth(item Value, pretty bool, depth int) string {
	match item {
		map[string]Value {
			record := item.as_map()
			mut keys := record.keys()
			keys.sort()
			mut parts := []string{}
			for key in keys {
				parts << json_quote(key) + if pretty { ': ' } else { ':' } + encode_depth(val(record, key), pretty, depth + 1)
			}
			if !pretty || parts.len == 0 { return '{' + parts.join(',') + '}' }
			padding := '  '.repeat(depth + 1)
			return '{\n' + padding + parts.join(',\n' + padding) + '\n' + '  '.repeat(depth) + '}'
		}
		[]Value {
			mut parts := []string{}
			for child in item { parts << encode_depth(child, pretty, depth + 1) }
			if !pretty || parts.len == 0 { return '[' + parts.join(',') + ']' }
			padding := '  '.repeat(depth + 1)
			return '[\n' + padding + parts.join(',\n' + padding) + '\n' + '  '.repeat(depth) + ']'
		}
		string { return json_quote(item) }
		int, i64, u8, u32, u64 { return item.str() }
		bool { return if item { 'true' } else { 'false' } }
		json2.Null { return 'null' }
		traceanalysis.Number { return item.text }
	}
}

fn left_shift_kind(item Value) bool {
	return match item {
		json2.Null { true }
		bool { !item }
		string { item == 'lsl' }
		traceanalysis.Number { strconv.atof64(item.text) or { return false } == 0 }
		else { item.u64() == 0 }
	}
}

fn offset_order(a &map[string]Value, b &map[string]Value) int {
	x := val(*a, 'producer_offset').int()
	y := val(*b, 'producer_offset').int()
	return if x < y {
		-1
	} else if x > y {
		1
	} else {
		0
	}
}

fn signed_string_integer(source string, name string) !big.Integer {
	digits := source.trim_space()
	if digits.starts_with('-') {
		unsigned := digits[1..]
		if unsigned == '' || unsigned.starts_with('+') || unsigned.starts_with('-') {
			return error('${name} is not an integer')
		}
		return traceanalysis.integer(Value(unsigned), name)!.neg()
	}
	return traceanalysis.integer(Value(digits), name)
}

fn is_null(item Value) bool {
	return match item {
		json2.Null { true }
		else { false }
	}
}
