// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import json2
import crypto.sha256
import tests.packages.winedircontent

const scope = 'bounded native macOS immediate directory entry names on explicit canonical absolute directories; children are not opened or followed; full host capability coverage remains separate'

struct Receipt {
	format int
	scope string
	targets_sha256 string
	source_sha256 string
	module_sha256 string
	tool_sha256 string
	directories map[string][]string
}

fn digest(path string) !string { return sha256.hexhash(os.read_file(path)!) }

fn source_pins() !(string, string) {
	main_source := $embed_file('wine-directory-content.v').to_string()
	module_source := $embed_file('winedircontent/content.v').to_string()
	main_hash := sha256.hexhash(main_source)
	module_hash := sha256.hexhash(module_source)
	if digest(@FILE)! != main_hash || digest(os.dir(@FILE) + '/winedircontent/content.v')! != module_hash {
		return error('compiled directory inventory source differs')
	}
	return main_hash, module_hash
}

fn ordinary(path string, bound u64) !string {
	st := os.lstat(path)!
	if st.get_filetype() != .regular || st.size == 0 || st.size > bound { return error('bounded ordinary directory declaration required') }
	$if macos {
		fd := C.open(path.str, C.O_RDONLY | C.O_NONBLOCK | C.O_NOFOLLOW | C.O_CLOEXEC)
		if fd < 0 { return error('cannot open directory declaration') }
		defer { C.close(fd) }
		mut held := C.stat{}
		if C.fstat(fd, &held) != 0 || u64(held.st_dev) != st.dev || u64(held.st_ino) != st.inode
			|| held.st_size < 1 || u64(held.st_size) != st.size { return error('directory declaration identity changed') }
		mut buffer := []u8{len: int(st.size) + 1}
		if C.read(fd, buffer.data, uint(buffer.len)) != int(st.size) { return error('directory declaration bytes changed') }
		after := os.lstat(path)!
		if after.dev != st.dev || after.inode != st.inode || after.get_filetype() != .regular || after.size != st.size {
			return error('directory declaration identity changed')
		}
		return buffer[..int(st.size)].bytestr()
	} $else { return error('native directory content requires macOS') }
}

fn publish(path string, text string) ! {
	$if macos {
		fd := C.open(path.str, C.O_CREAT | C.O_EXCL | C.O_WRONLY | C.O_CLOEXEC, 0o600)
		if fd < 0 { return error('fresh directory receipt required') }
		defer { C.close(fd) }
		if C.write(fd, text.str, text.len) != text.len { return error('directory receipt write failed') }
	} $else { return error('native directory content requires macOS') }
}

fn run() ! {
	if os.args.len != 4 || os.args[1] !in ['capture', 'check'] { return error('usage: DIRECTORY_CONTENT capture|check TARGETS_JSON RECEIPT_JSON') }
	$if !prod { return error('production directory inventory required') }
	source, module_source := source_pins()!
	tool := digest(os.executable())!
	manifest := ordinary(os.args[2], 1048576)!
	selected := json2.decode[[]string](manifest)!
	if os.real_path(os.dir(os.abs_path(os.args[3]))) in selected {
		return error('directory receipt must be outside observed directories')
	}
	// Enumerate immediate names without opening child entries.
	directories := winedircontent.capture(selected)!
	expected := Receipt{format: 1, scope: scope, targets_sha256: sha256.hexhash(manifest),
		source_sha256: source, module_sha256: module_source, tool_sha256: tool, directories: directories}
	source_pins()!
	if digest(os.executable())! != tool || ordinary(os.args[2], 1048576)! != manifest {
		return error('directory inventory inputs changed')
	}
	encoded := json2.encode(expected) + '\n'
	if encoded.len > 8388608 { return error('directory receipt oversized') }
	if os.args[1] == 'check' {
		if ordinary(os.args[3], 8388608)! != encoded { return error('native directory content or declaration differs') }
	} else {
		publish(os.args[3], encoded)!
	}
	println('WINE DIRECTORY CONTENT PASS ' + os.args[1] + ' ' + directories.len.str() + ' targets')
}

fn main() { run() or { eprintln(err); exit(1) } }
