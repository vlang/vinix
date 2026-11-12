// SPDX-License-Identifier: GPL-2.0-only
module stagehost

import hosttest
import json2
import os
import strconv

#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

fn native(operation string, row map[string]json2.Any) !json2.Any {
	args := (row['args'] or { json2.Any([]json2.Any{}) }).as_array().map(decode(it.str())!)
	match operation {
		'path' {
			value := match row['function']!.str() {
				'join' { posix_join(args) }
				'normpath' { posix_normal(args[0]) }
				'abspath' { posix_normal(if args[0].starts_with('/') { args[0] } else { posix_join([os.getwd(), args[0]]) }) }
				'basename' { args[0].all_after_last('/') }
				else { return error('unknown staging path operation') }
			}
			return value.bytes().hex()
		}
		'test' {
			return match row['function']!.str() {
				'lexists' { os.is_link(args[0]) || os.exists(args[0]) }
				'isfile' { os.is_file(args[0]) }
				'isdir' { os.is_dir(args[0]) }
				'exists' { os.exists(args[0]) }
				else { return error('unknown staging filesystem predicate') }
			}
		}
		'list' { return encoded(os.ls(args[0])!) }
		'read' {
			if row['binary']!.bool() { return os.read_bytes(args[0])!.hex() }
			return hosttest.module_read_text(args[0])!.bytes().hex()
		}
		'write' { hosttest.module_write_text(args[0], args[1])! }
		'open_write' {
			fd := unsafe { C.open(args[0].str, C.O_WRONLY | C.O_CREAT | C.O_TRUNC | C.O_CLOEXEC, 0o666) }
			if fd < 0 { return os.error_posix() }
			return fd.str()
		}
		'write_handle' {
			fd := strconv.atoi(row['handle']!.str())!
			hosttest.module_decode_utf8(args[0])!
			mut offset := 0
			for offset < args[0].len {
				count := unsafe { C.write(fd, args[0].str + offset, uint(args[0].len - offset)) }
				if count < 0 { if C.errno == C.EINTR { continue }; return os.error_posix() }
				if count == 0 { return error('cannot write staged source') }
				offset += int(count)
			}
		}
		'close_handle' { if C.close(strconv.atoi(row['handle']!.str())!) != 0 { return os.error_posix() } }
		'remove' { os.rm(args[0])! }
		'symlink' { os.symlink(args[0], args[1])! }
		'mkdir' {
			if !row['exist_ok']!.bool() && os.exists(args[0]) { return error('staging directory already exists: ' + args[0]) }
			os.mkdir_all(args[0])!
		}
		'rmtree' {
			// shutil.rmtree rejects a link to a directory instead of unlinking it.
			if os.is_link(args[0]) { return error('cannot remove a staging directory symlink') }
			os.rmdir_all(args[0])!
		}
		'copy' { hosttest.module_copy_file(args[0], args[1])! }
		'strip' { return strip_space(args[0]).bytes().hex() }
		'regex' {
			if row['full']!.bool() { return c_identifier(args[1]) }
			return json2.Any(pattern_rows(args[0], args[1])!)
		}
		'print' { println(args[0]) }
		else { return error('unknown native staging operation ' + operation) }
	}
	return json2.Null{}
}

fn posix_join(values []string) string {
	mut joined := ''
	for value in values {
		if value.starts_with('/') || joined == '' { joined = value } else {
			joined += if joined.ends_with('/') { value } else { '/' + value }
		}
	}
	return joined
}

fn posix_normal(value string) string {
	prefix := if value.starts_with('//') && !value.starts_with('///') { '//' } else if value.starts_with('/') { '/' } else { '' }
	mut parts := []string{}
	for part in value.split('/') {
		if part == '' || part == '.' { continue }
		if part == '..' && parts.len > 0 && parts.last() != '..' { parts.delete_last() }
		else if part != '..' || prefix == '' { parts << part }
	}
	text := prefix + parts.join('/')
	return if text == '' { '.' } else { text }
}

fn space(ch rune) bool { return ch in [`\t`, `\n`, `\v`, `\f`, `\r`, ` `, 0x85, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000] || (ch >= 0x1c && ch <= 0x1f) || (ch >= 0x2000 && ch <= 0x200a) }
fn strip_space(value string) string {
	mut end := value.len
	for ch in value.runes().reverse() { if !space(ch) { break }; end -= ch.str().len }
	return value[..end]
}
fn c_start(ch u8) bool { return ch == `_` || ch >= `a` && ch <= `z` || ch >= `A` && ch <= `Z` }
fn c_identifier(value string) bool { return value.len > 0 && c_start(value[0]) && value.bytes().all(c_start(it) || it.is_digit()) }

// Match only the fixed patterns used by the maintained staging policies. Offsets
// are UTF-8 byte positions; identifier boundaries use the shared Unicode table.
fn pattern_rows(pattern string, text string) ![]json2.Any {
	mut offsets := [0]
	runes := text.runes()
	mut position := 0
	mut words := map[int]bool{}
	mut following := map[int]int{}
	mut whitespace := map[int]int{}
	for ch in runes {
		words[position] = hosttest.module_word_rune(ch)
		if space(ch) { whitespace[position] = ch.str().len }
		length := ch.str().len
		following[position] = position + length
		position += length
		offsets << position
	}
	mut rows := []json2.Any{}
	if pattern == main_pattern {
		for index in offsets {
			if (index == 0 || text[index - 1] == `\n`) && text[index..].starts_with('fn main() {') {
				rows << match_row(index, index + 11, [], [])
			}
		}
		return rows
	}
	if pattern == entries_pattern {
		mut index := 0
		for index < text.len {
			if text[index] !in [u8(39), 34] { index++; continue }
			start := index
			index++
			begin := index
			for index < text.len && text[index] !in [u8(39), 34] { index++ }
			if index < text.len && index > begin { rows << match_row(start, index + 1, [text[begin..index]], [[begin, index]!]); index++ }
		}
		return rows
	}
	if pattern == subdirs_pattern || pattern == embedded_view_pattern {
		mut next := 0
		for number, index in offsets {
			if index < next { continue }
			if pattern == subdirs_pattern {
				previous_word := number > 0 && words[offsets[number - 1]]
				if previous_word || !text[index..].starts_with('subdirs') { continue }
				mut cursor := skip_space(index + 7, whitespace)
				if cursor >= text.len || text[cursor] != `:` { continue }
				cursor = skip_space(cursor + 1, whitespace)
				if cursor >= text.len || text[cursor] != `[` { continue }
				begin := cursor + 1
				end := text.index_after(']', begin) or { continue }
				rows << match_row(index, end + 1, [text[begin..end]], [[begin, end]!])
				next = end + 1
			} else {
				if (index > 0 && text[index - 1] != `\n`) || !text[index..].starts_with('const') { continue }
				mut cursor := skip_space(index + 5, whitespace)
				if cursor == index + 5 || cursor >= text.len || !c_start(text[cursor]) { continue }
				begin := cursor
				cursor++
				for cursor < text.len && words[cursor] {
					cursor = following[cursor]
				}
				name_end := cursor
				name := text[begin..cursor]
				if name.len <= 11 || (!name.ends_with('_qml_source') && !name.ends_with('_vml_source')) { continue }
				cursor = skip_space(cursor, whitespace)
				if cursor >= text.len || text[cursor] != `=` { continue }
				cursor = skip_space(cursor + 1, whitespace)
				if !text[cursor..].starts_with('\$embed_file(') { continue }
				argument := cursor + 12
				end := text.index_after('\n', argument) or { continue }
				if !text[argument..end].ends_with(').to_string()') || end - argument <= 13 { continue }
				rows << match_row(index, end + 1, [name], [[begin, name_end]!])
				next = end + 1
			}
		}
		return rows
	}
	if pattern.starts_with('\\b') && pattern.ends_with('\\b') {
		name := pattern[2..pattern.len - 2]
		mut next := 0
		for number, index in offsets {
			if index < next || !text[index..].starts_with(name) { continue }
			end := index + name.len
			if (number > 0 && words[offsets[number - 1]]) || words[end] { continue }
			rows << match_row(index, end, [], [])
			next = end
		}
		return rows
	}
	return error('unsupported staging pattern')
}

fn skip_space(start int, whitespace map[int]int) int {
	mut cursor := start
	for (cursor in whitespace) { cursor += whitespace[cursor] }
	return cursor
}
fn match_row(start int, end int, groups []string, spans [][2]int) json2.Any {
	return json2.Any({'start': json2.Any(start), 'end': json2.Any(end), 'groups': encoded(groups),
		'spans': json2.Any(spans.map(json2.Any([json2.Any(it[0]), json2.Any(it[1])])))})
}
