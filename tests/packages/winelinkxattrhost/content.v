// SPDX-License-Identifier: GPL-2.0-or-later
// The caller supplies its independently admitted metadata-alias declaration.
module winelinkxattrhost

import os
import json2
import tests.packages.winelinkxattr

pub struct Content {
pub mut:
	format int
	namespace string
	links map[string]winelinkxattr.Link
}

pub fn capture(aliases map[string]string, namespace string) !string {
	if aliases.len == 0 || aliases.len > 128 { return error('bounded admitted link aliases required') }
	if !os.is_abs_path(namespace) || namespace.len > 4096 || namespace.contains('\x00')
		|| os.real_path(namespace) != namespace || !os.is_dir(namespace) { return error('canonical original link namespace required') }
	mut expected := map[string]string{}
	for path, body in aliases {
		node := winelinkxattr.canonical_node(path)!
		hex := body.bytes().hex()
		if node in expected && expected[node] != hex { return error('admitted link bodies disagree') }
		expected[node] = hex
	}
	links := winelinkxattr.capture(expected.keys())!
	for path, body in expected {
		if links[path].target_hex != body { return error('read-closed link body differs') }
	}
	text := json2.encode(Content{format: 1, namespace: namespace, links: links}) + '\n'
	if text.len > 8 * 1024 * 1024 { return error('read-closed link xattr content exceeds host bound') }
	return text
}

pub fn admit(path string, aliases map[string]string, namespace string) ! {
	st := os.lstat(path)!
	if st.get_filetype() != .regular || st.size == 0 || st.size > 8 * 1024 * 1024 {
		return error('read-closed link xattr evidence must be bounded and ordinary')
	}
	$if macos {
		fd := C.open(path.str, C.O_RDONLY | C.O_NONBLOCK | C.O_NOFOLLOW | C.O_CLOEXEC)
		if fd < 0 { return error('cannot open link xattr receipt') }
		defer { C.close(fd) }
		mut held := C.stat{}
		if C.fstat(fd, &held) != 0 || u64(held.st_dev) != st.dev || u64(held.st_ino) != st.inode
			|| held.st_size < 1 || u64(held.st_size) != st.size { return error('link xattr receipt identity changed') }
		mut buffer := []u8{len: int(st.size) + 1}
		if C.read(fd, buffer.data, uint(buffer.len)) != int(st.size) { return error('link xattr receipt bytes changed') }
		after := os.lstat(path)!
		if after.dev != st.dev || after.inode != st.inode || after.get_filetype() != .regular || after.size != st.size {
			return error('link xattr receipt identity changed')
		}
		if buffer[..int(st.size)].bytestr() != capture(aliases, namespace)! { return error('read-closed link xattr content differs') }
	} $else { return error('native link xattrs require macOS') }
}
