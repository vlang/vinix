// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <sys/resource.h>

fn C.setrlimit(i32, voidptr) i32
fn C.getrlimit(i32, voidptr) i32

const darwin_rlim_infinity = u64(0x7fffffffffffffff)

fn rlimit_native_resource(resource i32) i32 {
	which := resource & ~i32(0x1000) // Darwin's strict POSIX flag.
	if which < 0 || which > 8 { return -1 }
	$if macos { return resource }
	return [i32(C.RLIMIT_CPU), i32(C.RLIMIT_FSIZE), i32(C.RLIMIT_DATA),
		i32(C.RLIMIT_STACK), i32(C.RLIMIT_CORE), i32(C.RLIMIT_AS),
		i32(C.RLIMIT_MEMLOCK), i32(C.RLIMIT_NPROC), i32(C.RLIMIT_NOFILE)]![which]
}

fn darwin_setrlimit(resource i32, input voidptr) i32 {
	previous := unsafe { *C.ios_errno_address() }
	$if macos { return darwin_process_result(C.setrlimit(resource, input), previous) }
	// Darwin copies the input before validating the resource number.
	if input == unsafe { nil } { darwin_set_errno(14); return -1 }
	native := rlimit_native_resource(resource)
	if native < 0 { darwin_set_errno(22); return -1 }
	mut limits := [2]u64{}
	// The guest record may be unaligned. Keep conversion off the caller's
	// bytes and leave the native kernel responsible for permissions/enforcement.
	unsafe { C.memcpy(voidptr(&limits[0]), input, 16) }
	if limits[0] > limits[1] { darwin_set_errno(22); return -1 }
	// Values above Darwin's canonical infinity are outside this subset:
	// UINT64_MAX would collide with Linux's infinity sentinel.
	if limits[1] > darwin_rlim_infinity { darwin_set_errno(45); return -1 }
	for index in 0 .. 2 { if limits[index] == darwin_rlim_infinity { limits[index] = u64(C.RLIM_INFINITY) } }
	return darwin_process_result(C.setrlimit(native, unsafe { voidptr(&limits[0]) }), previous)
}
