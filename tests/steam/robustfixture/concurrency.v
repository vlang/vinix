// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module robustfixture

#include <pthread.h>
struct C.pthread_t {}
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
@[c_extern]
fn C.robust_fixture_mapping_worker(voidptr) voidptr

struct Worker { mut: id i32 }
__global workers [16]Worker
__global handles [16]C.pthread_t

@[export: 'robust_fixture_mapping_worker']
pub fn mapping_worker(argument voidptr) voidptr {
	$if steam_i386 ? {
	unsafe {
		worker := &Worker(argument)
		for round := 0; round < 1000; round++ {
			length := usize(if round & 1 == 0 { 1 } else { 4097 })
			address := C.robust_subject_mmap(nil, length, 2, 1, worker.id, 0)
			C.assert(usize(address) == 0x100000 + usize(worker.id) * 0x10000)
			C.assert(C.robust_subject_munmap(address, length) == 0)
		}
	}
	}
	return unsafe { nil }
}

fn concurrency_tests() {
	concurrent_mode = true
	unsafe {
		for i := 0; i < 16; i++ {
			workers[i].id = i32(i + 1)
			C.assert(C.pthread_create(&handles[i], nil, C.robust_fixture_mapping_worker, &workers[i]) == 0)
		}
		for i := 0; i < 16; i++ { C.assert(C.pthread_join(handles[i], nil) == 0) }
	}
	concurrent_mode = false
}
