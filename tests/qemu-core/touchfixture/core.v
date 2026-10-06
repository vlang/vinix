// SPDX-License-Identifier: BSD-2-Clause
// Independent native first-touch fixture translated from test.c:169-281.
@[translated]
@[has_globals]
module touchfixture

#include <touchfixture_v_contract.h>

@[typedef]
struct C.pthread_t {}

@[typedef]
struct C.pthread_barrier_t {}

struct C.sysinfo {
mut:
	freeram u64
}

struct C.vqt_volatile_word {
mut:
	value u64
}

struct TouchWorker {
mut:
	slots &C.vqt_volatile_word = unsafe { nil }
	barrier &C.pthread_barrier_t = unsafe { nil }
	index u32
}

@[c_extern]
__global C.errno i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.sysconf(i32) i64
fn C.sysinfo(&C.sysinfo) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.mprotect(voidptr, usize, i32) i32
fn C.fork() i32
fn C._exit(i32)
fn C.reap_ok(i32) i32
fn C.memset(voidptr, i32, usize) voidptr
fn C.pipe(&i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.alarm(u32) u32
fn C.pthread_barrier_init(&C.pthread_barrier_t, voidptr, u32) i32
fn C.pthread_barrier_wait(&C.pthread_barrier_t) i32
fn C.pthread_barrier_destroy(&C.pthread_barrier_t) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.vqt_anonymous_touch(voidptr) voidptr

fn check(ok bool, line i32, expression &char) bool {
	if !ok {
		unsafe { C.printf(c'QEMU CORE FAIL line %d: %s (errno=%d)\n', line, expression, C.errno) }
	}
	return ok
}

@[export: 'vqt_anonymous_touch']
pub fn anonymous_touch(argument voidptr) voidptr {
	unsafe {
		worker := &TouchWorker(argument)
		C.pthread_barrier_wait(worker.barrier)
		worker.slots[worker.index].value = u64(0x56490000) + worker.index
		return nil
	}
}

@[export: 'test_anonymous_first_touch']
pub fn anonymous_first_touch() i32 {
	unsafe {
		page := usize(C.sysconf(C._SC_PAGESIZE))
		span := usize(4 * 1024 * 1024)
		mut before := C.sysinfo{}
		mut reserved := C.sysinfo{}
		mut committed := C.sysinfo{}
		if !check(C.sysinfo(&before) == 0, 191, c'sysinfo(&before) == 0') { return 1 }
		mut area := &u8(C.mmap(nil, span, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		if !check(usize(area) != usize(C.MAP_FAILED), 194, c'area != MAP_FAILED') { return 1 }
		if !check(C.sysinfo(&reserved) == 0, 195, c'sysinfo(&reserved) == 0') { return 1 }
		$if amd64 {
			if !check(reserved.freeram + u64(1024 * 1024) >= before.freeram, 199, c'reserved.freeram + 1024UL * 1024 >= before.freeram') { return 1 }
		}
		if !check(C.munmap(&area[page], page) == 0, 202, c'munmap(area + page, page) == 0') { return 1 }
		if !check(area[0] == 0 && area[2 * page] == 0 && area[span - 1] == 0, 203, c'area[0] == 0 && area[2 * page] == 0 && area[span - 1] == 0') { return 1 }
		if !check(C.munmap(area, page) == 0, 204, c'munmap(area, page) == 0') { return 1 }
		if !check(C.munmap(&area[2 * page], span - 2 * page) == 0, 205, c'munmap(area + 2 * page, span - 2 * page) == 0') { return 1 }

		area = &u8(C.mmap(nil, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		if !check(usize(area) != usize(C.MAP_FAILED), 209, c'area != MAP_FAILED') { return 1 }
		child := C.fork()
		if !check(child >= 0, 211, c'child >= 0') { return 1 }
		if child == 0 {
			for i := usize(0); i < page; i++ {
				if area[i] != 0 { C._exit(1) }
			}
			C.memset(area, 0x42, page)
			C._exit(if area[page - 1] == 0x42 { 0 } else { 1 })
		}
		if !check(C.reap_ok(child) == 0, 219, c'reap_ok(child) == 0') { return 1 }
		for i := usize(0); i < page; i++ {
			if !check(area[i] == 0, 221, c'area[i] == 0') { return 1 }
		}
		if !check(C.munmap(area, page) == 0, 222, c'munmap(area, page) == 0') { return 1 }

		area = &u8(C.mmap(nil, 3 * page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		if !check(usize(area) != usize(C.MAP_FAILED), 227, c'area != MAP_FAILED') { return 1 }
		mut endpoints := [2]i32{}
		mut payload := u8(0x73)
		if !check(C.pipe(&endpoints[0]) == 0, 230, c'pipe(endpoints) == 0') { return 1 }
		if !check(C.write(endpoints[1], &payload, 1) == 1, 231, c'write(endpoints[1], &payload, 1) == 1') { return 1 }
		if !check(C.read(endpoints[0], &area[page], 1) == 1, 232, c'read(endpoints[0], area + page, 1) == 1') { return 1 }
		if !check(area[page] == payload && area[page + 1] == 0, 233, c'area[page] == payload && area[page + 1] == 0') { return 1 }
		if !check(C.close(endpoints[0]) == 0 && C.close(endpoints[1]) == 0, 234, c'close(endpoints[0]) == 0 && close(endpoints[1]) == 0') { return 1 }
		if !check(C.mprotect(area, page, C.PROT_READ) == 0, 235, c'mprotect(area, page, PROT_READ) == 0') { return 1 }
		if !check(area[0] == 0 && area[page - 1] == 0, 236, c'area[0] == 0 && area[page - 1] == 0') { return 1 }
		if !check(C.mprotect(area, page, C.PROT_READ | C.PROT_WRITE) == 0, 237, c'mprotect(area, page, PROT_READ | PROT_WRITE) == 0') { return 1 }
		area[0] = 0x24
		if !check(area[0] == 0x24, 239, c'area[0] == 0x24') { return 1 }
		if !check(C.munmap(area, 3 * page) == 0, 240, c'munmap(area, 3 * page) == 0') { return 1 }

		area = &u8(C.mmap(nil, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		if !check(usize(area) != usize(C.MAP_FAILED), 244, c'area != MAP_FAILED') { return 1 }
		mut threads := [2]C.pthread_t{}
		mut arguments := [2]TouchWorker{}
		mut barrier := C.pthread_barrier_t{}
		if !check(C.pthread_barrier_init(&barrier, nil, 3) == 0, 249, c'pthread_barrier_init(&barrier, NULL, workers + 1) == 0') { return 1 }
		C.alarm(30)
		for i := u32(0); i < 2; i++ {
			arguments[i] = TouchWorker{slots: &C.vqt_volatile_word(area), barrier: &barrier, index: i}
			if !check(C.pthread_create(&threads[i], nil, C.vqt_anonymous_touch, voidptr(&arguments[i])) == 0, 256, c'pthread_create(&threads[i], NULL, anonymous_touch, &arguments[i]) == 0') { return 1 }
		}
		barrier_result := C.pthread_barrier_wait(&barrier)
		if !check(barrier_result == 0 || barrier_result == C.PTHREAD_BARRIER_SERIAL_THREAD, 259, c'barrier_result == 0 || barrier_result == PTHREAD_BARRIER_SERIAL_THREAD') { return 1 }
		for i := u32(0); i < 2; i++ {
			if !check(C.pthread_join(threads[i], nil) == 0, 261, c'pthread_join(threads[i], NULL) == 0') { return 1 }
			if !check((&C.vqt_volatile_word(area))[i].value == u64(0x56490000) + i, 262, c'((volatile unsigned long *)area)[i] == 0x56490000UL + i') { return 1 }
		}
		C.alarm(0)
		if !check(C.pthread_barrier_destroy(&barrier) == 0, 265, c'pthread_barrier_destroy(&barrier) == 0') { return 1 }
		if !check(area[page - 1] == 0, 266, c'area[page - 1] == 0') { return 1 }
		if !check(C.munmap(area, page) == 0, 267, c'munmap(area, page) == 0') { return 1 }

		if !check(C.sysinfo(&before) == 0, 270, c'sysinfo(&before) == 0') { return 1 }
		area = &u8(C.mmap(nil, span, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS | C.MAP_POPULATE, -1, 0))
		if !check(usize(area) != usize(C.MAP_FAILED), 273, c'area != MAP_FAILED') { return 1 }
		if !check(C.sysinfo(&committed) == 0, 274, c'sysinfo(&committed) == 0') { return 1 }
		if !check(committed.freeram + u64(span) - u64(1024 * 1024) <= before.freeram, 275, c'committed.freeram + span - 1024UL * 1024 <= before.freeram') { return 1 }
		if !check(area[0] == 0 && area[span - 1] == 0, 276, c'area[0] == 0 && area[span - 1] == 0') { return 1 }
		if !check(C.munmap(area, span) == 0, 277, c'munmap(area, span) == 0') { return 1 }
		C.puts(c'QEMU CORE PASS: anonymous first touch, zero pages, fork and explicit population')
		return 0
	}
}
