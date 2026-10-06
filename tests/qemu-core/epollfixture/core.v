// SPDX-License-Identifier: BSD-2-Clause
// Original independent epoll stride, data and count checks, lines2501-2530.
@[translated]
module epollfixture

#include <epollfixture_v_contract.h>
@[typedef]
struct C.epoll_data_t {
mut:
	u64 u64
}

struct C.epoll_event {
mut:
	events u32
	data   C.epoll_data_t
}

@[c_extern]
__global C.errno i32

fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.pipe(&i32) i32
fn C.epoll_create1(i32) i32
fn C.epoll_ctl(i32, i32, i32, &C.epoll_event) i32
fn C.epoll_wait(i32, &C.epoll_event, i32, i32) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32

fn check(ok bool, line i32, expression &char) bool {
	if !ok {
		unsafe { C.printf(c'QEMU CORE FAIL line %d: %s (errno=%d)\n', line, expression, C.errno) }
	}
	return ok
}

@[export:'test_epoll_abi_and_count']
pub fn epoll_abi_and_count() i32 {
	unsafe {
		mut pair := [2]i32{}
		if !check(C.pipe(&pair[0]) == 0, 2504, c'pipe(pair) == 0') { return 1 }
		epoll := C.epoll_create1(C.EPOLL_CLOEXEC)
		if !check(epoll >= 0, 2506, c'epoll >= 0') { return 1 }
		mut requested := C.epoll_event{ events: u32(C.EPOLLIN), data: C.epoll_data_t{ u64: u64(0x56494e495845504f) } }
		if !check(C.epoll_ctl(epoll, C.EPOLL_CTL_ADD, pair[0], &requested) == 0, 2511, c'epoll_ctl(epoll, EPOLL_CTL_ADD, pair[0], &requested) == 0') {
			return 1
		}
		mut observed := [4]C.epoll_event{}
		C.memset(&observed[0], 0xa5, sizeof(observed))
		if !check(C.epoll_wait(epoll, &observed[0], 4, 0) == 0, 2515, c'epoll_wait(epoll, observed, 4, 0) == 0') {
			return 1
		}
		if !check(C.write(pair[1], c'e', 1) == 1, 2516, c'write(pair[1], "e", 1) == 1') { return 1 }
		if !check(C.epoll_wait(epoll, &observed[0], 4, 1000) == 1, 2517, c'epoll_wait(epoll, observed, 4, 1000) == 1') {
			return 1
		}
		if !check((observed[0].events & C.EPOLLIN) != 0, 2518, c'(observed[0].events & EPOLLIN) != 0') {
			return 1
		}
		if !check(observed[0].data.u64 == requested.data.u64, 2519, c'observed[0].data.u64 == requested.data.u64') {
			return 1
		}
		mut byte := i8(0)
		if !check(C.read(pair[0], &byte, 1) == 1, 2522, c'read(pair[0], &byte, 1) == 1') {
			return 1
		}
		if !check(byte == `e`, 2523, c"byte == 'e'") { return 1 }
		if !check(C.epoll_wait(epoll, &observed[0], 4, 0) == 0, 2524, c'epoll_wait(epoll, observed, 4, 0) == 0') {
			return 1
		}
		if !check(C.close(epoll) == 0, 2525, c'close(epoll) == 0') { return 1 }
		if !check(C.close(pair[0]) == 0, 2526, c'close(pair[0]) == 0') { return 1 }
		if !check(C.close(pair[1]) == 0, 2527, c'close(pair[1]) == 0') { return 1 }
		C.puts(c'QEMU CORE PASS: Linux epoll ABI and event count')
		return 0
	}
}
