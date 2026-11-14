// SPDX-License-Identifier: GPL-2.0-or-later
module m1parity

import strconv

// Deliberately small readers for the declarations this audit compares. An
// unfamiliar expression is an error, never an assumed match or a default zero.
fn uncomment(source string, rust bool) !string {
	mut result := []u8{cap: source.len}
	mut i := 0
	for i < source.len {
		if i + 1 < source.len && source[i] == `/` && source[i + 1] == `/` {
			for i < source.len && source[i] != `\n` { i++ }
		} else if i + 1 < source.len && source[i] == `/` && source[i + 1] == `*` {
			i += 2
			mut closed := false
			for i < source.len {
				if i + 1 < source.len && source[i] == `*` && source[i + 1] == `/` {
					i += 2
					closed = true
					break
				}
				if source[i] == `\n` { result << `\n` }
				i++
			}
			if !closed { return error('unterminated source comment') }
			result << ` `
		} else if source[i] == `"` || source[i] == `'` {
			if rust && source[i] == `"` && i > 0 && (source[i - 1] == `r` || source[i - 1] == `#`) {
				return error('raw strings require explicit reader support')
			}
			// Rust lifetime tokens are identifiers, not quoted strings.
			if rust && source[i] == `'` {
				mut end := i + 1
				for end < source.len && (source[end].is_letter() || source[end].is_digit() || source[end] == `_`) {
					end++
				}
				if end > i + 1 && (end == source.len || source[end] != `'`) {
					result << source[i]
					i++
					continue
				}
			}
			quote := source[i]
			result << ` `
			i++
			mut closed := false
			for i < source.len {
				ch := source[i]
				result << if ch == `\n` { `\n` } else { ` ` }
				i++
				if ch == `\\` && i < source.len {
					result << if source[i] == `\n` { `\n` } else { ` ` }
					i++
					continue
				}
				if ch == quote {
					closed = true
					break
				}
			}
			if !closed { return error('unterminated source string') }
		} else {
			result << source[i]
			i++
		}
	}
	return result.bytestr()
}

fn identifier(value string) bool {
	return value.len > 0 && (value[0].is_letter() || value[0] == `_`)
		&& value.bytes().all(it.is_letter() || it.is_digit() || it == `_`)
}

fn expression(text string, constants map[string]u64, depth int) !u64 {
	if depth > 16 { return error('constant expression too deeply nested') }
	value := text.trim_space()
	if value == '' { return error('empty constant expression') }
	mut nesting := 0
	mut addition := -1
	mut shift := -1
	for i, ch in value {
		if ch == `(` { nesting++ }
		if ch == `)` {
			nesting--
			if nesting < 0 { return error('unbalanced expression') }
		}
		if nesting == 0 && ch == `+` { addition = i }
		if nesting == 0 && ch == `<` && i + 1 < value.len && value[i + 1] == `<` { shift = i }
	}
	if nesting != 0 { return error('unbalanced expression') }
	if shift >= 0 {
		left := expression(value[..shift], constants, depth + 1)!
		right := expression(value[shift + 2..], constants, depth + 1)!
		if right >= 64 || left > (~u64(0) >> right) { return error('constant shift overflow') }
		return left << right
	}
	if addition >= 0 {
		left := expression(value[..addition], constants, depth + 1)!
		right := expression(value[addition + 1..], constants, depth + 1)!
		if left > ~u64(0) - right { return error('constant addition overflow') }
		return left + right
	}
	for prefix in ['(', 'u16(', 'u32(', 'u64('] {
		if value.starts_with(prefix) && value.ends_with(')') {
			result := expression(value[prefix.len..value.len - 1], constants, depth + 1)!
			if (prefix == 'u16(' && result > 0xffff) || (prefix == 'u32(' && result > 0xffffffff) {
				return error('narrowing cast not supported')
			}
			return result
		}
	}
	if identifier(value) {
		return constants[value] or { return error('unknown constant: ${value}') }
	}
	digits := value.trim_right('uUlL').replace('_', '')
	if digits == '' { return error('unsupported constant: ${value}') }
	return strconv.parse_uint(digits, 0, 64) or { return error('unsupported constant: ${value}') }
}

fn declaration(source string, name string, rust bool) !string {
	mut found := ''
	mut seen := false
	for raw in uncomment(source, rust)!.split_into_lines() {
		line := raw.trim_space()
		if !line.starts_with('const ') && !line.starts_with('pub const ') && !line.starts_with('pub(crate) const ') {
			continue
		}
		if !line.contains('=') { continue }
		left, right := line.split_once('=') or { continue }
		words := left.all_before(':').fields()
		if words.len == 0 || words.last() != name { continue }
		if seen { return error('duplicate constant: ${name}') }
		seen = true
		found = right.trim_space().trim_right(';')
		if found == '' { return error('empty constant: ${name}') }
	}
	if found == '' { return error('missing constant: ${name}') }
	return found
}

fn enum_values(source string, name string) !map[string]u64 {
	body := aggregate(uncomment(source, false)!, 'enum ${name}')!
	mut values := map[string]u64{}
	mut next := u64(0)
	for raw in body.split(',') {
		item := raw.trim_space()
		if item == '' { continue }
		parts := item.split('=')
		if parts.len > 2 { return error('unsupported enum entry: ${item}') }
		key := parts[0].trim_space()
		if !identifier(key) || key in values { return error('invalid enum entry: ${item}') }
		value := if parts.len == 2 { expression(parts[1], values, 0)! } else { next }
		if value == ~u64(0) { return error('enum overflow') }
		values[key] = value
		next = value + 1
	}
	if values.len == 0 { return error('empty enum: ${name}') }
	return values
}

fn define_value(source string, name string) !u64 {
	mut found := ''
	for raw in uncomment(source, false)!.split_into_lines() {
		fields := raw.fields()
		if fields.len < 2 || fields[0] != '#define' || fields[1] != name { continue }
		if fields.len == 2 { return error('empty define: ${name}') }
		if found != '' { return error('duplicate define: ${name}') }
		found = fields[2..].join(' ')
	}
	if found == '' { return error('missing define: ${name}') }
	return expression(found, map[string]u64{}, 0)
}
