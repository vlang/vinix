// SPDX-License-Identifier: GPL-2.0-only
module policyhost
import hosttest

// Python's regex word and whitespace tables are Unicode 13. Scan UTF-8 by
// byte offsets so extracted source retains its exact original spelling.
fn rune_at(value string, offset int) (rune, int) {
	first := value[offset]
	length := if first < 0x80 { 1 } else if first < 0xe0 { 2 } else if first < 0xf0 { 3 } else { 4 }
	if offset + length > value.len { return rune(first), 1 }
	mut ch := u32(first & if length == 1 { u8(0x7f) } else if length == 2 { u8(0x1f) } else if length == 3 { u8(0x0f) } else { u8(0x07) })
	for i in 1 .. length { ch = (ch << 6) | u32(value[offset + i] & 0x3f) }
	return rune(ch), length
}
fn word(ch rune) bool { return hosttest.module_word_rune(ch) }
fn space(ch rune) bool { return ch in [rune(9), 10, 11, 12, 13, 28, 29, 30, 31, 32, 0x85, 0xa0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000] }
fn strip_right(value string) string {
	mut end := 0; mut pos := 0
	for pos < value.len { ch, size := rune_at(value, pos); pos += size; if !space(ch) { end = pos } }
	return value[..end]
}
fn whitespace_fields(value string) []string {
	mut result := []string{}; mut pos := 0; mut start := -1
	for pos < value.len { ch, size := rune_at(value, pos); if space(ch) { if start >= 0 { result << value[start..pos]; start = -1 } } else if start < 0 { start = pos }; pos += size }
	if start >= 0 { result << value[start..] }; return result
}
fn split_lines(value string) []string {
	mut lines := []string{}; mut pos := 0; mut start := 0
	for pos < value.len {
		ch, size := rune_at(value, pos)
		if ch in [rune(10), 11, 12, 13, 28, 29, 30, 0x85, 0x2028, 0x2029] {
			lines << value[start..pos]; pos += size
			if ch == 13 && pos < value.len && value[pos] == 10 { pos++ }; start = pos
		} else { pos += size }
	}
	if start < value.len { lines << value[start..] }; return lines
}
fn valid_prefix(prefix string) bool {
	if prefix == '' { return false }
	mut pos := 0
	for pos < prefix.len { ch, size := rune_at(prefix, pos); if !word(ch) && ch !in [rune(32), 42] { return false }; pos += size }; return true
}
fn signature(source string, name string, mounted bool) (int, int) {
	mut offset := 0
	for line in source.split('\n') {
		needle := if mounted { name + '(' } else { ' ' + name + '(' }
		if relative := line.index(needle) {
			prefix := line[..relative]
			boundary := !mounted || (prefix.len > 0 && !word(prefix.runes().last()))
			if valid_prefix(prefix) && boundary {
				tail := line[relative + needle.len..].all_before(';')
				if ending := tail.last_index(') {') { return offset, offset + relative + needle.len + ending + 2 }
			}
		}
		offset += line.len + 1
	}; return -1, -1
}
pub fn extract(source string, name string, family string) !string {
	start, matched_opening := signature(source, name, family == 'mounted')
	if start < 0 { return failure(if family == 'syscall' { 'SystemExit' } else { 'RuntimeError' }, if family == 'syscall' { 'Missing production function ' + name } else if family == 'mounted' { 'missing production function: ' + name } else { 'missing production function ' + name }) }
	opening := if family == 'mounted' { matched_opening } else { source.index_after('{', start) or { return failure('ValueError', 'substring not found') } }
	mut depth := 1; mut end := opening + 1
	for depth != 0 {
		if end >= source.len { return failure(if family == 'execute' { 'RuntimeError' } else { 'IndexError' }, if family == 'execute' { 'unterminated production function ' + name } else { 'string index out of range' }) }
		if source[end] == `{` { depth++ } else if source[end] == `}` { depth-- }; end++
	}
	body := source[start..end]
	if family == 'execute' && allocation(body, family) { return failure('RuntimeError', 'hidden allocation or copy in ' + name) }
	return body
}
pub fn allocation(body string, family string) bool {
	mut pos := 0
	for pos < body.len {
		ch, size := rune_at(body, pos)
		if !word(ch) { pos += size; continue }
		start := pos; pos += size
		for pos < body.len { next, length := rune_at(body, pos); if !word(next) { break }; pos += length }
		token := body[start..pos]
		mut cursor := pos
		for cursor < body.len { next, length := rune_at(body, cursor); if !space(next) { break }; cursor += length }
		if cursor == body.len || body[cursor] != `(` { continue }
		if family == 'execute' && (token.contains('malloc') || token.contains('calloc') || token.contains('realloc') || token.contains('memdup') || token.starts_with('new_array') || token in ['memcpy', 'memmove']) { return true }
		if family == 'syscall' && token in ['memdup', 'memdup_uncollectable', 'new_array', 'new_array_from_c_array'] { return true }
		if family == 'mounted' && (token in ['memdup', 'malloc', 'calloc', 'realloc', 'v_malloc', 'memory__malloc', 'array_slice', 'array_push', 'string__substr', 'new_array_from_c_array'] || token.starts_with('__new_array')) { return true }
	}; return false
}
fn index_required(value string, needle string) !int { return value.index(needle) or { return failure('ValueError', 'substring not found') } }
fn pan_adapter(value string) (string, int) {
	mut result := ''; mut cursor := 0; mut count := 0
	prefix := '__asm__ volatile ('
	for cursor < value.len {
		start := value.index_after(prefix, cursor) or { result += value[cursor..]; break }
		mut pos := start + prefix.len; mut matches := true
		for token in ['"msr pan, #1\\n\\t"', ':', ':', ':', '"memory"', ');'] {
			for pos < value.len { ch, size := rune_at(value, pos); if !space(ch) { break }; pos += size }
			if !value[pos..].starts_with(token) { matches = false; break }; pos += token.len
		}
		result += value[cursor..start]
		if matches { result += 'host_set_pan();'; cursor = pos; count++ } else { result += prefix; cursor = start + prefix.len }
	}; return result, count
}
