// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <sys/file.h>
fn C.flock(i32, i32) i32

// Darwin ignores unknown bits and selects UN before EX before SH. An operation
// with no lock kind reports EBADF, after descriptor and object-kind lookup.
// Linux's flock requires exactly one kind, so translate before calling it.
fn darwin_flock(fd i32, operation i32) i32 {
	previous := unsafe { *C.ios_errno_address() }
	mut native := operation
	$if linux {
		mut fields := [20]u64{}
		if C.ios_stat_info(unsafe { nil }, fd, 2, unsafe { &fields[0] }) != 0 {
			darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() }))
			return -1
		}
		kind := fields[1] & 0xf000
		// Pipes and sockets report Darwin ENOTSUP even for an invalid operation.
		// Device locks are outside this backend's regular-file/directory subset.
		if kind != 0x8000 && kind != 0x4000 {
			darwin_set_errno(45)
			return -1
		}
		native = if operation & 8 != 0 { i32(C.LOCK_UN) }
			else if operation & 2 != 0 { i32(C.LOCK_EX) }
			else if operation & 1 != 0 { i32(C.LOCK_SH) }
			else { darwin_set_errno(9); return -1 }
		if operation & 4 != 0 { native |= C.LOCK_NB }
	}
	// Keep the kernel's open-description ownership, blocking waits, dup/fork
	// lifetime and last-close release. Linux conversion and POSIX-lock conflict
	// semantics still differ from Darwin; this adapter does not emulate them.
	result := C.flock(fd, native)
	darwin_set_errno(if result < 0 { darwin_native_error(unsafe { *C.ios_errno_address() }) } else { previous })
	return result
}
