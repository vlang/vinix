// SPDX-License-Identifier: GPL-2.0-or-later
// Bounded native attribute contents; separate from ordinary file-byte admission.
module winexattr

import os

pub const max_targets = 2048
pub const max_names = 256
pub const max_value = 1048576
pub const max_total = 16777216

$if macos {
	#include <sys/xattr.h>
	#include <sys/stat.h>
	#include <fcntl.h>
	fn C.flistxattr(int, &char, uint, int) int
	fn C.fgetxattr(int, &char, voidptr, uint, u32, int) int
}

pub struct Object {
pub:
	kind string
	// Both names and values are hex: native attributes need not contain UTF-8.
	values map[string]string
}

struct Budget {
mut:
	bytes int
}

pub fn paths(selected []string) ![]string {
	if selected.len == 0 || selected.len > max_targets { return error('bounded nonempty xattr targets required') }
	mut ordered := selected.clone()
	ordered.sort()
	mut previous := ''
	for path in ordered {
		if !os.is_abs_path(path) || path.len > 4096 || path.contains('\x00') || path == previous
			|| os.real_path(path) != path { return error('canonical unique xattr targets required') }
		if os.lstat(path)!.get_filetype() !in [.regular, .directory] { return error('ordinary xattr target required') }
		previous = path
	}
	return ordered
}

fn names(fd int) ![]string {
	$if macos {
		length := C.flistxattr(fd, unsafe { nil }, 0, C.XATTR_SHOWCOMPRESSION)
		if length < 0 || length > 65536 { return error('xattr name list unreadable or oversized') }
		mut buffer := []u8{len: length + 1}
		actual := C.flistxattr(fd, &char(buffer.data), uint(buffer.len), C.XATTR_SHOWCOMPRESSION)
		if actual != length { return error('xattr name list changed') }
		if length == 0 { return []string{} }
		if buffer[length - 1] != 0 { return error('unterminated xattr name list') }
		mut result := buffer[..length - 1].bytestr().split('\x00')
		if result.len > max_names { return error('too many xattr names') }
		result.sort()
		mut previous := ''
		for name in result {
			if name.len == 0 || name.len > 255 || name == previous { return error('invalid or repeated xattr name') }
			previous = name
		}
		return result
	} $else { return error('native xattr content requires macOS') }
}

fn object(path string, mut budget Budget) !Object {
	$if macos {
		before := os.lstat(path)!
		fd := C.open(path.str, C.O_RDONLY | C.O_NONBLOCK | C.O_NOFOLLOW | C.O_CLOEXEC)
		if fd < 0 { return error('cannot open xattr target') }
		defer { C.close(fd) }
		mut held := C.stat{}
		if C.fstat(fd, &held) != 0 || u64(held.st_dev) != before.dev || u64(held.st_ino) != before.inode
			|| before.get_filetype() !in [.regular, .directory] { return error('xattr target identity changed') }
		listed := names(fd)!
		mut values := map[string]string{}
		for name in listed {
			length := C.fgetxattr(fd, name.str, unsafe { nil }, 0, 0, C.XATTR_SHOWCOMPRESSION)
			if length < 0 || length > max_value || budget.bytes + name.len + length > max_total {
				return error('xattr value unreadable or oversized')
			}
			mut buffer := []u8{len: length + 1}
			if C.fgetxattr(fd, name.str, buffer.data, uint(buffer.len), 0, C.XATTR_SHOWCOMPRESSION) != length {
				return error('xattr value changed')
			}
			values[name.bytes().hex()] = buffer[..length].hex()
			budget.bytes += name.len + length
		}
		if names(fd)! != listed { return error('xattr names changed') }
		after := os.lstat(path)!
		if after.dev != before.dev || after.inode != before.inode || after.get_filetype() != before.get_filetype()
			|| os.real_path(path) != path { return error('xattr target identity changed') }
		return Object{kind: if before.get_filetype() == .regular { 'regular' } else { 'directory' }, values: values}
	} $else { return error('native xattr content requires macOS') }
}

fn pass(ordered []string) !map[string]Object {
	mut budget := Budget{}
	mut result := map[string]Object{}
	for path in ordered { result[path] = object(path, mut budget)! }
	return result
}

// Two complete observations must agree. This detects observed changes; it is
// not an atomic filesystem snapshot and cannot exclude change-and-restore races.
pub fn capture(selected []string) !map[string]Object {
	ordered := paths(selected)!
	first := pass(ordered)!
	if pass(ordered)! != first { return error('xattr content changed between observations') }
	paths(selected)!
	return first
}
