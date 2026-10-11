// SPDX-License-Identifier: GPL-2.0-or-later
module bpffixture

#include <errno.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>

fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32

@[export: 'main']
pub fn run() i32 {
	unsafe {
		errno_ptr := C.__errno_location()
		mut attr := [64]u32{}
		attr[6] = 0x12345678 // BPF_PROG_QUERY's output count must stay untouched.
		for cmd in [5, 8, 9, 16, 0x7fffffff]! {
			*errno_ptr = 0
			result := C.syscall(isize(C.SYS_bpf), isize(cmd), &attr[0], isize(sizeof(attr)))
			if result != -1 || *C.__errno_location() != C.ENOSYS || attr[6] != 0x12345678 {
				C.printf(c'LINUX BPF FAIL: cmd=%d result=%ld errno=%d\n', cmd, result, *C.__errno_location())
				return 1
			}
		}
		*errno_ptr = 0
		if C.syscall(isize(C.SYS_bpf), isize(16), voidptr(1), isize(64)) != -1
			|| *C.__errno_location() != C.ENOSYS {
			C.puts(c'LINUX BPF FAIL: absent implementation touched userspace')
			return 1
		}
		C.puts(c'LINUX BPF: PASS')
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
