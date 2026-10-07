// SPDX-License-Identifier: GPL-2.0-or-later
module g13layout

import os
import strconv

pub const emitted = ['InitData', 'HwDataA', 'HwDataB', 'Globals', 'IOMapping', 'PowerZone']
pub const labels = ['v12_3', 'v13_5']
pub const known_v12_3 = {
	'IOMapping': i64(0x20)
	'HwDataB':   i64(0xb6c)
	'HwDataA':   i64(0x3d6c)
	'Globals':   i64(0x11d40)
}

pub struct Target {
pub:
	gpu     string = 'G13'
	version string
}

pub struct Field {
pub:
	name      string
	type_text string
	condition string
}

pub struct Definition {
pub:
	name   string
	fields []Field
}

pub struct ConstArm {
	condition string
	value     i64
}

pub struct Definitions {
pub:
	structs map[string]Definition
	consts  map[string][]ConstArm
}

pub struct Member {
pub:
	name      string
	offset    i64
	size      i64
	type_text string
}

pub struct Layout {
pub:
	size   i64
	align  i64
	fields []Member
}

pub struct Pair {
	old i64
	new i64
}

struct AddedField {
	name   string
	offset i64
	kind   string
}

pub fn default_m1n1() string {
	return os.getenv_opt('VINIX_M1N1') or { os.join_path(os.home_dir(), 'code/3rd/m1n1') }
}

pub fn default_raw_rs() string {
	return os.join_path(default_m1n1(), 'rust/src/gpu/raw.rs')
}

pub fn repo_root() string {
	return os.real_path(os.join_path(@FILE, '..', '..', '..', '..'))
}

pub fn default_output() string {
	return os.join_path(repo_root(), 'kernel/gpu/agx/fw/g13_initdata_layout.v')
}

fn target(label string) Target {
	return Target{ version: if label == 'v12_3' { 'V12_3' } else { 'V13_5' } }
}

fn hx(value i64) string {
	return '0x' + strconv.format_int(value, 16)
}

fn number(text string) !i64 {
	return strconv.parse_int(text, 0, 64)!
}

fn is_word(ch u8) bool {
	return ch.is_letter() || ch.is_digit() || ch == `_`
}

fn identifier(text string) bool {
	return text.len > 0 && text.bytes().all(is_word(it))
}

fn numeric(text string) bool {
	if text.starts_with('0x') {
		return text.len > 2 && text[2..].bytes().all(it.is_hex_digit())
	}
	return text.len > 0 && text.bytes().all(it.is_digit())
}

pub fn extract_gate(line string) !string {
	start := line.index('#[ver(') or { return '' }
	mut index := start + 6
	mut depth := 1
	for index < line.len && depth > 0 {
		if line[index] == `(` { depth++ }
		if line[index] == `)` {
			depth--
			if depth == 0 { break }
		}
		index++
	}
	if depth != 0 { return error('unterminated version gate in ${line.trim_space()}') }
	return line[start + 6..index].trim_space()
}

struct GateParser {
	tokens    []string
	condition string
	target    Target
mut:
	position int
}

fn gate_tokens(condition string) []string {
	// Match the original comparison/parenthesis token grammar. Unmatched text
	// is ignored, just as the original re.findall tokenizer ignored it.
	mut tokens := []string{}
	mut index := 0
	for index < condition.len {
		if condition[index] in [`(`, `)`] {
			tokens << condition[index..index + 1]
			index++
			continue
		}
		if index + 1 < condition.len && condition[index..index + 2] in ['&&', '||'] {
			tokens << condition[index..index + 2]
			index += 2
			continue
		}
		if !is_word(condition[index]) {
			index++
			continue
		}
		start := index
		for index < condition.len && is_word(condition[index]) { index++ }
		for index < condition.len && condition[index].is_space() { index++ }
		mut op_len := 0
		if index + 1 < condition.len && condition[index..index + 2] in ['>=', '<=', '==', '!='] {
			op_len = 2
		} else if index < condition.len && condition[index] in [`<`, `>`] {
			op_len = 1
		}
		if op_len == 0 { continue }
		index += op_len
		for index < condition.len && condition[index].is_space() { index++ }
		value_start := index
		for index < condition.len && is_word(condition[index]) { index++ }
		if index > value_start { tokens << condition[start..index] }
	}
	return tokens
}

fn (mut parser GateParser) comparison(text string) !bool {
	mut op := ''
	mut parts := []string{}
	for candidate in ['>=', '<=', '==', '!=', '<', '>'] {
		if text.contains(candidate) {
			op = candidate
			parts = text.split(candidate)
			break
		}
	}
	if parts.len != 2 { return error('unsupported comparison ${text}') }
	axis := parts[0].trim_space()
	value := parts[1].trim_space()
	axis_values := if axis == 'G' {
		['G13', 'G14', 'G14X']
	} else if axis == 'V' {
		['V12_3', 'V12_4', 'V13_0B4', 'V13_2', 'V13_3', 'V13_5']
	} else {
		return error('unknown axis or value in ${text}')
	}
	if value !in axis_values { return error('unknown axis or value in ${text}') }
	left := axis_values.index(if axis == 'G' { parser.target.gpu } else { parser.target.version })
	if left < 0 { return error('unknown target for ${axis}') }
	right := axis_values.index(value)
	return match op {
		'>=' { left >= right }
		'<=' { left <= right }
		'==' { left == right }
		'!=' { left != right }
		'<' { left < right }
		else { left > right }
	}
}

fn (mut parser GateParser) primary() !bool {
	if parser.position >= parser.tokens.len { return error('unbalanced gate ${parser.condition}') }
	token := parser.tokens[parser.position]
	parser.position++
	if token == '(' {
		value := parser.disjunction()!
		if parser.position >= parser.tokens.len || parser.tokens[parser.position] != ')' {
			return error('unbalanced gate ${parser.condition}')
		}
		parser.position++
		return value
	}
	return parser.comparison(token)
}

fn (mut parser GateParser) conjunction() !bool {
	mut value := parser.primary()!
	for parser.position < parser.tokens.len && parser.tokens[parser.position] == '&&' {
		parser.position++
		right := parser.primary()!
		value = right && value
	}
	return value
}

fn (mut parser GateParser) disjunction() !bool {
	mut value := parser.conjunction()!
	for parser.position < parser.tokens.len && parser.tokens[parser.position] == '||' {
		parser.position++
		right := parser.conjunction()!
		value = right || value
	}
	return value
}

pub fn evaluate(condition string, concrete Target) !bool {
	if condition == '' { return true }
	tokens := gate_tokens(condition)
	if tokens.len == 0 { return error('unsupported version gate ${condition}') }
	mut parser := GateParser{ tokens: tokens, condition: condition, target: concrete }
	value := parser.disjunction()!
	if parser.position != tokens.len { return error('trailing tokens in gate ${condition}') }
	return value
}

fn visibility(line string) string {
	return line.trim_space().trim_string_left('pub(crate) ').trim_string_left('pub ')
}

pub fn parse(source string) !Definitions {
	mut structs := map[string]Definition{}
	mut consts := map[string][]ConstArm{}
	lines := source.split_into_lines()
	mut index := 0
	for index < lines.len {
		line := visibility(lines[index])
		is_struct := line.starts_with('struct ') && line.contains('{')
		is_const := line.starts_with('const ') && line.contains(':') && line.all_after(':').trim_space().starts_with('usize') && line.contains('=') && line.all_after('=').trim_space().starts_with('{')
		if !is_struct && !is_const {
			index++
			continue
		}
		name := if is_struct {
			line.all_after('struct ').all_before('{').trim_space()
		} else {
			line.all_after('const ').all_before(':').trim_space()
		}
		if !identifier(name) {
			index++
			continue
		}
		mut fields := []Field{}
		mut arms := []ConstArm{}
		mut pending := ''
		index++
		for index < lines.len {
			current := lines[index].trim_space()
			if (is_struct && current == '}') || (is_const && current.replace(' ', '').replace('\t', '') == '};') {
				break
			}
			gate := extract_gate(lines[index])!
			if lines[index].contains('#[ver(') {
				pending = gate
				index++
				continue
			}
			if is_struct {
				member := visibility(lines[index])
				if member.contains(':') && member.ends_with(',') {
					field_name := member.all_before(':').trim_space()
					if identifier(field_name) {
						fields << Field{ name: field_name, type_text: member.all_after(':').trim_string_right(',').trim_space(), condition: pending }
						pending = ''
					}
				}
			} else if numeric(current) {
				arms << ConstArm{ condition: pending, value: number(current)! }
				pending = ''
			}
			index++
		}
		index++
		if is_struct {
			structs[name] = Definition{ name: name, fields: fields }
		} else {
			consts[name] = arms
		}
	}
	return Definitions{ structs: structs, consts: consts }
}

pub fn (defs Definitions) resolve_const(name string, concrete Target) !i64 {
	base := name.replace('::ver', '')
	if base !in defs.consts { return error('unknown constant ${name}') }
	for arm in defs.consts[base] {
		if evaluate(arm.condition, concrete)! { return arm.value }
	}
	return error('no arm of ${base} matches ${concrete.gpu}/${concrete.version}')
}

pub fn array_parts(text string) !(string, string) {
	inner := text[6..text.len - 1]
	mut depth := 0
	for index, ch in inner.bytes() {
		if ch == `<` { depth++ }
		if ch == `>` { depth-- }
		if ch == `,` && depth == 0 {
			return inner[..index].trim_space(), inner[index + 1..].trim_space()
		}
	}
	return error('malformed array ${text}')
}

pub fn (defs Definitions) size_align(original string, concrete Target) !(i64, i64) {
	text := original.trim_space().replace('::ver', '')
	match text {
		'u8', 'i8' { return 1, 1 }
		'u16', 'i16' { return 2, 2 }
		'u32', 'i32', 'F32' { return 4, 4 }
		'u64', 'i64' { return 8, 8 }
		'U64' { return 8, 1 }
		'U32' { return 4, 1 }
		else {}
	}
	if text.starts_with('Pad<') { return number(text[4..text.len - 1])!, 1 }
	if text.starts_with('Array<') || (text.starts_with('[') && text.ends_with(']') && text.contains(';')) {
		count_text, element := if text.starts_with('Array<') {
			array_parts(text)!
		} else {
			text[1..text.len - 1].all_after_last(';').trim_space(), text[1..text.len - 1].all_before_last(';').trim_space()
		}
		count := if numeric(count_text) {
			number(count_text)!
		} else {
			defs.resolve_const(count_text, concrete)!
		}
		size, alignment := defs.size_align(element, concrete)!
		return count * size, alignment
	}
	if text in defs.structs {
		layout := defs.lay_out(text, concrete)!
		return layout.size, layout.align
	}
	return error('unknown type ${text}')
}

pub fn (defs Definitions) lay_out(name string, concrete Target) !Layout {
	if name !in defs.structs { return error('unknown structure ${name}') }
	mut offset := i64(0)
	mut alignment := i64(1)
	mut fields := []Member{}
	for field in defs.structs[name].fields {
		if !evaluate(field.condition, concrete)! { continue }
		size, align := defs.size_align(field.type_text, concrete)!
		offset = (offset + align - 1) & ~(align - 1)
		fields << Member{ name: field.name, offset: offset, size: size, type_text: field.type_text.trim_space().replace('::ver', '') }
		offset += size
		alignment = i64_max(alignment, align)
	}
	return Layout{ size: (offset + alignment - 1) & ~(alignment - 1), align: alignment, fields: fields }
}

fn i64_max(a i64, b i64) i64 { return if a > b { a } else { b } }

pub fn verify_against_tree(layouts map[string]Layout, expected map[string]i64) []string {
	mut problems := []string{}
	for name in ['IOMapping', 'HwDataB', 'HwDataA', 'Globals'] {
		if name !in expected { continue }
		if name !in layouts || layouts[name].size != expected[name] {
			got := if name in layouts { hx(layouts[name].size) } else { 'absent' }
			problems << '${name}: tree says ${hx(expected[name])}, computed ${got}'
		}
	}
	return problems
}

pub fn verify_encoded_offsets(layouts map[string]Layout) []string {
	mut problems := []string{}
	for name in emitted {
		if name !in layouts { continue }
		for member in layouts[name].fields {
			if !member.name.starts_with('unk_') { continue }
			claimed := member.name[4..]
			if claimed.len < 3 || claimed.len > 5 || !claimed.bytes().all(it in `0` .. `9` || it in `a` .. `f`) {
				continue
			}
			value := int(strconv.parse_int(claimed, 16, 64) or { continue })
			if value != member.offset && !(name == 'Globals' && member.name == 'unk_117bc') {
				problems << '${name}.${member.name}: name says ${hx(value)}, computed ${hx(member.offset)}'
			}
		}
	}
	return problems
}

// Literal offsets belong to specific builder calls. Scanning their argument
// lists preserves the optional ABI argument without treating other literals
// or computed loop bases as direct writes.
pub fn written_offsets(source string, helpers []string, calls map[string]int) ![]i64 {
	mut found := map[i64]bool{}
	for helper in helpers {
		needle := helper + '(mut data, '
		mut remainder := source
		for remainder.contains(needle) {
			remainder = remainder.all_after(needle)
			argument := remainder.trim_string_left('abi, ')
			literal := leading_hex(argument)
			if literal != '' { found[number(literal)!] = true }
		}
	}
	for helper, count in calls {
		needle := helper + '(mut data'
		mut remainder := source
		for remainder.contains(needle) {
			remainder = remainder.all_after(needle)
			mut argument := remainder.trim_string_left(', abi')
			mut literals := []i64{}
			for _ in 0 .. count {
				if !argument.starts_with(',') { break }
				argument = argument[1..].trim_left(' \t\r\n')
				literal := leading_hex(argument)
				if literal == '' { break }
				literals << number(literal)!
				argument = argument[literal.len..]
			}
			if literals.len == count {
				for literal in literals { found[literal] = true }
			}
		}
	}
	mut result := found.keys()
	result.sort()
	return result
}

fn leading_hex(text string) string {
	if !text.starts_with('0x') { return '' }
	mut index := 2
	for index < text.len && text[index].is_hex_digit() { index++ }
	return if index > 2 { text[..index] } else { '' }
}

pub fn (defs Definitions) translate_offset(offset i64, old Layout, new Layout, path string) !i64 {
	mut member := Member{}
	mut found := false
	for candidate in old.fields {
		if candidate.offset == offset {
			member = candidate
			found = true
		}
	}
	if !found {
		for candidate in old.fields {
			if candidate.offset <= offset && offset < candidate.offset + candidate.size {
				member = candidate
				found = true
			}
		}
	}
	if !found { return error('${path}: ${hx(offset)} addresses no field at 12.3') }
	mut replacement := Member{}
	found = false
	for candidate in new.fields {
		if candidate.name == member.name {
			replacement = candidate
			found = true
		}
	}
	if !found { return error_with_code(member.name, 2) }
	delta := offset - member.offset
	if delta == 0 { return replacement.offset }
	if member.type_text in defs.structs {
		inner := defs.translate_offset(delta, defs.lay_out(member.type_text, target('v12_3'))!, defs.lay_out(member.type_text, target('v13_5'))!, '${path}.${member.name}')!
		return replacement.offset + inner
	}
	if replacement.size != member.size {
		return error('${path}: ${hx(offset)} is ${hx(delta)} into ${member.name}, which changes size ${hx(member.size)} -> ${hx(replacement.size)}')
	}
	return replacement.offset + delta
}

pub fn (defs Definitions) remap(offsets []i64, old Layout, new Layout, name string) ([]Pair, []i64, []string) {
	mut pairs := []Pair{}
	mut dropped := []i64{}
	mut problems := []string{}
	for offset in offsets {
		translated := defs.translate_offset(offset, old, new, name) or {
			if err.code() == 2 { dropped << offset } else { problems << err.msg() }
			continue
		}
		pairs << Pair{ old: offset, new: translated }
	}
	return pairs, dropped, problems
}

pub fn assignment_for(initdata string, name string) !string {
	lines := initdata.split_into_lines()
	for index, line in lines {
		trimmed := line.trim_space()
		prefix := 'raw.' + name
		if !trimmed.starts_with(prefix) { continue }
		tail := trimmed[prefix.len..].trim_left(' \t')
		if !tail.starts_with('=') || tail.starts_with('==') { continue }
		mut value := tail[1..].trim_left(' \t')
		mut cursor := index
		for !value.contains(';') && cursor + 1 < lines.len {
			cursor++
			value += ' ' + lines[cursor].trim_space()
		}
		value = value.all_before(';')
		mut gate := ''
		mut previous := index - 1
		for previous >= 0 && previous >= index - 2 {
			text := lines[previous].trim_space()
			if text == '' || text in ['{', '}'] {
				previous--
				continue
			}
			gate = extract_gate(lines[previous])!
			break
		}
		if gate != '' && !evaluate(gate, target('v13_5'))! { continue }
		return value.fields().join(' ')
	}
	return ''
}

fn mentioned(initdata string, name string) bool {
	needle := 'raw.' + name
	mut position := 0
	for position < initdata.len {
		relative := initdata[position..].index(needle) or { return false }
		start := position + relative
		end := start + needle.len
		if (start == 0 || !is_word(initdata[start - 1])) && (end == initdata.len || !is_word(initdata[end])) {
			return true
		}
		position = end
	}
	return false
}

fn exclusion(name string) string {
	return match name {
		'aux_leak_coef', 'aux_ps' { 'csafr, which t8103 does not have' }
		'unk_hws2' { 'G >= G14X' }
		else { '' }
	}
}

fn (defs Definitions) additions(name string) ![]Member {
	old := defs.lay_out(name, target('v12_3'))!
	new := defs.lay_out(name, target('v13_5'))!
	names := old.fields.map(it.name)
	return new.fields.filter(it.name !in names)
}

fn (defs Definitions) fields_needing_values(initdata string) !map[string][]AddedField {
	mut result := map[string][]AddedField{}
	for index, name in ['HwDataA', 'Globals', 'HwDataB'] {
		mut entries := []AddedField{}
		for member in defs.additions(name)! {
			if exclusion(member.name) != '' { continue }
			if member.type_text in defs.structs {
				inner := defs.lay_out(member.type_text, target('v13_5'))!
				for sub in inner.fields {
					entries << AddedField{ name: '${member.name}_${sub.name}', offset: member.offset + sub.offset, kind: sub.type_text }
				}
				continue
			}
			assignment := assignment_for(initdata, member.name)!
			if assignment == '' && !mentioned(initdata, member.name) { continue }
			entries << AddedField{ name: member.name, offset: member.offset, kind: member.type_text }
		}
		result[['hwdata_a', 'globals', 'hwdata_b'][index]] = entries
	}
	return result
}

pub fn classify_additions(raw_rs string) !string {
	defs := parse(os.read_file(raw_rs)!)!
	initdata := os.read_file(os.join_path(os.dir(raw_rs), 'initdata.rs'))!
	mut lines := []string{}
	for name in ['HwDataA', 'Globals', 'HwDataB'] {
		added := defs.additions(name)!
		mut needed := []string{}
		mut skipped := []string{}
		mut zeroed := 0
		for member in added {
			why := exclusion(member.name)
			if why != '' {
				skipped << '    skip   ${member.name:-32s} (${why})'
				continue
			}
			assignment := assignment_for(initdata, member.name)!
			if assignment != '' {
				position := hx(member.offset)
				needed << '    value  ${member.name:-32s} @ ${position:7s} = ${assignment}'
			} else if mentioned(initdata, member.name) {
				position := hx(member.offset)
				needed << '    value  ${member.name:-32s} @ ${position:7s} = <assigned indirectly>'
			} else {
				zeroed++
			}
		}
		lines << '${name}: ${added.len} added -- ${needed.len} need a value, ${zeroed} stay zero, ${skipped.len} not applicable'
		lines << needed
		lines << skipped
	}
	return lines.join('\n')
}

pub fn report(raw_rs string) !string {
	defs := parse(os.read_file(raw_rs)!)!
	mut lines := []string{}
	for name in emitted {
		if name !in defs.structs { continue }
		old := defs.lay_out(name, target('v12_3'))!
		new := defs.lay_out(name, target('v13_5'))!
		old_names := old.fields.map(it.name)
		new_names := new.fields.map(it.name)
		added := new.fields.filter(it.name !in old_names)
		removed := old.fields.filter(it.name !in new_names)
		mut moved := 0
		for member in new.fields {
			for prior in old.fields {
				if member.name == prior.name && member.offset != prior.offset { moved++ }
			}
		}
		lines << '${name}: ${hx(old.size)} -> ${hx(new.size)}  +${added.len} -${removed.len} moved ${moved}'
		for member in added {
			lines << '    + ${member.name} @ ${hx(member.offset)} (${member.size} bytes)'
		}
		for member in removed {
			lines << '    - ${member.name} @ ${hx(member.offset)} (${member.size} bytes)'
		}
	}
	return lines.join('\n')
}

fn snake_case(text string) string {
	mut result := ''
	for index, ch in text.bytes() {
		if index > 0 && ch.is_capital() && (text[index - 1] in `a` .. `z` || text[index - 1].is_digit() || (text[index - 1].is_capital() && index + 1 < text.len && text[index + 1] in `a` .. `z`)) {
			result += '_'
		}
		result += ch.ascii_str().to_lower()
	}
	return result
}

fn rendered_array(values []i64) string {
	return '[' + values.map('u32(' + hx(it) + ')').join(', ') + ']!'
}

pub fn generate(raw_rs string) !string {
	return generate_checked(raw_rs, known_v12_3)
}

pub fn generate_checked(raw_rs string, expected map[string]i64) !string {
	defs := parse(os.read_file(raw_rs)!)!
	mut per_target := map[string]map[string]Layout{}
	mut mapping_counts := map[string]i64{}
	for label in labels {
		mut layouts := map[string]Layout{}
		for name in emitted {
			if name in defs.structs { layouts[name] = defs.lay_out(name, target(label))! }
		}
		if 'RuntimePointers' in defs.structs {
			layouts['RuntimePointers'] = defs.lay_out('RuntimePointers', target(label))!
		}
		per_target[label] = layouts
		mapping_counts[label] = defs.resolve_const('IO_MAPPING_COUNT', target(label))!
	}
	mut problems := verify_against_tree(per_target['v12_3'], expected)
	problems << verify_encoded_offsets(per_target['v12_3'])
	if problems.len > 0 {
		return error('layout engine disagrees with the established 12.3 layout:\n  ' + problems.join('\n  '))
	}
	mut remaps := map[string][]Pair{}
	mut drops := map[string][]i64{}
	mut remap_problems := []string{}
	for index, label in ['hwdata_a', 'globals'] {
		name := ['HwDataA', 'Globals'][index]
		file := os.join_path(repo_root(), 'kernel/gpu/agx/fw', [
			'initdata_g13_hwdata_a.v',
			'initdata_g13_globals.v',
		][index])
		if !os.is_file(file) {
			remap_problems << 'missing ${file}'
			continue
		}
		helpers := if index == 0 {
			['g13_hwdata_a_put_u32', 'g13_hwdata_a_put_u64']
		} else {
			['g13_globals_put_u32', 'g13_globals_put_u16']
		}
		calls := if index == 0 {
			{
				'g13_set_filter': 2
			}
		} else {
			map[string]int{}
		}
		mut offsets := written_offsets(os.read_file(file)!, helpers, calls)!
		bases := if index == 0 {
			[i64(0x74), 0xc58, 0x3648, 0x36f0, 0x3718, 0x3cf4, 0x3d14]
		} else {
			[i64(0x893c), 0x89f8, 0x8aa0]
		}
		for base in bases { if base !in offsets { offsets << base } }
		offsets.sort()
		pairs, dropped, errors := defs.remap(offsets, per_target['v12_3'][name], per_target['v13_5'][name], name)
		remaps[label] = pairs
		drops[label] = dropped
		remap_problems << errors
	}
	if remap_problems.len > 0 {
		return error('cannot re-point every 12.3 offset at 13.5:\n  ' + remap_problems.join('\n  '))
	}
	mut lines := [
		'// SPDX-License-Identifier: GPL-2.0-or-later',
		'// Copyright (c) 2026 Alexander Medvednikov',
		'// Code generated by tools/agx-re/generate_g13_initdata_layout.py; DO NOT EDIT.',
		'//',
		"// G13 InitData field offsets at each firmware ABI, computed from m1n1's",
		'// versioned firmware structures. The 12.3 column reproduces the sizes this',
		'// tree already had, which is what makes the 13.5 column trustworthy.',
		'',
		'module fw',
		'',
	]
	for label in labels {
		layouts := per_target[label]
		lines << '// ---- G13 ${target(label).version} ----'
		lines << 'pub const g13_${label}_io_mapping_count = u32(${mapping_counts[label]})'
		mut names := layouts.keys()
		names.sort()
		for name in names {
			lines << 'pub const g13_${label}_${snake_case(name)}_size = u64(${hx(layouts[name].size)})'
		}
		lines << ''
	}
	old := per_target['v12_3']['HwDataB']
	new := per_target['v13_5']['HwDataB']
	mut old_spans := []i64{}
	mut new_spans := []i64{}
	mut sizes := []i64{}
	for member in old.fields {
		for replacement in new.fields {
			if replacement.name == member.name && replacement.size == member.size {
				old_spans << member.offset
				new_spans << replacement.offset
				sizes << member.size
			}
		}
	}
	lines << '// Common HwDataB field spans copied from the established 12.3 builder'
	lines << '// into the 13.5 blob. Changed-size arrays are populated separately.'
	lines << 'pub const g13_hwdata_b_copy_offsets_v12_3 = ${rendered_array(old_spans)}'
	lines << 'pub const g13_hwdata_b_copy_offsets_v13_5 = ${rendered_array(new_spans)}'
	lines << 'pub const g13_hwdata_b_copy_sizes = ${rendered_array(sizes)}'
	for label in labels {
		mut found := false
		for member in per_target[label]['HwDataB'].fields {
			if member.name == 'io_mappings' {
				lines << 'pub const g13_${label}_hw_data_b_io_mappings_offset = u32(${hx(member.offset)})'
				found = true
				break
			}
		}
		if !found { return error('HwDataB has no io_mappings') }
	}
	lines << ''
	lines << ['// PowerZone member offsets at each ABI. 13.5 inserts two fields in the',
		"// middle of the entry, so the array's stride and the position of the two",
		'// members after the insertion both change: a per-entry base plus fixed',
		'// member offsets would write the filter coefficients into the wrong',
		'// words. The array base itself is in the remap table below.']
	for label in labels {
		zone := defs.lay_out('PowerZone', target(label))!
		for member in zone.fields {
			lines << 'pub const g13_${label}_power_zone_${member.name}_offset = u32(${hx(member.offset)})'
		}
		lines << ''
	}
	lines << ['// Fields 13.5 adds that need a value written, at their 13.5 offsets.',
		'// These do not exist at 12.3, so there is nothing to translate: the',
		'// builders write them only when the 13.5 layout is selected. Members of',
		'// a nested block are expanded, which is what unk_e10_0 -- the SE control',
		'// block 13.5 grows HwDataA by -- mostly consists of.']
	needed := defs.fields_needing_values(os.read_file(os.join_path(os.dir(raw_rs), 'initdata.rs'))!)!
	for label in ['hwdata_a', 'globals', 'hwdata_b'] {
		for member in needed[label] {
			lines << 'pub const g13_v13_5_${label}_${member.name}_offset = u32(${hx(member.offset)}) // ${member.kind}'
		}
		lines << ''
	}
	lines << ['// Where each offset the 12.3 builders write moves to at 13.5. The two',
		'// arrays are index-matched, sorted by the 12.3 offset, and cover exactly',
		'// the offsets those builders address -- generation fails if one of them',
		'// names a field 13.5 removed or reshaped.']
	for label in ['hwdata_a', 'globals'] {
		lines << 'pub const g13_${label}_offsets_v12_3 = ${rendered_array(remaps[label].map(it.old))}'
		lines << 'pub const g13_${label}_offsets_v13_5 = ${rendered_array(remaps[label].map(it.new))}'
		lines << ''
	}
	lines << ['// 12.3 offsets whose field 13.5 does not have. The write is skipped',
		'// there rather than failing: the value has nowhere to go, and putting',
		'// it at the 12.3 offset would land on whatever 13.5 placed there.']
	for label in ['hwdata_a', 'globals'] {
		values := drops[label]
		rendered := if values.len > 0 {
			rendered_array(values).trim_string_right('!')
		} else {
			'[]u32{}'
		}
		lines << 'pub const g13_${label}_offsets_dropped_v13_5 = ${rendered}'
	}
	lines << ''
	return lines.join('\n') + '\n'
}
