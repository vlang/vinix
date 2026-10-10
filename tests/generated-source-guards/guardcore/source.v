// SPDX-License-Identifier: GPL-2.0-or-later
module guardcore

import encoding.utf8
import hosttest

pub struct Generated {
	source  string
	lines   []string
	offsets []int
}

pub fn parse(source string) !Generated {
	if !utf8.validate_str(source) { return error('generated C is not valid UTF-8') }
	text := source.replace('\r\n', '\n').replace('\r', '\n')
	lines := text.split('\n')
	mut offsets := []int{cap: lines.len}
	mut offset := 0
	for line in lines {
		offsets << offset
		offset += line.len + 1
	}
	return Generated{text, lines, offsets}
}

fn ascii_word(character u8) bool {
	return character.is_alnum() || character == `_`
}

fn type_prefix(prefix string) bool {
	return prefix.len > 0 && (prefix[0].is_letter() || prefix[0] == `_`)
		&& prefix.bytes().all(ascii_word(it) || it in [` `, `*`])
}

// Preserve the original generated-C selectors: single-line signatures and
// the first unindented closing brace. Prototypes and indented definitions do
// not satisfy the resource/procfs type-prefix checks.
pub fn (generated Generated) body(name string, family string) !string {
	needle := name + '('
	for number, line in generated.lines {
		if !line.ends_with(') {') || number + 1 >= generated.lines.len { continue }
		mut search := 0
		for search < line.len {
			at := line.index_after(needle, search) or { break }
			prefix := line[..at]
			search = at + needle.len
			if prefix != '' && hosttest.module_word_rune(prefix.runes().last()) { continue }
			if family != 'pagecache' && !type_prefix(prefix) { continue }
			if family == 'procfs' && !prefix.ends_with(' ') { continue }
			if family == 'procfs' && line[at + needle.len..line.len - 3].contains(';') { continue }
			start := generated.offsets[number] + line.len + 1
			end := generated.source.index_after('\n}\n', start) or { return error('substring not found') }
			return generated.source[start..end]
		}
	}
	return error(if family == 'procfs' {
		'missing ${name} definition'
	} else {
		'missing function ${name}'
	})
}

fn regex_space(character rune) bool {
	return character in [rune(9), 10, 11, 12, 13, 28, 29, 30, 31, 32, 0x85, 0xa0, 0x1680, 0x2000,
		0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x2028,
		0x2029, 0x202f, 0x205f, 0x3000]
}

fn hidden_allocation(body string) bool {
	runes := body.runes()
	for name in ['memdup', 'new_array_from_c_array', 'builtin__memdup', 'v_malloc'] {
		letters := name.runes()
		for index in 0 .. runes.len {
			if index > 0 && hosttest.module_word_rune(runes[index - 1]) { continue }
			if index + letters.len > runes.len { break }
			mut same := true
			for offset, letter in letters {
				if runes[index + offset] != letter {
					same = false
					break
				}
			}
			if !same { continue }
			mut cursor := index + letters.len
			for cursor < runes.len && regex_space(runes[cursor]) { cursor++ }
			if cursor < runes.len && runes[cursor] == `(` { return true }
		}
	}
	return false
}

fn required_index(value string, needle string) !int {
	return value.index(needle) or { return error('substring not found') }
}
