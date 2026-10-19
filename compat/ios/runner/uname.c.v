// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <sys/utsname.h>

fn C.uname(&C.utsname) i32

$if linux {
	fn C.process_vm_writev(i32, &C.iovec, usize, &C.iovec, usize, usize) isize
}

fn darwin_uname(output voidptr) i32 {
	$if macos {
		return C.uname(&C.utsname(output))
	}
	$if linux {
		previous := unsafe { *C.ios_errno_address() }
		mut native := C.utsname{}
		if C.uname(unsafe { &native }) != 0 {
			darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() }))
			return -1
		}
		// Linux has six 65-byte fields; Darwin has five 256-byte fields.
		// Copy only the strings and their terminators, preserving field tails.
		fields := [unsafe { &native.sysname[0] }, unsafe { &native.nodename[0] },
			unsafe { &native.release[0] }, unsafe { &native.version[0] },
			unsafe { &native.machine[0] }]!
		for index, field in fields {
			length := C.strnlen(field, 65)
			if length == 65 { darwin_set_errno(5); return -1 }
			offset := usize(index) * 256
			if output == unsafe { nil } || usize(output) > ~usize(0) - offset {
				darwin_set_errno(14)
				return -1
			}
			local := C.iovec{voidptr(field), length + 1}
			remote := C.iovec{voidptr(usize(output) + offset), length + 1}
			// Kernel copyout reports EFAULT (and permits a partial field write)
			// without dereferencing an application's invalid destination here.
			written := C.process_vm_writev(C.getpid(), unsafe { &local }, 1,
				unsafe { &remote }, 1, 0)
			if written != isize(length + 1) {
				darwin_set_errno(if written < 0 {
					darwin_native_error(unsafe { *C.ios_errno_address() })
				} else { 14 })
				return -1
			}
		}
		darwin_set_errno(previous)
		return 0
	}
	return -1
}
