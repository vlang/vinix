// SPDX-License-Identifier: GPL-2.0-or-later
// Independent large-I/O lifetime regression. Original check lines are retained.
@[has_globals]
module bigio

#include <big-io-native-abi.h>

@[typedef]
struct C.FILE {}
struct C.big_io_pages { value u64 }
@[c_extern]
__global C.stdout &C.FILE
__global big_io_payload [65536]u8
__global big_io_slabinfo [65536]char

fn C.BIG_IO_ERRNO() &i32
fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.sleep(u32) u32
fn C.pause() i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.strstr(&char, &char) &char
fn C.sscanf(&char, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.fflush(&C.FILE) i32

fn check(condition bool, line i32) bool {
	if !condition { unsafe { C.printf(c'BIG IO FAIL: line=%d errno=%d\n', line, *C.BIG_IO_ERRNO()) } }
	return condition
}

fn large_pages(pages &C.big_io_pages) i32 {
	unsafe {
		fd := C.open(c'/proc/slabinfo', C.O_RDONLY)
		if !check(fd >= 0, 17) { return 1 }
		n := C.read(fd, &big_io_slabinfo[0], sizeof(big_io_slabinfo) - 1)
		if !check(n > 0 && C.close(fd) == 0, 19) { return 1 }
		big_io_slabinfo[n] = 0
		large := C.strstr(&big_io_slabinfo[0], c'large - - ')
		if !check(large != nil && C.sscanf(large, c'large - - %llu', &pages.value) == 1, 22) { return 1 }
	}
	return 0
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		zero := C.open(c'/dev/zero', C.O_RDONLY)
		sink := C.open(c'/dev/null', C.O_WRONLY)
		if !check(zero >= 0 && sink >= 0, 30) { return 1 }
		if !check(C.read(zero, &big_io_payload[0], sizeof(big_io_payload)) == isize(sizeof(big_io_payload)), 32) { return 1 }
		if !check(C.write(sink, &big_io_payload[0], sizeof(big_io_payload)) == isize(sizeof(big_io_payload)), 33) { return 1 }
		mut before := C.big_io_pages{}
		mut after := C.big_io_pages{}
		for warm := i32(0); warm < 3; warm++ {
			if !check(large_pages(&before) == 0, 36) { return 1 }
		}
		if !check(C.sleep(7) == 0, 37) { return 1 }
		if !check(large_pages(&before) == 0, 38) { return 1 }
		for round := i32(0); round < 300; round++ {
			C.memset(&big_io_payload[0], 0x5a, sizeof(big_io_payload))
			if !check(C.read(zero, &big_io_payload[0], sizeof(big_io_payload)) == isize(sizeof(big_io_payload)), 41) { return 1 }
			for i := u32(0); i < sizeof(big_io_payload); i++ {
				if !check(big_io_payload[i] == 0, 42) { return 1 }
			}
			if !check(C.write(sink, &big_io_payload[0], sizeof(big_io_payload)) == isize(sizeof(big_io_payload)), 43) { return 1 }
			errno_address := C.BIG_IO_ERRNO()
			*errno_address = 0
			if !check(C.read(zero, voidptr(usize(1)), sizeof(big_io_payload)) == -1 && *C.BIG_IO_ERRNO() == C.EFAULT, 45) { return 1 }
			*errno_address = 0
			if !check(C.write(sink, voidptr(usize(1)), sizeof(big_io_payload)) == -1 && *C.BIG_IO_ERRNO() == C.EFAULT, 47) { return 1 }
		}
		if !check(large_pages(&after) == 0, 49) { return 1 }
		C.printf(c'BIG IO MEASURE: before=%llu after=%llu\n', before.value, after.value)
		if !check(after.value == before.value, 51) { return 1 }
		if !check(C.close(zero) == 0 && C.close(sink) == 0, 52) { return 1 }
		C.printf(c'BIG IO PASS: 300 large reads writes and failed read/write-copy frees; pages=%llu\n', after.value)
		C.fflush(C.stdout)
		for { C.pause() }
	}
	return 0
}
