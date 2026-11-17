// SPDX-License-Identifier: GPL-2.0-or-later
// The caller supplies its independently admitted directory capability declaration.
module winedircontenthost

import os
import json2
import tests.packages.winedircontent

pub struct Content {
pub mut:
	format int
	namespace string
	directories map[string][]string
}

pub fn capture(directories []string, namespace string) !string {
	if !os.is_abs_path(namespace) || namespace.len > 4096 || namespace.contains('\x00')
		|| os.real_path(namespace) != namespace || !os.is_dir(namespace) { return error('canonical original directory namespace required') }
	mut selected := map[string]bool{}
	for path in directories { selected[os.real_path(path)] = true }
	content := winedircontent.capture(selected.keys())!
	text := json2.encode(Content{format: 1, namespace: namespace, directories: content}) + '\n'
	if text.len > 8 * 1024 * 1024 { return error('read-closed directory content exceeds host bound') }
	return text
}

pub fn admit(path string, directories []string, namespace string) ! {
	st := os.lstat(path)!
	if st.get_filetype() != .regular || st.size == 0 || st.size > 8 * 1024 * 1024 {
		return error('read-closed directory content evidence must be bounded and ordinary')
	}
	$if macos {
		fd := C.open(path.str, C.O_RDONLY | C.O_NONBLOCK | C.O_NOFOLLOW | C.O_CLOEXEC)
		if fd < 0 { return error('cannot open directory content receipt') }
		defer { C.close(fd) }
		mut held := C.stat{}
		if C.fstat(fd, &held) != 0 || u64(held.st_dev) != st.dev || u64(held.st_ino) != st.inode
			|| held.st_size < 1 || u64(held.st_size) != st.size { return error('directory content receipt identity changed') }
		mut buffer := []u8{len: int(st.size) + 1}
		if C.read(fd, buffer.data, uint(buffer.len)) != int(st.size) { return error('directory content receipt bytes changed') }
		after := os.lstat(path)!
		if after.dev != st.dev || after.inode != st.inode || after.get_filetype() != .regular || after.size != st.size {
			return error('directory content receipt identity changed')
		}
		if buffer[..int(st.size)].bytestr() != capture(directories, namespace)! { return error('read-closed directory content differs') }
	} $else { return error('native directory contents require macOS') }
}
