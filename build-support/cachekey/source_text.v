// SPDX-License-Identifier: GPL-2.0-or-later
module cachekey

import os
import strings

pub struct TextDecodeError {
pub:
	data   []u8
	start  int
	end    int
	reason string
}

pub fn (e TextDecodeError) code() int { return 0 }

pub fn (e TextDecodeError) msg() string { return e.reason }

fn validate_utf8(text string) ! {
	mut index := 0
	for index < text.len {
		ch := text[index]
		if ch < 0x80 {
			index++
			continue
		}
		length := if ch >= 0xc2 && ch <= 0xdf {
			2
		} else if ch >= 0xe0 && ch <= 0xef {
			3
		} else if ch >= 0xf0 && ch <= 0xf4 {
			4
		} else {
			0
		}
		if length == 0 {
			return TextDecodeError{text.bytes(), index, index + 1, 'invalid start byte'}
		}
		for offset in 1 .. length {
			if index + offset >= text.len {
				return TextDecodeError{text.bytes(), index, text.len, 'unexpected end of data'}
			}
			byte := text[index + offset]
			valid := byte >= 0x80 && byte <= 0xbf && (offset != 1
				|| (ch != 0xe0 || byte >= 0xa0) && (ch != 0xed || byte <= 0x9f)
					&& (ch != 0xf0 || byte >= 0x90) && (ch != 0xf4 || byte <= 0x8f))
			if !valid {
				return TextDecodeError{text.bytes(), index, index + offset, 'invalid continuation byte'}
			}
		}
		index += length
	}
}

fn source_text(path string) !string {
	if path.contains('\x00') { return error('embedded null byte') }
	mut stream := os.open(path) or { return file_error(path) }
	defer { stream.close() }
	mut state := C.vinix_cache_stat{}
	if C.vinix_cache_fstat(i32(stream.fd), &state) != 0 { return file_error('') }
	if state.st_mode & u32(C.S_IFMT) == u32(C.S_IFDIR) { return FileError{int(C.EISDIR), path} }
	mut text := strings.new_builder(8192)
	mut buffer := []u8{len: 8192}
	for {
		count := stream.read(mut buffer) or {
			if err is os.Eof { break }
			return file_error('')
		}
		if count == 0 { break }
		text.write(buffer[..count])!
	}
	result := text.str()
	validate_utf8(result)!
	return result.replace('\r\n', '\n').replace('\r', '\n')
}

fn regex_space(ch rune) bool {
	return ch in [` `, `\t`, `\n`, `\r`, `\v`, `\f`, rune(0x85), rune(0xa0), rune(0x1680),
		rune(0x2028), rune(0x2029), rune(0x202f), rune(0x205f), rune(0x3000)] || (ch >= 0x1c && ch <= 0x1f) || (ch >= 0x2000 && ch <= 0x200a)
}

pub fn subdirs_text(text string) []string {
	runes := text.runes()
	needle := 'subdirs'.runes()
	for index in 0 .. runes.len {
		if index > 0 && source_word(runes[index - 1]) { continue }
		if index + needle.len > runes.len || runes[index..index + needle.len] != needle { continue }
		mut cursor := index + needle.len
		for cursor < runes.len && regex_space(runes[cursor]) { cursor++ }
		if cursor >= runes.len || runes[cursor] != `:` { continue }
		cursor++
		for cursor < runes.len && regex_space(runes[cursor]) { cursor++ }
		if cursor >= runes.len || runes[cursor] != `[` { continue }
		cursor++
		start := cursor
		for cursor < runes.len && runes[cursor] != `]` { cursor++ }
		if cursor == runes.len { continue }
		mut result := []string{}
		mut item := start
		for item < cursor {
			if runes[item] !in [`'`, `"`] {
				item++
				continue
			}
			begin := item + 1
			mut end := begin
			for end < cursor && runes[end] !in [`'`, `"`] { end++ }
			if end > begin && end < cursor {
				result << runes[begin..end].string()
				item = end + 1
			} else {
				item++
			}
		}
		return result
	}
	return []string{}
}

pub fn module_subdirs(source string) ![]string {
	return subdirs_text(source_text(join_path(source, 'v.mod'))!)
}

pub fn office_imports(text string) []string {
	runes := text.runes()
	needle := 'office.'.runes()
	mut result := []string{}
	mut index := 0
	for index < runes.len {
		if (index > 0 && source_word(runes[index - 1])) || index + needle.len >= runes.len || runes[index..index + needle.len] != needle {
			index++
			continue
		}
		begin := index + needle.len
		if !ascii_identifier_start(runes[begin]) {
			index++
			continue
		}
		mut end := begin + 1
		for end < runes.len && (ascii_identifier_start(runes[end]) || (runes[end] >= `0` && runes[end] <= `9`)) {
			end++
		}
		result << runes[begin..end].string()
		index = end
	}
	return result
}

fn ascii_identifier_start(ch rune) bool {
	return (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || ch == `_`
}
