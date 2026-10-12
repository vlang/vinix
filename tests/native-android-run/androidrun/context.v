// SPDX-License-Identifier: GPL-2.0-or-later
module androidrun

import androidhost as ah
import boothost
import hosttest
import json2
import os
import runhost
import tarcore
import tarstream
import strconv

pub struct Plan {
pub:
	command     []string
	environment map[string]string
	directory   string
}

@[heap]
struct Archive {
mut:
	path    string
	reading bool
	closed  bool
	reader  tarstream.Reader
	writer  tarcore.Writer
	inodes  map[string]string
}

@[heap]
pub struct Context {
pub:
	root string
pub mut:
	args            map[string]ah.Value
	prepare_hook    fn (mut Context) !ah.Value               = unsafe { nil }
	plan_hook       fn (map[string]ah.Value, ah.Value) !Plan = unsafe { nil }
	command_hook    fn ([]string, voidptr) !                 = unsafe { nil }
	command_context voidptr
mut:
	inodes    map[string]string
	files     map[int]os.File
	archives  []&Archive
	infos     []tarcore.Member
	next_file int
}

fn null() ah.Value { return ah.Value(json2.Null{}) }

fn text(row map[string]ah.Value, key string) string { return ah.field(row, key).text() }

fn number(value ah.Value) !i64 {
	if value is ah.Number { return strconv.parse_int(value.text, 10, 64)! }
	if value is int { return i64(value) }
	if value is i64 { return value }
	if value is u64 {
		if value > u64(0x7fffffffffffffff) { return error('integer out of range') }
		return i64(value)
	}
	return error('expected integer')
}

fn truth(value ah.Value) bool {
	return match value {
		json2.Null { false }
		bool { value }
		string { value != '' }
		[]ah.Value { value.len > 0 }
		map[string]ah.Value { value.len > 0 }
		else { !boothost.receipt_equal(value, ah.Value(0)) }
	}
}

fn ordinary(value ah.Value) string {
	return match value {
		string { value }
		json2.Null { 'None' }
		bool {
			if value { 'True' } else { 'False' }
		}
		else { ah.encode(value) }
	}
}

fn android_callback(operation string, row map[string]ah.Value, pointer voidptr) !ah.Value {
	mut context := unsafe { &Context(pointer) }
	return context.primitive(operation, row)!
}

pub fn (mut context Context) call(operation string, arguments map[string]ah.Value) !ah.Value {
	previous, pointer := runhost.set_native_callback(android_callback, context)
	defer { runhost.set_native_callback(previous, pointer) }
	return runhost.dispatch({
		'operation': ah.Value(operation)
		'arguments': ah.Value(arguments)
		'root':      ah.Value(context.root)
	})!
}

pub fn (mut context Context) close() {
	for _, file in context.files {
		mut owned := file
		owned.close()
	}
	context.files.clear()
	for mut archive in context.archives {
		if archive.closed { continue }
		archive.closed = true
		if archive.reading {
			archive.reader.close()
		} else {
			archive.writer.close()
		}
	}
}

fn parent(path string) string {
	index := path.last_index('/') or { return '.' }
	return if index == 0 { '/' } else { path[..index] }
}

fn join(parts []string) string {
	mut result := ''
	for part in parts {
		if part.starts_with('/') {
			result = part
		} else if part != '' && part != '.' {
			result = if result == '' { part } else { result.trim_right('/') + '/' + part }
		}
	}
	return if result == '' { '.' } else { result }
}

fn parents(path string) ! {
	if os.is_dir(path) { return }
	previous := parent(path)
	if previous != path { parents(previous)! }
	os.mkdir(path)!
}

fn path_suffix(path string) string {
	name := path.all_after_last('/')
	at := name.last_index('.') or { return '' }
	return if at == 0 || at == name.len - 1 { '' } else { name[at..] }
}

fn with_suffix(path string, suffix string) !string {
	if path.all_after_last('/') in ['', '.', '..'] || (suffix != '' && (!suffix.starts_with('.') || suffix.contains('/'))) {
		return error('invalid suffix or empty file name')
	}
	previous := path_suffix(path)
	return path[..path.len - previous.len] + suffix
}

fn paths(directory string, recursive bool) ![]string {
	if !os.is_dir(directory) { return []string{} }
	mut result := []string{}
	for name in os.ls(directory)! {
		path := directory.trim_right('/') + '/' + name
		result << path
		if recursive && !os.is_link(path) && os.is_dir(path) { result << paths(path, true)! }
	}
	return result
}

fn read_text(path string) !string { return hosttest.module_read_text(path)! }

fn write_text(path string, data string) ! { hosttest.module_write_text(path, data)! }

fn write_bytes(mut file os.File, bytes []u8) ! {
	mut offset := 0
	for offset < bytes.len {
		count := file.write(bytes[offset..])!
		if count <= 0 { return error('file write stopped') }
		offset += count
	}
}

fn (mut context Context) path(row map[string]ah.Value) !ah.Value {
	path := text(row, 'path')
	arguments := ah.field(row, 'arguments').items()
	options := ah.field(row, 'options').object()
	return match text(row, 'method') {
		'name' { ah.Value(path.all_after_last('/')) }
		'parent' { ah.Value(parent(path)) }
		'suffix' { ah.Value(path_suffix(path)) }
		'parts' { ah.Value(path.split('/').filter(it != '' && it != '.').map(ah.Value(it))) }
		'resolve' { ah.Value(hosttest.module_resolve(path)!) }
		'with_suffix' { ah.Value(with_suffix(path, arguments[0].text())!) }
		'with_name' { ah.Value(join([parent(path), arguments[0].text()])) }
		'relative_to' {
			base := arguments[0].text().trim_right('/')
			if path != base && !path.starts_with(base + '/') {
				return error('path is outside its base')
			}
			ah.Value(if path == base { '.' } else { path[base.len + 1..] })
		}
		'exists' { ah.Value(os.exists(path)) }
		'is_file' { ah.Value(os.is_file(path)) }
		'is_dir' { ah.Value(os.is_dir(path)) }
		'is_symlink' { ah.Value(os.is_link(path)) }
		'write_text' {
			write_text(path, arguments[0].text())!
			ah.Value(arguments[0].text().runes().len)
		}
		'read_text' { ah.Value(read_text(path)!) }
		'unlink' {
			os.rm(path)!
			null()
		}
		'chmod' {
			os.chmod(path, int(number(arguments[0])!))!
			null()
		}
		'mkdir' {
			if os.is_dir(path) && truth(ah.field(options, 'exist_ok')) { return null() }
			if truth(ah.field(options, 'parents')) { parents(parent(path))! }
			mode := if 'mode' in options { int(number(options['mode']!)!) } else { 0o777 }
			if C.mkdir(path.str, u32(mode)) != 0 { return os.error_posix() }
			null()
		}
		'symlink_to' {
			os.symlink(arguments[0].text(), path)!
			null()
		}
		else { return error('unsupported native path method: ' + text(row, 'method')) }
	}
}
