// SPDX-License-Identifier: GPL-2.0-or-later
module hosttest

import os
import strings

#include <sys/stat.h>
#include <errno.h>
#include <stdio.h>
#flag -I @DIR
#include "module_fs_abi.h"

fn C.fstat(i32, &C.stat) i32
fn C.vinix_module_stat_path(&char, &C.vinix_module_stat) i32
fn C.utimensat(i32, &char, &C.timespec, i32) i32
fn C.chflags(&char, u32) i32

@[typedef]
struct C.vinix_module_stat {
	st_mode                  u32
	st_atime                 i64
	st_mtime                 i64
	vinix_module_atime_nsec  i64
	vinix_module_mtime_nsec  i64
	st_flags                 u32
}

pub struct ModuleCopyFailure {
pub:
	source      string
	destination string
	message     string
}

pub struct ModuleCopyError {
pub:
	entries []ModuleCopyFailure
}

pub fn (failure ModuleCopyError) msg() string { return 'Source copy failed' }

pub fn (failure ModuleCopyError) code() int { return 0 }

pub struct ModuleFileError {
pub:
	filename string
	number   int
	message  string
}

pub fn (failure ModuleFileError) msg() string { return failure.message }

pub fn (failure ModuleFileError) code() int { return failure.number }

pub struct ModuleDecodeError {
pub:
	data   []u8
	start  int
	end    int
	reason string
}

pub fn (failure ModuleDecodeError) msg() string { return 'Invalid UTF-8 source: ' + failure.reason }

pub fn (failure ModuleDecodeError) code() int { return 0 }

fn module_utf8(text string) ! {
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
			return ModuleDecodeError{text.bytes(), index, index + 1, 'invalid start byte'}
		}
		for offset in 1 .. length {
			if index + offset >= text.len {
				return ModuleDecodeError{text.bytes(), index, text.len, 'unexpected end of data'}
			}
			byte := text[index + offset]
			valid := byte >= 0x80 && byte <= 0xbf && (offset != 1
				|| (ch != 0xe0 || byte >= 0xa0) && (ch != 0xed || byte <= 0x9f)
					&& (ch != 0xf0 || byte >= 0x90) && (ch != 0xf4 || byte <= 0x8f))
			if !valid {
				return ModuleDecodeError{text.bytes(), index, index + offset, 'invalid continuation byte'}
			}
		}
		index += length
	}
}

fn module_write(path string, text string) ! {
	if path.contains('\x00') { return error('embedded null byte') }
	stream := C.fopen(path.str, c'wb')
	if isnil(stream) { return ModuleFileError{path, int(C.errno), 'Cannot open module output'} }
	mut closed := false
	defer { if !closed { C.fclose(stream) } }
	C.errno = 0
	if C.fwrite(text.str, usize(1), usize(text.len), stream) != usize(text.len) {
		number := if C.errno == 0 { int(C.EIO) } else { int(C.errno) }
		return ModuleFileError{'', number, 'Cannot write module output'}
	}
	closed = true
	if C.fclose(stream) != 0 {
		return ModuleFileError{'', int(C.errno), 'Cannot close module output'}
	}
}

// Rewrite an actual generated artifact with the checked module I/O policy.
pub fn rewrite_generated_text(path string, before string, after string) ! {
	module_write(path, module_read(path)!.replace(before, after))!
}

fn module_read(path string) !string {
	if path.contains('\x00') { return error('embedded null byte') }
	mut stream := os.open(path) or { return ModuleFileError{path, err.code(), err.msg()} }
	defer { stream.close() }
	mut state := C.stat{}
	if C.fstat(i32(stream.fd), &state) != 0 {
		return ModuleFileError{'', int(C.errno), 'Cannot inspect opened source'}
	}
	if u32(state.st_mode) & u32(C.S_IFMT) == u32(C.S_IFDIR) {
		return ModuleFileError{path, int(C.EISDIR), 'Source is a directory'}
	}
	mut content := strings.new_builder(8192)
	mut buffer := []u8{len: 8192}
	for {
		count := stream.read(mut buffer) or {
			if err is os.Eof { break }
			return ModuleFileError{'', int(C.errno), err.msg()}
		}
		if count == 0 { break }
		content.write(buffer[..count])!
	}
	text := content.str()
	module_utf8(text)!
	return text.replace('\r\n', '\n').replace('\r', '\n')
}

fn module_paths(source string) ![]string {
	if source.contains('\x00') { return []string{} }
	entries := os.ls(source) or { return []string{} }
	return entries.filter(it.ends_with('.v')).map(module_join(source, it))
}

// These producers use Unix paths. A backslash is a literal filename byte,
// including inside the private source copy, rather than a path separator.
fn module_join(parent string, child string) string {
	return parent.trim_right('/') + '/' + child
}

fn module_name(path string) string {
	return path.trim_right('/').all_after_last('/')
}

fn module_copy(source string, destination string) ! {
	if !os.is_dir(source) {
		state := module_copy_snapshot(source)!
		module_copy_file(source, destination)!
		module_copy_apply_stat(state, destination)!
		return
	}
	names := os.ls(source) or { return ModuleFileError{source, err.code(), err.msg()} }
	os.mkdir(destination) or { return ModuleFileError{destination, err.code(), err.msg()} }
	mut failures := []ModuleCopyFailure{}
	for name in names {
		from := module_join(source, name)
		to := module_join(destination, name)
		module_copy(from, to) or {
			if err is ModuleCopyError {
				failures << err.entries
			} else if err is ModuleFileError {
				failures << ModuleCopyFailure{from, to, module_file_message(err)}
			} else {
				failures << ModuleCopyFailure{from, to, err.msg()}
			}
			continue
		}
	}
	module_copy_stat(source, destination) or {
		if err is ModuleFileError { failures << ModuleCopyFailure{source, destination, module_file_message(err)} }
		else { failures << ModuleCopyFailure{source, destination, err.msg()} }
		return ModuleCopyError{failures}
	}
	if failures.len > 0 { return ModuleCopyError{failures} }
}

fn module_file_message(failure ModuleFileError) string {
	mut message := '[Errno ${failure.number}] ' + unsafe { C.strerror(failure.number).vstring().clone() }
	if failure.filename != '' {
		quote := if failure.filename.contains("'") && !failure.filename.contains('"') { '"' } else { "'" }
		message += ': ' + quote + failure.filename.replace('\\', '\\\\').replace(quote, '\\' + quote)
			.replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t') + quote
	}
	return message
}

pub fn module_copy_file(source string, destination string) ! {
	state := os.stat(source) or { return ModuleFileError{source, err.code(), err.msg()} }
	if state.get_filetype() == .fifo { return error('`${source}` is a named pipe') }
	input := C.fopen(source.str, c'rb')
	if isnil(input) { return ModuleFileError{source, int(C.errno), 'Cannot open source copy'} }
	defer { C.fclose(input) }
	output := C.fopen(destination.str, c'wb')
	if isnil(output) { return ModuleFileError{destination, int(C.errno), 'Cannot open source destination'} }
	mut closed := false
	defer { if !closed { C.fclose(output) } }
	mut buffer := []u8{len: 8192}
	for {
		C.errno = 0
		count := C.fread(buffer.data, usize(1), usize(buffer.len), input)
		read_number := int(C.errno)
		if count > 0 && C.fwrite(buffer.data, usize(1), count, output) != count {
			number := if C.errno == 0 { int(C.EIO) } else { int(C.errno) }
			return ModuleFileError{'', number, 'Cannot write source destination'}
		}
		if C.ferror(input) != 0 {
			number := if read_number == 0 { int(C.EIO) } else { read_number }
			return ModuleFileError{'', number, 'Cannot read source copy'}
		}
		if count < usize(buffer.len) { break }
	}
	closed = true
	if C.fclose(output) != 0 { return ModuleFileError{'', int(C.errno), 'Cannot close source destination'} }
}

fn module_copy_stat(source string, destination string) ! {
	module_copy_apply_stat(module_copy_snapshot(source)!, destination)!
}

fn module_copy_snapshot(source string) !C.vinix_module_stat {
	mut state := C.vinix_module_stat{}
	if C.vinix_module_stat_path(source.str, &state) != 0 {
		return ModuleFileError{source, int(C.errno), 'Cannot inspect copied source'}
	}
	return state
}

fn module_copy_apply_stat(state C.vinix_module_stat, destination string) ! {
	times := [C.timespec{state.st_atime, state.vinix_module_atime_nsec},
		C.timespec{state.st_mtime, state.vinix_module_mtime_nsec}]!
	if C.utimensat(C.AT_FDCWD, destination.str, &times[0], 0) != 0 {
		return ModuleFileError{destination, int(C.errno), 'Cannot preserve source times'}
	}
	if C.chmod(destination.str, state.st_mode & 0o7777) != 0 {
		return ModuleFileError{destination, int(C.errno), 'Cannot preserve source permissions'}
	}
	$if macos {
		if C.chflags(destination.str, state.st_flags) != 0 && C.errno != C.ENOTSUP && C.errno != C.EOPNOTSUPP {
			return ModuleFileError{destination, int(C.errno), 'Cannot preserve source flags'}
		}
	}
}

fn module_remove_tree(path string) ! {
	if os.is_link(path) { os.rm(path)!; return }
	$if macos { C.chflags(path.str, 0) }
	if !os.is_dir(path) {
		os.rm(path)!
		return
	}
	os.chmod(path, 0o700)!
	for name in os.ls(path)! { module_remove_tree(module_join(path, name))! }
	os.rmdir(path)!
}

// Resolve existing links in order, including links above a not-yet-created
// output, while keeping the original CLI's non-strict missing-leaf behavior.
struct ModulePathPart {
	text   string
	retire string
}

pub fn module_resolve(path string) !string {
	if path.contains('\x00') { return error('embedded null byte') }
	mut pending := (if path.starts_with('/') { path } else { os.getwd() + '/' + path }).split('/').map(ModulePathPart{it, ''})
	mut parts := []string{}
	mut active := map[string]bool{}
	mut position := 0
	for position < pending.len {
		item := pending[position]
		position++
		if item.retire != '' {
			active.delete(item.retire)
			continue
		}
		piece := item.text
		if piece in ['', '.'] { continue }
		if piece == '..' {
			if parts.len > 0 { parts.delete_last() }
			continue
		}
		candidate := '/' + [...parts, piece].join('/')
		if os.is_link(candidate) {
			if candidate in active { return error('Symlink loop from ' + path) }
			active[candidate] = true
			target := os.readlink(candidate)!
			if target.starts_with('/') { parts.clear() }
			pending = [...target.split('/').map(ModulePathPart{it, ''}), ModulePathPart{'', candidate},
				...pending[position..]]
			position = 0
		} else {
			parts << piece
		}
	}
	return '/' + parts.join('/')
}

fn module_trim(text string) string {
	runes := text.runes()
	mut first := 0
	mut last := runes.len
	for first < last && module_space(runes[first]) { first++ }
	for last > first && module_space(runes[last - 1]) { last-- }
	return runes[first..last].string()
}

fn module_trim_right(text string) string {
	runes := text.runes()
	mut last := runes.len
	for last > 0 && module_space(runes[last - 1]) { last-- }
	return runes[..last].string()
}

fn module_lines(text string) []string {
	mut result := []string{}
	mut line := ''
	mut previous_cr := false
	for ch in text.runes() {
		if ch == `\n` && previous_cr {
			previous_cr = false
			continue
		}
		previous_cr = ch == `\r`
		if ch in [`\n`, `\r`, `\v`, `\f`, rune(0x1c), rune(0x1d), rune(0x1e), rune(0x85), rune(0x2028),
			rune(0x2029)] {
			result << line
			line = ''
		} else {
			line += ch.str()
		}
	}
	if line != '' { result << line }
	return result
}

fn module_identifier(text string) bool {
	runes := text.runes()
	return runes.len > 0 && runes.all(module_word(it))
}

fn module_replace(text string, word string, replacement string, prefix bool) string {
	runes := text.runes()
	selected := word.runes()
	mut result := strings.new_builder(text.len)
	mut index := 0
	for index < runes.len {
		end := index + selected.len
		if runes[index] == selected[0] && end <= runes.len && runes[index..end] == selected
			&& (index == 0 || !module_word(runes[index - 1]))
			&& (prefix || end == runes.len || !module_word(runes[end])) {
			result.write_string(replacement)
			index = end
		} else {
			result.write_rune(runes[index])
			index++
		}
	}
	return result.str()
}

fn module_has_word(text string, word string) bool {
	return module_replace(text, word, '', false) != text
}

fn module_skip_space(text []rune, begin int) int {
	mut index := begin
	for index < text.len && module_space(text[index]) { index++ }
	return index
}

fn module_foreign_scalars(raw string, name string) int {
	mut remaining := raw
	mut count := 0
	for remaining.contains('@[typedef]') {
		remaining = remaining.all_after('@[typedef]')
		runes := remaining.runes()
		start := module_skip_space(runes, 0)
		declaration := ('struct C.' + name).runes()
		end := start + declaration.len
		if end > runes.len || runes[start..end] != declaration { continue }
		brace := module_skip_space(runes, end)
		if brace >= runes.len || runes[brace] != `{` { continue }
		close := module_skip_space(runes, brace + 1)
		if close < runes.len && runes[close] == `}` { count++ }
	}
	return count
}

fn module_parameter_type(text string) string {
	runes := module_trim(text).runes()
	mut start := runes.len
	for start > 0 && module_word(runes[start - 1]) { start-- }
	if start < runes.len && start > 0 && module_space(runes[start - 1]) {
		for start > 0 && module_space(runes[start - 1]) { start-- }
		return runes[..start].string()
	}
	return runes.string()
}

fn module_word_tokens(text string) []string {
	mut result := []string{}
	mut token := ''
	for ch in (text + ' ').runes() {
		if module_word(ch) {
			token += ch.str()
		} else {
			if token != '' { result << token }
			token = ''
		}
	}
	return result
}

fn module_metadata_repr(records map[string][]string) string {
	mut result := []string{}
	for name, parameters in records {
		result << "'" + name + "': {" + parameters.map("'" + it + "'").join(', ') + '}'
	}
	return '{' + result.join(', ') + '}'
}
