// SPDX-License-Identifier: GPL-2.0-or-later
module iosbuild

import cachecli
import cachekey
import crypto.sha256
import os
import sourcecommand

fn C.mkdtemp(&char) &char

pub fn private_directory(base string) !string {
	mkdir(base)!
	mut bytes := (base + '/.ios-native.XXXXXX\x00').bytes()
	if C.mkdtemp(&char(bytes.data)) == unsafe { nil } { return os.error_posix() }
	return bytes[..bytes.len - 1].bytestr()
}

pub fn publish(path string, text string) ! {
	work := private_directory(parent(path))!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/output', text)!
	cachecli.replace_file(work + '/output', path)!
}

pub struct Tools {
pub:
	root         string
	command_hook fn ([]string, voidptr) !sourcecommand.Output = unsafe { nil }
	context      voidptr
}

pub fn (tools Tools) command(argv []string) !sourcecommand.Output {
	if tools.command_hook != unsafe { nil } { return tools.command_hook(argv, tools.context)! }
	return sourcecommand.capture_full(argv, os.environ(), -1, 64 * 1024 * 1024, cachecli.cancelled)!
}

pub fn (tools Tools) combined(argv []string) !sourcecommand.Output {
	if tools.command_hook != unsafe { nil } {
		return tools.command_hook(argv, tools.context)!
	}
	return sourcecommand.capture_combined(argv, os.environ(), -1, 64 * 1024 * 1024, cachecli.cancelled)!
}

pub fn (tools Tools) checked(argv []string) !string {
	result := tools.command(argv)!
	if result.status != 0 {
		return error('iOS command failed: ' + argv.str() + '\n' + result.stdout + result.stderr)
	}
	return result.stdout
}

pub fn parent(path string) string {
	at := path.last_index('/') or { return '.' }
	return if at == 0 { '/' } else { path[..at] }
}

pub fn mkdir(path string) ! {
	if path in ['', '.', '/'] || os.is_dir(path) { return }
	mkdir(parent(path))!
	os.mkdir(path) or { if !os.is_dir(path) { return err } }
}

pub fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := file.read(mut buffer) or { if err is os.Eof { 0 } else { return err } }
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	return hash.sum([]u8{}).hex()
}

pub fn dispatch(root string, command string, argv []string) !int {
	tools := Tools{ root: root }
	return match command {
		'build-cxx' { build_cxx_cli(tools, argv)! }
		'generate-cxx-symbols' { symbols_cli(tools, argv)! }
		'stage-gles' { gles_cli(tools, argv)! }
		else { return error_with_code('unknown iOS build command: ' + command, 2) }
	}
}

pub fn resolved(path string) !string { return cachekey.resolve_path(path)! }
