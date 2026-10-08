// SPDX-License-Identifier: GPL-2.0-only
module agxhost

import hosttest

fn word_rune(ch rune) bool { return hosttest.module_word_rune(ch) }

pub fn forbidden_imports(text string, scale_fixture bool) bool {
	mut token := ''
	for ch in (text + ' ').runes() {
		if word_rune(ch) {
			token += ch.str()
			continue
		}
		name := if token.starts_with('_') { token[1..] } else { token }
		if name in ['malloc', 'realloc', 'memdup'] || name.starts_with('new_array') || (!scale_fixture && name in [
			'calloc',
			'free',
		]) {
			return true
		}
		token = ''
	}
	return false
}

pub fn allocation_call_count(text string, name string) int {
	needle := name + '('
	mut start := 0
	mut count := 0
	for start < text.len {
		index := start + (text[start..].index(needle) or { break })
		before := text[..index].runes()
		if before.len == 0 || !word_rune(before.last()) { count++ }
		start = index + needle.len
	}
	return count
}
