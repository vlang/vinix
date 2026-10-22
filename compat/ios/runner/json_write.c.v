// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math
import encoding.utf8

struct JsonWriter {
	options u64
mut:
	bytes []u8
	path  [65]u64
	nodes int
}

fn (mut writer JsonWriter) append(text string) ! {
	if writer.bytes.len > json_size_limit - text.len {
		return json_failure('JSON output exceeds size limit')
	}
	for byte in text { writer.bytes << byte }
}

fn (mut writer JsonWriter) indent(depth int) ! {
	writer.append('\n')!
	for _ in 0 .. depth { writer.append('  ')! }
}

fn (mut writer JsonWriter) text(text string) ! {
	if !utf8.validate_str(text) { return json_failure('Invalid UTF-8 JSON string') }
	writer.append('"')!
	for byte in text {
		match byte {
			`"` { writer.append('\\"')! }
			`\\` { writer.append('\\\\')! }
			`/` { writer.append(if writer.options & 8 != 0 { '/' } else { '\\/' })! }
			8 { writer.append('\\b')! }
			9 { writer.append('\\t')! }
			10 { writer.append('\\n')! }
			12 { writer.append('\\f')! }
			13 { writer.append('\\r')! }
			else {
				if byte < 32 {
					mut escape := [u8(`\\`), `u`, `0`, `0`, u8(0), 0]!
					alphabet := '0123456789abcdef'
					escape[4] = alphabet[byte >> 4]
					escape[5] = alphabet[byte & 15]
					writer.append(unsafe { tos(&escape[0], escape.len) })!
				} else {
					if writer.bytes.len == json_size_limit {
						return json_failure('JSON output exceeds size limit')
					}
					writer.bytes << byte
				}
			}
		}
	}
	writer.append('"')!
}

fn json_number_double(header &ObjHeader) f64 {
	return if header.is_real {
		header.real_number
	} else if header.unsigned_number {
		f64(u64(header.number))
	} else {
		f64(header.number)
	}
}

fn json_number_equal(a &ObjHeader, b &ObjHeader) bool {
	if a.is_real && b.is_real { return a.real_number == b.real_number }
	if a.is_real || b.is_real {
		integer := if a.is_real { b } else { a }
		value := if a.is_real { a.real_number } else { b.real_number }
		if !math.is_finite(value) || math.floor(value) != value { return false }
		if integer.unsigned_number {
			return value >= 0 && value < 18446744073709551616.0 && u64(value) == u64(integer.number)
		}
		return value >= -9223372036854775808.0 && value < 9223372036854775808.0 && i64(value) == integer.number
	}
	if a.unsigned_number != b.unsigned_number && ((a.number < 0 && !a.unsigned_number) || (b.number < 0 && !b.unsigned_number)) {
		return false
	}
	return a.number == b.number
}

fn (mut writer JsonWriter) numeric(header &ObjHeader) ! {
	mut buffer := [128]u8{}
	if header.image_integer {
		constant_integer_format(header, unsafe { &char(&buffer[0]) }, 128)
		writer.append(ctext(u64(unsafe { &buffer[0] })))!
		return
	}
	if header.cf_boolean {
		writer.append(if header.number != 0 { 'true' } else { 'false' })!
		return
	}
	if !header.is_real {
		if header.unsigned_number {
			C.snprintf(unsafe { &char(&buffer[0]) }, buffer.len, c'%llu', u64(header.number))
		} else {
			C.snprintf(unsafe { &char(&buffer[0]) }, buffer.len, c'%lld', header.number)
		}
	} else {
		value := header.real_number
		if !math.is_finite(value) { return json_failure('Non-finite JSON number') }
		// Foundation emits seventeen significant digits for binary doubles.
		C.snprintf(unsafe { &char(&buffer[0]) }, buffer.len, c'%.17g', value)
	}
	writer.append(ctext(u64(unsafe { &buffer[0] })))!
}

fn (mut writer JsonWriter) value(object u64, depth int) ! {
	if object == 0 || depth > json_depth_limit || writer.nodes == 65536 {
		return json_failure('JSON nesting or node limit exceeded')
	}
	writer.nodes++
	if objc_is_kind(object, ios_runtime.names['NSNull']) {
		writer.append('null')!
		return
	}
	if objc_is_kind(object, ios_runtime.names['NSString']) {
		writer.text(string_text(object))!
		return
	}
	if objc_is_kind(object, ios_runtime.names['NSNumber']) {
		writer.numeric(obj_header(object))!
		return
	}
	dictionary := objc_is_kind(object, ios_runtime.names['NSDictionary'])
	if !dictionary && !objc_is_kind(object, ios_runtime.names['NSArray']) {
		return json_failure('Unsupported JSON object type')
	}
	for i in 0 .. depth {
		if writer.path[i] == object { return json_failure('Cyclic JSON collection') }
	}
	writer.path[depth] = object
	header := obj_header(object)
	if header.cf_raw_values || header.cf_raw_keys || header.items.len > 65536 {
		return json_failure('Unsupported raw JSON collection')
	}
	if dictionary && header.keys.len != header.items.len {
		return json_failure('Invalid JSON dictionary')
	}
	pretty := writer.options & 1 != 0
	writer.append(if dictionary { '{' } else { '[' })!
	mut order := []int{}
	defer { unsafe { order.free() } }
	if dictionary && writer.options & 2 != 0 {
		order = []int{cap: header.keys.len}
		order.flags |= .noslices
		for i, key in header.keys {
			if !objc_is_kind(key, ios_runtime.names['NSString']) {
				return json_failure('JSON dictionary keys must be strings')
			}
			// Locale collation beyond this measured ASCII key profile is explicit.
			for byte in string_text(key) {
				if !((byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`) || (byte >= `0` && byte <= `9`) || byte == `_`) {
					return json_failure('Sorted JSON key collation is outside the ASCII profile')
				}
			}
			order << i
		}
		// Sorting never changes the input dictionary or owns its key objects.
		json_sort_keys(header, mut order)
	}
	for position in 0 .. header.items.len {
		index := if order.len == 0 { position } else { order[position] }
		if position != 0 { writer.append(',')! }
		if pretty { writer.indent(depth + 1)! }
		if dictionary {
			key := header.keys[index]
			if !objc_is_kind(key, ios_runtime.names['NSString']) {
				return json_failure('JSON dictionary keys must be strings')
			}
			writer.text(string_text(key))!
			writer.append(if pretty { ' : ' } else { ':' })!
		}
		writer.value(header.items[index], depth + 1)!
	}
	if pretty {
		if header.items.len == 0 { writer.append('\n')! }
		writer.indent(depth)!
	}
	writer.append(if dictionary { '}' } else { ']' })!
}

fn json_write(object u64, options u64) !u64 {
	if options & ~u64(15) != 0 { return json_failure('JSON writing options are not implemented') }
	if options & 4 == 0 && !objc_is_kind(object, ios_runtime.names['NSArray']) && !objc_is_kind(object, ios_runtime.names['NSDictionary']) {
		return json_failure('JSON fragments require the fragments option')
	}
	mut writer := JsonWriter{ options: options, bytes: []u8{cap: 256} }
	writer.bytes.flags |= .noslices
	defer { unsafe { writer.bytes.free() } }
	writer.value(object, 0)!
	data := objc_allocate(ios_runtime.names['NSData'])
	obj_header(data).data = writer.bytes.clone()
	return data
}

fn json_valid(object u64) bool {
	if !objc_is_kind(object, ios_runtime.names['NSArray']) && !objc_is_kind(object, ios_runtime.names['NSDictionary']) {
		return false
	}
	mut writer := JsonWriter{ bytes: []u8{cap: 256} }
	writer.bytes.flags |= .noslices
	defer { unsafe { writer.bytes.free() } }
	writer.value(object, 0) or { return false }
	return true
}
