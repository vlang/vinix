// SPDX-License-Identifier: GPL-2.0-or-later
// Independent native boundary checks; also link against the frozen C preload.
@[has_globals]
module robustfixture

#include <assert.h>
#include <stdio.h>
#include <string.h>
fn C.assert(bool)
fn C.puts(&char) i32
fn C.strcmp(&char, &char) i32
@[c_extern]
fn C.fixture_call_syscall(isize, isize, isize, isize, isize, isize, isize) isize
@[c_extern]
fn C.robust_mock_syscall()
@[c_extern]
fn C.robust_subject_mmap(voidptr, usize, i32, i32, i32, isize) voidptr
@[c_extern]
fn C.robust_subject_mmap64(voidptr, usize, i32, i32, i32, i64) voidptr
@[c_extern]
fn C.robust_subject_munmap(voidptr, usize) i32
@[c_extern]
fn C.robust_subject_uname(voidptr) i32
@[c_extern]
fn C.robust_fixture_mock_mmap(voidptr, usize, i32, i32, i32, isize) voidptr
@[c_extern]
fn C.robust_fixture_mock_mmap64(voidptr, usize, i32, i32, i32, i64) voidptr
@[c_extern]
fn C.robust_fixture_mock_munmap(voidptr, usize) i32
@[c_extern]
fn C.robust_fixture_mock_uname(voidptr) i32

__global thread_storage [4096]u8
__global arguments [7]isize
__global observed_address voidptr
__global observed_length usize
__global observed_offset i64
__global observed_protection i32
__global observed_flags i32
__global observed_fd i32
__global mapping_result voidptr
__global unmap_result i32
__global uname_result i32
__global syscalls u32
__global cases u32
__global concurrent_mode bool

@[export: 'robust_fixture_pthread_self']
pub fn pthread_self() voidptr {
	return unsafe { &thread_storage[0] }
}

@[export: 'robust_fixture_dlsym']
pub fn lookup(handle voidptr, name &char) voidptr {
	C.assert(usize(handle) == usize(-1))
	if C.strcmp(name, c'syscall') == 0 { return voidptr(C.robust_mock_syscall) }
	if C.strcmp(name, c'mmap') == 0 { return voidptr(C.robust_fixture_mock_mmap) }
	if C.strcmp(name, c'mmap64') == 0 { return voidptr(C.robust_fixture_mock_mmap64) }
	if C.strcmp(name, c'munmap') == 0 { return voidptr(C.robust_fixture_mock_munmap) }
	C.assert(C.strcmp(name, c'uname') == 0)
	return voidptr(C.robust_fixture_mock_uname)
}

@[export: 'robust_mock_dispatch']
pub fn mock_syscall(number isize, a1 isize, a2 isize, a3 isize, a4 isize, a5 isize, a6 isize) isize {
	arguments[0] = number
	arguments[1] = a1
	arguments[2] = a2
	arguments[3] = a3
	arguments[4] = a4
	arguments[5] = a5
	arguments[6] = a6
	syscalls++
	return -73
}

@[export: 'robust_fixture_mock_mmap']
pub fn mock_mmap(address voidptr, length usize, protection i32, flags i32, fd i32, offset isize) voidptr {
	if concurrent_mode {
		C.assert(address == nil && length == 16384 && protection == 2 && flags == 1 && fd >= 1 && fd <= 16 && offset == 0)
		return voidptr(0x100000 + usize(fd) * 0x10000)
	}
	observed_address = address
	observed_length = length
	observed_protection = protection
	observed_flags = flags
	observed_fd = fd
	observed_offset = i64(offset)
	return mapping_result
}

@[export: 'robust_fixture_mock_mmap64']
pub fn mock_mmap64(address voidptr, length usize, protection i32, flags i32, fd i32, offset i64) voidptr {
	observed_offset = offset
	observed_address = address
	observed_length = length
	observed_protection = protection
	observed_flags = flags
	observed_fd = fd
	return mapping_result
}

@[export: 'robust_fixture_mock_munmap']
pub fn mock_munmap(address voidptr, length usize) i32 {
	if concurrent_mode {
		C.assert(usize(address) >= 0x110000 && usize(address) <= 0x200000 && length == 16384)
		return 0
	}
	observed_address = address
	observed_length = length
	return unmap_result
}

@[export: 'robust_fixture_mock_uname']
pub fn mock_uname(buffer voidptr) i32 {
	if buffer != nil {
		unsafe { for i := 0; i < 390; i++ { (&u8(buffer))[i] = u8(`?`) } }
	}
	return uname_result
}

fn syscall_tests() {
	unsafe {
		number := isize($if steam_i386 ? { 312 } $else { 274 })
		offset := usize($if steam_i386 ? { 0x6c } $else { 0x2e0 })
		size := usize($if steam_i386 ? { 12 } $else { 24 })
		mut head := voidptr(nil)
		mut length := usize(0)
		C.assert(C.fixture_call_syscall(number, 0, isize(&head), isize(&length), 4, 5, 6) == 0)
		C.assert(usize(head) == usize(&thread_storage[0]) + offset && length == size && syscalls == 0)
		cases++
		for mode := 0; mode < 4; mode++ {
			selected := if mode == 0 { number - 1 } else { number }
			a1 := isize(if mode == 1 { 12 } else { 0 })
			a2 := if mode == 2 { isize(0) } else { isize(&head) }
			a3 := if mode == 3 { isize(0) } else { isize(&length) }
			C.assert(C.fixture_call_syscall(selected, a1, a2, a3, -4, 5, -6) == -73)
			C.assert(arguments[0] == selected && arguments[1] == a1 && arguments[2] == a2 && arguments[3] == a3)
			C.assert(arguments[4] == -4 && arguments[5] == 5 && arguments[6] == -6)
			cases++
		}
		C.assert(syscalls == 4)
	}
}

fn mapping_tests() {
	unsafe {
		mapping_result = voidptr(0x100000)
		unmap_result = -17
		for mode := 0; mode < 8; mode++ {
			address := if mode == 0 { voidptr(0x200000) } else { voidptr(nil) }
			fd := i32(if mode == 1 { -1 } else { 9 })
			flags := i32(if mode == 2 { 2 } else if mode == 3 { 0x11 } else { 1 })
			protection := i32(if mode == 4 { 1 } else { 3 })
			length := usize(if mode == 5 { u64(0xffffc001) } else if mode == 6 { u64(16384) } else { u64(4097) })
			padded := if mode >= 7 { usize(16384) } else if mode == 3 { usize(16384) } else { length }
			// The original flags test checks MAP_TYPE, including MAP_FIXED.
			C.assert(C.robust_subject_mmap(address, length, protection, flags, fd, -4096) == mapping_result)
			C.assert(observed_length == padded && usize(observed_address) == usize(address) && observed_offset == -4096)
			C.assert(observed_fd == fd && observed_flags == flags && observed_protection == protection)
			C.assert(C.robust_subject_munmap(mapping_result, length) == -17 && observed_length == padded)
			cases++
		}
		mapping_result = voidptr(-1)
		C.assert(C.robust_subject_mmap(nil, 1, 2, 1, 9, 0) == voidptr(-1) && observed_length == 16384)
		C.robust_subject_munmap(voidptr(-1), 1)
		C.assert(observed_length == 1)
		cases++
		mapping_result = voidptr(0x100000)
		C.assert(C.robust_subject_mmap64(nil, 4097, 3, 1, 9, i64(-0x100001000)) == mapping_result)
		C.assert(observed_offset == i64(-0x100001000) && observed_length == 16384)
		C.robust_subject_munmap(mapping_result, 16384)
		C.assert(observed_length == 16384)
		C.robust_subject_munmap(mapping_result, 4097)
		C.assert(observed_length == 4097)
		cases++
		// Replacement, table saturation, first-free reuse and failed-unmap retirement.
		for i := 0; i < 513; i++ {
			mapping_result = voidptr(0x100000 + usize(i) * 0x10000)
			C.robust_subject_mmap(nil, 1, 2, 1, 9, 0)
		}
		C.robust_subject_munmap(mapping_result, 1)
		C.assert(observed_length == 1)
		for i := 0; i < 512; i++ {
			C.robust_subject_munmap(voidptr(0x100000 + usize(i) * 0x10000), 1)
			C.assert(observed_length == 16384)
		}
		mapping_result = voidptr(0x100000)
		C.robust_subject_mmap(nil, 1, 2, 1, 9, 0)
		C.robust_subject_mmap(nil, 4097, 2, 1, 9, 0)
		C.robust_subject_munmap(mapping_result, 1)
		C.assert(observed_length == 1)
		C.robust_subject_munmap(mapping_result, 4097)
		C.assert(observed_length == 16384)
		cases++
		mut buffer := [390]u8{}
		uname_result = 0
		C.assert(C.robust_subject_uname(&buffer[0]) == 0)
		C.assert(C.strcmp(&char(&buffer[260]), c'x86_64') == 0 && buffer[259] == `?` && buffer[267] == `?`)
		uname_result = -9
		C.assert(C.robust_subject_uname(&buffer[0]) == -9 && buffer[260] == `?`)
		C.assert(C.robust_subject_uname(nil) == -9)
		uname_result = 0
		C.assert(C.robust_subject_uname(nil) == 0)
		cases++
	}
}

@[export: 'main']
pub fn main() i32 {
	syscall_tests()
	$if steam_i386 ? { mapping_tests() }
	C.assert(cases == u32($if steam_i386 ? { 17 } $else { 5 }))
	$if steam_i386 ? {
		$if !steam_robust_bare ? { concurrency_tests() }
	}
	C.puts(c'STEAM ROBUST ABI FIXTURE: PASS')
	return 0
}
