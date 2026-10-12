// SPDX-License-Identifier: GPL-2.0-or-later
// A data-only reader: quoted strings, integer constants and bounded arithmetic.
module kpihost

import cachecli
import json2
import os
import strconv

struct Literal {
	token        string
	string_value bool
}

fn literals(text string) ![]Literal {
	mut result := []Literal{}
	mut at := 0
	for at < text.len {
		byte := text[at]
		if byte.is_space() {
			at++
			continue
		}
		if byte == `/` && at + 1 < text.len && text[at + 1] == `/` {
			for at < text.len && text[at] != `\n` { at++ }
			continue
		}
		if byte == `/` && at + 1 < text.len && text[at + 1] == `*` {
			at += 2
			for at + 1 < text.len && text[at..at + 2] != '*/' { at++ }
			if at + 1 >= text.len { return error('incomplete data comment') }
			at += 2
			continue
		}
		if byte == `c` && at + 1 < text.len && text[at + 1] == `'` {
			at++
			continue
		}
		if byte in [u8(`'`), `"`] {
			quote := byte
			at++
			mut data := []u8{}
			for at < text.len && text[at] != quote {
				value := text[at]
				at++
				if value != `\\` {
					data << value
					continue
				}
				if at >= text.len { return error('incomplete literal escape') }
				escaped := text[at]
				at++
				if escaped == `x` {
					if at + 2 > text.len { return error('incomplete hexadecimal escape') }
					data << u8(strconv.parse_uint(text[at..at + 2], 16, 8)!)
					at += 2
				} else if escaped >= `0` && escaped <= `7` {
					begin := at - 1
					for at < text.len && at - begin < 3 && text[at] >= `0` && text[at] <= `7` {
						at++
					}
					data << u8(strconv.parse_uint(text[begin..at], 8, 8)!)
				} else {
					data << match escaped {
						`n` { u8(10) }
						`r` { u8(13) }
						`t` { u8(9) }
						`a` { u8(7) }
						`b` { u8(8) }
						`f` { u8(12) }
						`v` { u8(11) }
						`\\`, `'`, `"` { escaped }
						else { return error('unsupported data escape') }
					}
				}
			}
			if at >= text.len { return error('incomplete quoted literal') }
			at++
			result << Literal{ token: data.bytestr(), string_value: true }
			continue
		}
		if byte.is_alnum() || byte == `_` {
			begin := at
			for at < text.len && (text[at].is_alnum() || text[at] == `_` || text[at] == `.`) {
				at++
			}
			result << Literal{ token: text[begin..at] }
		} else {
			result << Literal{ token: byte.ascii_str() }
			at++
		}
	}
	return result
}

struct Number {
	negative  bool
	magnitude u64
}

fn (number Number) canonical() string {
	return if number.negative && number.magnitude != 0 {
		'-' + number.magnitude.str()
	} else {
		number.magnitude.str()
	}
}

fn (number Number) bits() u64 {
	return if number.negative { ~number.magnitude + u64(1) } else { number.magnitude }
}

struct NumberReader {
	values []Literal
mut:
	at int
}

fn (mut reader NumberReader) unary() !Number {
	if reader.at >= reader.values.len { return error('incomplete integer data') }
	value := reader.values[reader.at]
	reader.at++
	if value.token in ['+', '-', '~'] && !value.string_value {
		inner := reader.unary()!
		return match value.token {
			'+' { inner }
			'-' { Number{ negative: !inner.negative, magnitude: inner.magnitude } }
			else { Number{ magnitude: ~inner.bits() } }
		}
	}
	if value.token == '(' {
		if reader.at + 1 < reader.values.len && reader.values[reader.at].token in [
			'char',
			'int',
			'unsigned',
			'long',
		] && reader.values[reader.at + 1].token == ')' {
			reader.at += 2
			return reader.unary()!
		}
		inner := reader.expression()!
		if reader.at >= reader.values.len || reader.values[reader.at].token != ')' {
			return error('unclosed integer data')
		}
		reader.at++
		return inner
	}
	if value.token in ['u64', 'i64', 'u32', 'i32', 'usize', 'isize', 'char'] && !value.string_value {
		if reader.at >= reader.values.len || reader.values[reader.at].token != '(' {
			return error('invalid data cast')
		}
		reader.at++
		inner := reader.expression()!
		if reader.at >= reader.values.len || reader.values[reader.at].token != ')' {
			return error('unclosed data cast')
		}
		reader.at++
		return inner
	}
	if value.string_value {
		if value.token.len != 1 { return error('integer character data must be one byte') }
		return Number{ magnitude: u64(value.token[0]) }
	}
	return match value.token {
		'ULLONG_MAX' { Number{ magnitude: ~u64(0) } }
		'LLONG_MAX' { Number{ magnitude: u64(0x7fffffffffffffff) } }
		'LLONG_MIN' { Number{ negative: true, magnitude: u64(0x8000000000000000) } }
		'ERANGE' { Number{ magnitude: 34 } }
		'EINVAL' { Number{ magnitude: 22 } }
		'VINIX_PCI_CONFIG_BAD_REGISTER', 'bad', 'true' { Number{ magnitude: 1 } }
		'VINIX_PCI_CONFIG_UNAVAILABLE', 'unavailable' { Number{ magnitude: 2 } }
		'false' { Number{} }
		else {
			raw := value.token.trim_right('UL')
			Number{
				magnitude: strconv.parse_uint(if raw.starts_with('0x') { raw[2..] } else { raw }, if raw.starts_with('0x') {
					16
				} else {
					10
				}, 64)!
			}
		}
	}
}

fn sum(left Number, right Number) !Number {
	if left.negative == right.negative {
		if right.magnitude > ~u64(0) - left.magnitude {
			return error('integer data exceeds 64-bit magnitude')
		}
		return Number{ negative: left.negative, magnitude: left.magnitude + right.magnitude }
	}
	return if left.magnitude >= right.magnitude {
		Number{ negative: left.negative, magnitude: left.magnitude - right.magnitude }
	} else {
		Number{ negative: right.negative, magnitude: right.magnitude - left.magnitude }
	}
}

fn (mut reader NumberReader) expression() !Number {
	mut value := reader.unary()!
	for reader.at < reader.values.len && reader.values[reader.at].token in ['+', '-'] {
		subtract := reader.values[reader.at].token == '-'
		reader.at++
		term := reader.unary()!
		value = sum(value, Number{ negative: if subtract { !term.negative } else { term.negative }, magnitude: term.magnitude })!
	}
	return value
}

fn numeric(data []Literal) !Number {
	mut reader := NumberReader{ values: data }
	value := reader.expression()!
	if reader.at != data.len { return error('unsupported trailing integer data') }
	return value
}

fn tables(data []Literal, name string, v bool) ![][]Literal {
	mut result := [][]Literal{}
	for index, item in data {
		if item.string_value || item.token != name { continue }
		mut begin := index + 1
		if v {
			if begin + 1 >= data.len { continue }
			if data[begin].token == ':' && data[begin + 1].token == '=' {
				begin += 2
			} else if data[begin].token == '=' {
				begin++
			} else {
				continue
			}
			if begin >= data.len || data[begin].token != '[' { continue }
		} else {
			if begin + 3 >= data.len || data[begin].token != '[' || data[begin + 1].token != ']' || data[begin + 2].token != '=' || data[begin + 3].token != '{' {
				continue
			}
			begin += 3
		}
		opening := data[begin].token
		closing := if opening == '[' { ']' } else { '}' }
		mut depth := 1
		mut end := begin + 1
		for end < data.len && depth > 0 {
			if !data[end].string_value {
				if data[end].token == opening { depth++ }
				if data[end].token == closing { depth-- }
			}
			if depth > 0 { end++ }
		}
		if depth != 0 { return error('incomplete fixture table: ' + name) }
		result << data[begin + 1..end]
	}
	return result
}

fn fields(data []Literal) [][]Literal {
	mut result := [][]Literal{}
	mut begin := 0
	mut depth := 0
	for index, item in data {
		if !item.string_value {
			if item.token in ['(', '{', '['] { depth++ }
			if item.token in [')', '}', ']'] { depth-- }
			if item.token == ',' && depth == 0 {
				if index > begin { result << data[begin..index] }
				begin = index + 1
			}
		}
	}
	if begin < data.len { result << data[begin..] }
	return result
}

fn record_rows(data []Literal) ![][]string {
	mut result := [][]string{}
	mut at := 0
	for at < data.len {
		if data[at].string_value || data[at].token != '{' {
			at++
			continue
		}
		begin := at + 1
		at++
		mut depth := 1
		for at < data.len && depth > 0 {
			if !data[at].string_value {
				if data[at].token == '{' { depth++ }
				if data[at].token == '}' { depth-- }
			}
			if depth > 0 { at++ }
		}
		if depth != 0 { return error('incomplete fixture record') }
		mut row := []string{}
		for cell in fields(data[begin..at]) {
			if cell.len == 1 && cell[0].string_value {
				row << 'text:' + cell[0].token.bytes().hex()
			} else if cell.len == 1 && cell[0].token in ['nil', 'NULL'] {
				row << 'nil'
			} else {
				row << numeric(cell)!.canonical()
			}
		}
		result << row
		at++
	}
	return result
}

fn one_table(data []Literal, name string, v bool) ![]Literal {
	values := tables(data, name, v)!
	if values.len != 1 { return error('expected one fixture table: ' + name) }
	return values[0]
}

fn original(tools Tools, name string) ![]Literal {
	result := tools.command(['git', '-C', tools.root, 'show',
		'8f7239d1fd4c593746279699f6ff25df5f4dd7bd:kernel/c/' + name], os.environ())!
	if result.status != 0 { return error(result.stderr) }
	return literals(result.stdout)!
}

fn maintained(tools Tools, name string) ![]Literal {
	return literals(os.read_file(tools.root + '/kernel/linuxkpi/' + name + '/core.v')!)!
}

pub fn golden_parity(tools Tools) !map[string]json2.Any {
	mut checked := map[string]json2.Any{}
	c := original(tools, 'linuxkpi_runtime_native_test.c')!
	v := maintained(tools, 'runtimefixture')!
	for name, count in {
		'unsigned_cases': 19
		'signed_cases':   8
		'bool_cases':     12
		'pairs':          15
	} {
		left := record_rows(one_table(c, name, false)!)!
		right := record_rows(one_table(v, name, true)!)!
		if left.len != count || left != right {
			return error('independent runtime fixture data differs: ' + name + '\n' + left.str() + '\n' + right.str())
		}
		checked[name] = json2.Any(count)
	}
	mut buffers := 0
	for name in ['high', 'force', 'force_expected', 'trim', 'trim_expected', 'blank', 'blank_expected',
		'empty', 'no_delimiter', 'replaced', 'replaced_expected', 'old_nul', 'old_nul_expected',
		'empty_expected'] {
		left := tables(c, name, false)!
		right := tables(v, name, true)!
		if left.len != right.len { return error('guarded buffer count differs: ' + name) }
		for index, row in left {
			mut before := []u8{}
			mut after := []u8{}
			for cell in fields(row) { before << u8(numeric(cell)!.bits() & 255) }
			for cell in fields(right[index]) { after << u8(numeric(cell)!.bits() & 255) }
			if before != after { return error('guarded bytes differ: ' + name) }
		}
		buffers += left.len
	}
	checked['guarded_buffers'] = json2.Any(buffers)
	pc := original(tools, 'linuxkpi_pci_config_test.c')!
	pv := maintained(tools, 'pciconfigfixture')!
	for name, count in {
		'cases':   15
		'updates': 4
	} {
		left := record_rows(one_table(pc, name, false)!)!
		right := record_rows(one_table(pv, name, true)!)!
		if left.len != count || left != right {
			return error('independent PCI data differs: ' + name)
		}
		checked['pci_' + name] = json2.Any(count)
	}
	ic := original(tools, 'linuxkpi_i915_policy_test.c')!
	iv := maintained(tools, 'i915policyfixture')!
	c_goldens := tables(ic, 'goldens', false)!
	if c_goldens.len != 2 { return error('expected QP and device goldens') }
	for index, name in ['qp_goldens', 'device_goldens'] {
		left := record_rows(c_goldens[index])!
		right := record_rows(one_table(iv, name, true)!)!
		if left.len != if index == 0 { 48 } else { 8 } || left != right {
			return error('independent i915 data differs: ' + name)
		}
		checked[name] = json2.Any(left.len)
	}
	families := record_rows(one_table(iv, 'qp_families', true)!)!
	if families.len != 6 || families != record_rows(one_table(ic, 'families', false)!)! {
		return error('independent QP families differ')
	}
	mut storage := 0
	for family in families { storage += 15 * family[1].int() }
	if storage != 3240 { return error('QP storage coverage differs') }
	checked['qp_storage_valid_indices'] = json2.Any(storage)
	cc := original(tools, 'linuxkpi_cache_test.c')!
	cv := maintained(tools, 'cachefixture')!
	for name, count in {
		'rejected':     6
		'alignment':    4
		'rejected_gfp': 3
	} {
		left := fields(one_table(cc, name, false)!)
		right := fields(one_table(cv, name, true)!)
		if left.len != count || right.len != count {
			return error('cache data count differs: ' + name)
		}
		for index, row in left {
			if name == 'alignment' {
				if numeric(row)!.canonical() != numeric(right[index])!.canonical() {
					return error('cache alignment differs')
				}
			} else {
				before := row.map(it.token).join('')
				after := right[index].map(it.token).join('').replace('C.', '')
				if before != after { return error('cache policy data differs: ' + name) }
			}
		}
		checked['cache_' + name] = json2.Any(count)
	}
	return checked
}

pub fn golden_cli(tools Tools, argv []string) !int {
	cachecli.arguments(argv, [], [], [], 0, 0, 'Compare native fixture data to the immutable original C revision.\nUsage: fixture-goldens') or { return error_with_code(err.msg(), 2) }
	println('LinuxKPI independent fixture golden parity: ' + json2.encode(golden_parity(tools)!))
	return 0
}
