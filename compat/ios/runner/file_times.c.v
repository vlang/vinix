// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <utime.h>

struct C.utimbuf {
	actime  i64
	modtime i64
}

fn C.utime(&char, &C.utimbuf) i32

struct DarwinFileTimes {
	access       i64
	modification i64
}

fn utime_native(path &char, times &C.utimbuf) i32 {
	result := C.utime(path, times)
	$if linux {
		if result < 0 && unsafe { *C.ios_errno_address() } == C.ENOENT {
			// Like readlink_native, use libc's component lookup when the
			// kernel loses an absolute symlink. It also identifies loops as
			// ELOOP rather than treating the target as a missing file.
			mut resolved := [4096]u8{}
			if C.realpath(path, unsafe { &char(&resolved[0]) }) == unsafe { nil } { return -1 }
			return C.utime(unsafe { &char(&resolved[0]) }, times)
		}
	}
	return result
}

fn darwin_utime(path &char, times &DarwinFileTimes) i32 {
	previous := unsafe { *C.ios_errno_address() }
	// A null timestamp pointer asks the native filesystem to set both times
	// to now. Explicit Darwin timestamps are two signed 64-bit seconds;
	// use header-backed native storage without changing the caller's buffer.
	if times == unsafe { nil } {
		return darwin_ioctl_result(utime_native(path, unsafe { nil }), previous)
	}
	mut native := C.utimbuf{ actime: times.access, modtime: times.modification }
	return darwin_ioctl_result(utime_native(path, unsafe { &native }), previous)
}
