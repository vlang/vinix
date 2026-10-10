// SPDX-License-Identifier: GPL-2.0-or-later
module guardcore

import hosttest

fn word_prefix(prefix string) bool {
	return prefix.ends_with(' ') && prefix.len > 1
		&& prefix[..prefix.len - 1].runes().all(hosttest.module_word_rune(it))
}

// These guards originally inspect the signature as well as its body. Keep
// their separate prefix/argument selectors and first unindented closing brace.
pub fn (generated Generated) selected(name string, selector string) !string {
	needle := name + '('
	for number, line in generated.lines {
		at := line.index(needle) or { continue }
		prefix := line[..at]
		if selector == 'socket' {
			if prefix.len < 2 || !prefix.ends_with(' ') || prefix.contains(';') { continue }
		} else if !word_prefix(prefix) {
			continue
		}
		closing := line.last_index(') {') or { continue }
		if closing < at + needle.len { continue }
		if selector == 'churn'
			&& (closing + 3 != line.len || number + 1 >= generated.lines.len
				|| line[at + needle.len..closing].contains(';')) {
			continue
		}
		start := generated.offsets[number]
		body_start := start + line.len + 1
		end := generated.source.index_after('\n}\n', if selector == 'churn' {
			body_start
		} else {
			start
		}) or {
			return error('substring not found')
		}
		return if selector == 'churn' {
			generated.source[body_start..end]
		} else {
			generated.source[start..end + 3]
		}
	}
	return error(if selector == 'churn' {
		'missing ${name} definition'
	} else {
		'missing compiled function: ${name}'
	})
}

fn balanced_end(source string, opening int) !int {
	mut depth := 1
	mut cursor := opening + 1
	for cursor < source.len {
		if source[cursor] == `{` { depth++ }
		if source[cursor] == `}` { depth-- }
		cursor++
		if depth == 0 { return cursor }
	}
	return error('unterminated brace block')
}

// The timer selector accepts multiline arguments and counts raw braces,
// including braces in comments/strings, just as the original source check did.
pub fn (generated Generated) timer_body(name string) !string {
	needle := name + '('
	for number, line in generated.lines {
		mut candidates := []int{}
		mut search := 0
		for search < line.len {
			at := line.index_after(needle, search) or { break }
			search = at + needle.len
			if line[..at].contains(';') { break }
			if at > 0 && hosttest.module_word_rune(line[..at].runes().last()) { continue }
			candidates << at
		}
		// The original prefix is greedy: try the last matching name first.
		for at in candidates.reverse() {
			start := generated.offsets[number] + at + needle.len
			closing := generated.source.index_after(') {', start) or { continue }
			if generated.source[start..closing].contains(';') { continue }
			opening := closing + 2
			end := balanced_end(generated.source, opening)!
			return generated.source[opening..end]
		}
	}
	return error('missing definition: ${name}')
}

fn word_calls(source string, names []string, whitespace bool) []int {
	runes := source.runes()
	patterns := names.map(it.runes())
	mut offsets := []int{cap: runes.len}
	mut offset := 0
	for character in runes {
		offsets << offset
		offset += rune_bytes(character)
	}
	mut matches := []int{}
	for index, character in runes {
		if index > 0 && hosttest.module_word_rune(runes[index - 1]) { continue }
		for letters in patterns {
			if character != letters[0] || index + letters.len > runes.len { continue }
			mut same := true
			for number, letter in letters {
				if runes[index + number] != letter {
					same = false
					break
				}
			}
			if !same { continue }
			mut cursor := index + letters.len
			if whitespace {
				for cursor < runes.len && regex_space(runes[cursor]) { cursor++ }
			}
			if cursor < runes.len && runes[cursor] == `(` { matches << offsets[index] }
		}
	}
	return matches
}

fn rune_bytes(character rune) int {
	return if character < 0x80 {
		1
	} else if character < 0x800 {
		2
	} else if character < 0x10000 {
		3
	} else {
		4
	}
}

fn skip_space(source string) string {
	mut bytes := 0
	for character in source.runes() {
		if !regex_space(character) { break }
		bytes += rune_bytes(character)
	}
	return source[bytes..]
}

fn has_assignment(source string, name string, compound bool) bool {
	mut search := 0
	for search < source.len {
		at := source.index_after(name, search) or { break }
		search = at + name.len
		mut tail := skip_space(source[search..])
		if compound && (tail.starts_with('|') || tail.starts_with('&')) { tail = tail[1..] }
		if tail.starts_with('=') { return true }
	}
	return false
}

fn consume(tail string, token string) !string {
	if !tail.starts_with(token) { return error('token mismatch') }
	return tail[token.len..]
}

fn queued_transfers(source string) int {
	mut count := 0
	mut search := 0
	marker := 'unix__PendingFdGroup'
	for search < source.len {
		at := source.index_after(marker, search) or { break }
		search = at + marker.len
		if at > 0 && hosttest.module_word_rune(source[..at].runes().last()) { continue }
		mut tail := source[search..]
		spaced := skip_space(tail)
		if tail.len == spaced.len { continue }
		tail = spaced
		mut length := 0
		for character in tail.runes() {
			if !hosttest.module_word_rune(character) { break }
			length += rune_bytes(character)
		}
		if length == 0 { continue }
		variable := tail[..length]
		tail = skip_space(tail[length..])
		tail = consume(tail, '=') or { continue }
		tail = skip_space(tail)
		tail = consume(tail, '*group;') or { continue }
		tail = skip_space(tail)
		tail = consume(tail, 'array_push(&') or { continue }
		tail = consume(tail, 'peer') or { consume(tail, 'target') or { continue } }
		tail = consume(tail, '->pending_fd_groups,') or { continue }
		tail = skip_space(tail)
		consume(tail, '&' + variable + ');') or { continue }
		count++
	}
	return count
}
