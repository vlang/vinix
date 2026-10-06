// SPDX-License-Identifier: BSD-2-Clause
// Independent C-int truncation fixture, original lines2535-2544.
@[translated]
module intfixture

#include <intfixture_v_contract.h>

@[c_extern]
__global C.errno i32

fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.syscall(isize, ...) isize
fn C.close(i32) i32

fn check(ok bool, line i32, expression &char) bool {
	if !ok {
		unsafe { C.printf(c'QEMU CORE FAIL line %d: %s (errno=%d)\n', line, expression, C.errno) }
	}
	return ok
}

@[export:'test_syscall_int_truncation']
pub fn syscall_int_truncation() i32 {
	unsafe {
		descriptor := C.syscall(isize(C.SYS_openat), u64(0x00000000ffffff9c), c'.', i32(C.O_RDONLY), i32(0))
		if !check(descriptor >= 0, 2539, c'descriptor >= 0') { return 1 }
		if !check(C.close(i32(descriptor)) == 0, 2540, c'close((int)descriptor) == 0') { return 1 }
		C.puts(c'QEMU CORE PASS: syscall C-int truncation')
		return 0
	}
}
