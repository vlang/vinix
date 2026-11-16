// SPDX-License-Identifier: GPL-2.0-or-later
// Symlink-node observations deliberately do not dereference the final component.
module winelinkxattr

import os
import tests.packages.winexattr

$if macos {
	#include <sys/xattr.h>
	#include <sys/stat.h>
	#include <fcntl.h>
	fn C.flistxattr(int, &char, uint, int) int
	fn C.fgetxattr(int, &char, voidptr, uint, u32, int) int
}

pub struct Link {
pub:
	target_hex string
	values map[string]string
}

struct Budget {
mut:
	bytes int
}

pub fn canonical_node(path string) !string {
	if !os.is_abs_path(path) || path.len > 4096 || path.contains('\x00') { return error('absolute bounded link path required') }
	parent := os.real_path(os.dir(path))
	if !os.is_abs_path(parent) || !os.is_dir(parent) { return error('canonical link parent required') }
	return parent.trim_right('/') + '/' + os.file_name(path)
}

fn paths(selected []string) ![]string {
	if selected.len == 0 || selected.len > winexattr.max_targets { return error('bounded nonempty link targets required') }
	mut ordered := selected.clone(); ordered.sort()
	mut previous := ''
	for path in ordered {
		if canonical_node(path)! != path || path == previous { return error('canonical-parent unique link targets required') }
		if os.lstat(path)!.get_filetype() != .symbolic_link { return error('symlink-node target required') }
		previous = path
	}
	return ordered
}

fn names(fd int) ![]string {
	$if macos {
		length := C.flistxattr(fd, unsafe { nil }, 0, C.XATTR_SHOWCOMPRESSION)
		if length < 0 || length > 65536 { return error('link xattr name list unreadable or oversized') }
		mut buffer := []u8{len: length + 1}
		if C.flistxattr(fd, &char(buffer.data), uint(buffer.len), C.XATTR_SHOWCOMPRESSION) != length { return error('link xattr name list changed') }
		if length == 0 { return []string{} }
		if buffer[length - 1] != 0 { return error('unterminated link xattr list') }
		mut result := buffer[..length - 1].bytestr().split('\x00'); result.sort()
		if result.len > winexattr.max_names { return error('too many link xattr names') }
		mut previous := ''
		for name in result {
			if name.len == 0 || name.len > 255 || name == previous { return error('invalid or repeated link xattr name') }
			previous = name
		}
		return result
	} $else { return error('native link xattrs require macOS') }
}

fn body(path string) !string {
	$if macos {
		mut buffer := [4097]u8{}
		length := C.readlink(path.str, &char(&buffer[0]), 4097)
		if length < 1 || length > 4096 { return error('bounded nonempty link body required') }
		return buffer[..length].bytestr()
	} $else { return error('native link xattrs require macOS') }
}

fn link(path string, mut budget Budget) !Link {
	$if macos {
		before := os.lstat(path)!
		if before.get_filetype() != .symbolic_link { return error('symlink-node target required') }
		// O_SYMLINK opens the link vnode. Adding O_NOFOLLOW causes ELOOP on
		// this profile; fstat plus final lstat bind the descriptor to the node.
		fd := C.open(path.str, C.O_RDONLY | C.O_NONBLOCK | C.O_SYMLINK | C.O_CLOEXEC)
		if fd < 0 { return error('cannot open link vnode') }
		defer { C.close(fd) }
		mut held := C.stat{}
		if C.fstat(fd, &held) != 0 || u64(held.st_dev) != before.dev || u64(held.st_ino) != before.inode
			|| (u32(held.st_mode) & 0o170000) != 0o120000 { return error('link vnode identity changed') }
		target := body(path)!
		if u64(target.len) != before.size { return error('link body size changed') }
		listed := names(fd)!
		mut values := map[string]string{}
		for name in listed {
			length := C.fgetxattr(fd, name.str, unsafe { nil }, 0, 0, C.XATTR_SHOWCOMPRESSION)
			if length < 0 || length > winexattr.max_value || budget.bytes + name.len + length > winexattr.max_total {
				return error('link xattr value unreadable or oversized')
			}
			mut buffer := []u8{len: length + 1}
			if C.fgetxattr(fd, name.str, buffer.data, uint(buffer.len), 0, C.XATTR_SHOWCOMPRESSION) != length { return error('link xattr value changed') }
			values[name.bytes().hex()] = buffer[..length].hex()
			budget.bytes += name.len + length
		}
		if names(fd)! != listed || body(path)! != target { return error('link observations changed') }
		after := os.lstat(path)!
		if after.dev != before.dev || after.inode != before.inode || after.get_filetype() != .symbolic_link
			|| canonical_node(path)! != path { return error('link vnode identity changed') }
		return Link{target_hex: target.bytes().hex(), values: values}
	} $else { return error('native link xattrs require macOS') }
}

fn pass(ordered []string) !map[string]Link {
	mut budget := Budget{}
	mut result := map[string]Link{}
	for path in ordered { result[path] = link(path, mut budget)! }
	return result
}

pub fn capture(selected []string) !map[string]Link {
	ordered := paths(selected)!
	first := pass(ordered)!
	if pass(ordered)! != first { return error('link xattr content changed between observations') }
	paths(selected)!
	return first
}
