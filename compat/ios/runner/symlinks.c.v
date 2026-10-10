// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <unistd.h>
#include <fcntl.h>

fn C.ios_readlink(&char, voidptr, usize) isize
fn C.ios_readlinkat(i32, &char, voidptr, usize) isize
fn C.symlink(&char, &char) i32
fn C.realpath(&char, &char) &char

fn readlink_native(path &char, buffer voidptr, size usize) isize {
	result := C.ios_readlink(path, buffer, size)
	$if linux {
		if result >= 0 || unsafe { *C.ios_errno_address() } != C.ENOENT { return result }
		// Native lookup in this kernel can lose an absolute parent symlink.
		// The native libc's realpath resolves components through readlink.
		// Resolve only the parent and retry through its descriptor: the final
		// link is still read, never followed. O_PATH needs no read permission.
		mut parent := [4096]u8{}
		mut resolved := [4096]u8{}
		mut slash := -1
		mut length := 0
		unsafe {
			for length < parent.len - 1 && path[length] != 0 {
				parent[length] = u8(path[length])
				if path[length] == char(47) { slash = length }
				length++
			}
			if slash < 0 || path[length] != 0 { return result }
			parent[if slash == 0 { 1 } else { slash }] = 0
			if C.realpath(&char(&parent[0]), &char(&resolved[0])) == nil { return -1 }
			fd := C.open(&char(&resolved[0]), C.O_PATH | C.O_DIRECTORY | C.O_CLOEXEC, 0)
			if fd < 0 { return -1 }
			retried := C.ios_readlinkat(i32(fd), &path[slash + 1], buffer, size)
			native_error := *C.ios_errno_address()
			C.close(fd)
			darwin_set_errno(native_error)
			return retried
		}
	}
	return result
}

fn darwin_readlink(path &char, buffer voidptr, size usize) isize {
	// Darwin rejects counts greater than INT_MAX before looking up the path.
	if size > 0x7fffffff { darwin_set_errno(22); return -1 }
	if path == unsafe { nil } { darwin_set_errno(14); return -1 }
	previous := unsafe { *C.ios_errno_address() }
	// Darwin permits zero bytes but still checks the path and link type.
	// Linux rejects a zero count, so validate with one byte of stack storage.
	mut scratch := [1]u8{}
	result := if size == 0 {
		readlink_native(path, unsafe { &scratch[0] }, 1)
	} else {
		readlink_native(path, buffer, size)
	}
	if result < 0 {
		darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() }))
		return result
	}
	darwin_set_errno(previous)
	return if size == 0 { isize(0) } else { result }
}

fn darwin_symlink(target &char, path &char) i32 {
	return i32(darwin_file_result(C.symlink(target, path)))
}
