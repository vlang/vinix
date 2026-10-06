// SPDX-License-Identifier: BSD-2-Clause
// Native syscall argument capture and real descriptors; guest calls actual syscall.
@[has_globals; translated]
module intoracle

#include <int-oracle-native-abi.h>
@[typedef]
struct C.vqt_const_char_p {}

@[c_extern]
__global C.errno i32

fn C.assert(bool)
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.strcmp(&char, &char) i32
fn C.syscall(isize, ...) isize
fn C.vqt_host_syscall(isize, ...) isize
fn C.openat(i32, &char, i32, ...) i32
fn C.close(i32) i32
fn C.pipe(&i32) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) i32
fn C.WEXITSTATUS(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.fflush(voidptr) i32
fn C._exit(i32)
fn C.puts(&char) i32
fn C.open(&char, i32, ...) i32
fn C.dup2(i32, i32) i32
fn C.pause() i32
fn C.original_test_syscall_int_truncation() i32
fn C.test_syscall_int_truncation() i32

__global (
	int_fault    i32
	int_syscalls i32
	int_closes   i32
	int_capture  u64
	int_number   isize
	int_probe    bool
)

@[export:'vqt_host_syscall_body']
pub fn syscall_input(number isize, dir u64, native_path C.vqt_const_char_p, flags i32, mode i32) isize {
	unsafe {
		mut path := &char(nil)
		C.memcpy(&path, &native_path, sizeof(C.vqt_const_char_p))
		C.assert(number == isize(C.SYS_openat) && dir == u64(0x00000000ffffff9c) && C.strcmp(path, c'.') == 0)
		if int_probe {
			C.assert(flags == i32(0x12345678) && mode == i32(0x5a5a5a5a))
			return 37
		}
		C.assert(flags == C.O_RDONLY && mode == 0)
		int_syscalls++
		int_capture = dir
		int_number = number
		if int_fault == 1 {
			C.errno = C.EIO
			return -1
		}
		$if int_guest ? {
			return C.syscall(number, dir, path, flags, mode)
		} $else {
			return isize(C.openat(C.AT_FDCWD, path, flags, mode))
		}
	}
}

@[export:'vqt_host_close']
pub fn close_input(fd i32) i32 {
	unsafe {
		int_closes++
		if int_fault == 2 {
			C.errno = C.EIO
			return -1
		}
		return C.close(fd)
	}
}

fn attempt(original bool, fault i32) [6]u64 {
	unsafe {
		mut endpoints := [2]i32{}
		C.assert(C.pipe(&endpoints[0]) == 0)
		C.fflush(nil)
		child := C.fork()
		C.assert(child >= 0)
		if child == 0 {
			C.close(endpoints[0])
			int_fault = fault
			int_syscalls = 0
			int_closes = 0
			int_capture = 0
			int_number = 0
			C.errno = C.E2BIG
			result := if original {
				C.original_test_syscall_int_truncation()
			} else {
				C.test_syscall_int_truncation()
			}
			mut report := [u64(result), u64(u32(C.errno)), u64(int_syscalls), u64(int_closes),
				int_capture, u64(int_number)]!
			C.assert(C.write(endpoints[1], &report[0], sizeof(report)) == isize(sizeof(report)))
			C.fflush(nil)
			C._exit(0)
		}
		C.close(endpoints[1])
		mut report := [6]u64{}
		C.assert(C.read(endpoints[0], &report[0], sizeof(report)) == isize(sizeof(report)))
		C.assert(C.close(endpoints[0]) == 0)
		mut status := i32(-1)
		C.assert(C.waitpid(child, &status, 0) == child && C.WIFEXITED(status) != 0 && C.WEXITSTATUS(status) == 0)
		return report
	}
}

@[export:'main']
pub fn main_entry() i32 {
	unsafe {
		$if int_guest ? {
			mut console := C.open(c'/dev/com1', C.O_WRONLY | C.O_NOCTTY)
			if console < 0 { console = C.open(c'/dev/console', C.O_WRONLY | C.O_NOCTTY) }
			if console >= 0 {
				C.dup2(console, 1)
				C.dup2(console, 2)
				C.close(console)
			}
		}
		int_probe = true
		C.assert(C.vqt_host_syscall(isize(C.SYS_openat), u64(0x00000000ffffff9c), c'.', i32(0x12345678), i32(0x5a5a5a5a)) == 37)
		int_probe = false
		for fault := i32(0); fault <= 2; fault++ {
			original := attempt(true, fault)
			ported := attempt(false, fault)
			for field in 0 .. 6 { C.assert(original[field] == ported[field]) }
			C.assert(ported[0] == if fault == 0 { u64(0) } else { u64(1) })
			C.assert(ported[2] == 1 && ported[4] == u64(0x00000000ffffff9c) && ported[5] == u64(C.SYS_openat))
		}
		C.puts(c'QEMU CORE INT DIFFERENTIAL PASS: three native syscall argument/failure cases')
		C.fflush(nil)
		$if int_guest ? {
			for { C.pause() }
		}
		return 0
	}
}
