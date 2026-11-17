// SPDX-License-Identifier: GPL-2.0-or-later
// Immediate native entry names only; child objects are never opened or followed.
module winedircontent

import os

pub const max_targets = 2048
pub const max_entries = 4096
pub const max_total = 16384
pub const max_name_bytes = 1048576

$if macos {
	#include <dirent.h>
	#include <fcntl.h>
	#include <sys/stat.h>
	fn C.fdopendir(int) voidptr
}

struct Budget {
mut:
	entries int
	bytes int
}

pub fn paths(selected []string) ![]string {
	if selected.len == 0 || selected.len > max_targets { return error('bounded nonempty directory targets required') }
	mut ordered := selected.clone(); ordered.sort()
	mut previous := ''
	for path in ordered {
		if !os.is_abs_path(path) || path.len > 4096 || path.contains('\x00') || path == previous
			|| os.real_path(path) != path { return error('canonical unique directory targets required') }
		if os.lstat(path)!.get_filetype() != .directory { return error('directory target required') }
		previous = path
	}
	return ordered
}

fn entries(path string, mut budget Budget) ![]string {
	$if macos {
		before := os.lstat(path)!
		if before.get_filetype() != .directory { return error('directory target required') }
		fd := C.open(path.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NONBLOCK | C.O_NOFOLLOW | C.O_CLOEXEC)
		if fd < 0 { return error('cannot open directory target') }
		mut held := C.stat{}
		if C.fstat(fd, &held) != 0 || u64(held.st_dev) != before.dev || u64(held.st_ino) != before.inode
			|| (u32(held.st_mode) & 0o170000) != 0o040000 {
			C.close(fd); return error('directory target identity changed')
		}
		stream := C.fdopendir(fd)
		if stream == unsafe { nil } { C.close(fd); return error('cannot enumerate directory target') }
		defer { C.closedir(stream) }
		mut names := []string{}
		for {
			C.errno = 0
			entry := C.readdir(stream)
			if entry == unsafe { nil } {
				if C.errno != 0 { return error('directory enumeration failed') }
				break
			}
			length := int(entry.d_namlen)
			if length < 1 || length > 255 { return error('invalid native directory name length') }
			name := unsafe { (&char(&entry.d_name[0])).vstring_with_len(length).clone() }
			if name in ['.', '..'] { continue }
			if name.contains('\x00') || name.contains('/') { return error('invalid native directory name') }
			if names.len >= max_entries || budget.entries >= max_total || budget.bytes + length > max_name_bytes {
				return error('directory entry inventory exceeds bound')
			}
			names << name.bytes().hex()
			budget.entries++; budget.bytes += length
		}
		names.sort()
		for index in 1 .. names.len { if names[index] == names[index - 1] { return error('repeated native directory name') } }
		after := os.lstat(path)!
		if after.dev != before.dev || after.inode != before.inode || after.get_filetype() != .directory
			|| os.real_path(path) != path { return error('directory target identity changed') }
		return names
	} $else { return error('native directory inventory requires macOS') }
}

fn pass(ordered []string) !map[string][]string {
	mut budget := Budget{}
	mut result := map[string][]string{}
	for path in ordered { result[path] = entries(path, mut budget)! }
	return result
}

// Matching observations are quiescent evidence, not an atomic filesystem snapshot.
pub fn capture(selected []string) !map[string][]string {
	ordered := paths(selected)!
	first := pass(ordered)!
	if pass(ordered)! != first { return error('directory names changed between observations') }
	paths(selected)!
	return first
}
