// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import json2
import crypto.sha256
import tests.packages.winelinkxattr

const scope = 'bounded native macOS symlink-node xattr names/values and literal link bodies on explicit canonical-parent paths; final targets are not dereferenced; full host capability coverage remains separate'

struct Receipt {
	format int
	scope string
	targets_sha256 string
	source_sha256 string
	module_sha256 string
	tool_sha256 string
	limits_sha256 string
	links map[string]winelinkxattr.Link
}

fn digest(path string) !string { return sha256.hexhash(os.read_file(path)!) }

fn source_pins() !(string, string, string) {
	main_source := $embed_file('wine-link-xattr-content.v').to_string()
	module_source := $embed_file('winelinkxattr/content.v').to_string()
	limits_source := $embed_file('winexattr/content.v').to_string()
	limits_hash := sha256.hexhash(limits_source)
	main_hash := sha256.hexhash(main_source)
	module_hash := sha256.hexhash(module_source)
	if digest(@FILE)! != main_hash || digest(os.dir(@FILE) + '/winelinkxattr/content.v')! != module_hash
		|| digest(os.dir(@FILE) + '/winexattr/content.v')! != limits_hash {
		return error('compiled xattr inventory source differs')
	}
	return main_hash, module_hash, limits_hash
}

fn ordinary(path string, bound u64) !string {
	st := os.lstat(path)!
	if st.get_filetype() != .regular || st.size == 0 || st.size > bound { return error('bounded ordinary xattr declaration required') }
	$if macos {
		fd := C.open(path.str, C.O_RDONLY | C.O_NONBLOCK | C.O_NOFOLLOW | C.O_CLOEXEC)
		if fd < 0 { return error('cannot open xattr declaration') }
		defer { C.close(fd) }
		mut held := C.stat{}
		if C.fstat(fd, &held) != 0 || u64(held.st_dev) != st.dev || u64(held.st_ino) != st.inode
			|| held.st_size < 1 || u64(held.st_size) != st.size { return error('xattr declaration identity changed') }
		mut buffer := []u8{len: int(st.size) + 1}
		if C.read(fd, buffer.data, uint(buffer.len)) != int(st.size) { return error('xattr declaration bytes changed') }
		after := os.lstat(path)!
		if after.dev != st.dev || after.inode != st.inode || after.get_filetype() != .regular || after.size != st.size {
			return error('xattr declaration identity changed')
		}
		return buffer[..int(st.size)].bytestr()
	} $else { return error('native xattr content requires macOS') }
}

fn publish(path string, text string) ! {
	$if macos {
		fd := C.open(path.str, C.O_CREAT | C.O_EXCL | C.O_WRONLY | C.O_CLOEXEC, 0o600)
		if fd < 0 { return error('fresh xattr receipt required') }
		defer { C.close(fd) }
		if C.write(fd, text.str, text.len) != text.len { return error('xattr receipt write failed') }
	} $else { return error('native xattr content requires macOS') }
}

fn run() ! {
	if os.args.len != 4 || os.args[1] !in ['capture', 'check'] { return error('usage: LINK_XATTR_CONTENT capture|check TARGETS_JSON RECEIPT_JSON') }
	$if !prod { return error('production xattr inventory required') }
	source, module_source, limits := source_pins()!
	tool := digest(os.executable())!
	manifest := ordinary(os.args[2], 1048576)!
	selected := json2.decode[[]string](manifest)!
	// Snapshot current link-node attributes without dereferencing the final target.
	links := winelinkxattr.capture(selected)!
	expected := Receipt{format: 1, scope: scope, targets_sha256: sha256.hexhash(manifest),
		source_sha256: source, module_sha256: module_source, tool_sha256: tool, limits_sha256: limits, links: links}
	source_pins()!
	if digest(os.executable())! != tool || ordinary(os.args[2], 1048576)! != manifest {
		return error('xattr inventory inputs changed')
	}
	encoded := json2.encode(expected) + '\n'
	if encoded.len > 67108864 { return error('xattr receipt oversized') }
	if os.args[1] == 'check' {
		if ordinary(os.args[3], 67108864)! != encoded { return error('native xattr content or declaration differs') }
	} else {
		publish(os.args[3], encoded)!
	}
	println('WINE LINK XATTR CONTENT PASS ' + os.args[1] + ' ' + links.len.str() + ' targets')
}

fn main() { run() or { eprintln(err); exit(1) } }
