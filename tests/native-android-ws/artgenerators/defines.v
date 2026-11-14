// SPDX-License-Identifier: Apache-2.0
// V replacement for AOSP art/tools/cpp-define-generator/make_header.py.
// Original algorithm: Copyright (C) 2018 The Android Open Source Project.
module artgenerators

import strconv

struct Define {
	name string
	value string
	negative string
}

fn word(text string) bool {
	return text.len > 0 && text.bytes().all(it.is_alnum() || it == `_`)
}

fn immediate(text string) string {
	return if text.starts_with('$') || text.starts_with('#') { text[1..] } else { text }
}

fn decimal(text string) !u64 {
	if text.len == 0 || !text.bytes().all(it.is_digit()) {
		return error('invalid decimal assembly constant')
	}
	return strconv.parse_uint(text, 10, 64)
}

// Input is compiler assembly containing .ascii ">>NAME #VALUE #SIGNED<<".
// Sort the original decimal fields, then format. Do not sort by numeric value:
// upstream sorts (name, value spelling, signed flag) tuples lexicographically.
pub fn asm_header(input string) !string {
	mut found := []Define{}
	mut offset := 0
	for offset < input.len {
		begin := input[offset..].index('\">>') or { break }
		start := offset + begin + 3
		end := input[start..].index('<<\"') or {
			return error('unterminated assembly constant')
		}
		fields := input[start..start + end].split(' ')
		offset = start + end + 3
		if fields.len != 3 || !word(fields[0]) {
			return error('invalid assembly constant fields')
		}
		value := immediate(fields[1])
		negative := immediate(fields[2])
		if negative !in ['0', '1'] { return error('invalid assembly constant signed flag') }
		magnitude := decimal(value.trim_string_left('-'))!
		if value.starts_with('-') && magnitude > u64(1) << 63 {
			return error('assembly constant exceeds signed compiler range')
		}
		found << Define{fields[0], value, negative}
	}
	if found.len == 0 { return error('no assembly constants found') }
	found.sort_with_compare(fn (a &Define, b &Define) int {
		if a.name != b.name { return compare_strings(a.name, b.name) }
		if a.value != b.value { return compare_strings(a.value, b.value) }
		return compare_strings(a.negative, b.negative)
	})
	mut output := []string{}
	for item in found {
		magnitude := decimal(item.value.trim_string_left('-'))!
		mut value := '0x' + magnitude.hex()
		if item.value.starts_with('-') && magnitude != 0 {
			value = if item.negative == '0' {
				'0x' + (u64(0) - magnitude).hex()
			} else { '-0x' + magnitude.hex() }
		}
		output << '#define ${item.name} ${value}'
	}
	return output.join('\n') + '\n'
}
