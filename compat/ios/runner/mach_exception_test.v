// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

#include <dlfcn.h>
fn C.dlsym(voidptr, &char) voidptr
$if macos { fn C.mach_task_self() u32 }

type ExcTestRaise = fn (u32, u32, u32, i32, &i32, u32) i32
type ExcTestState = fn (u32, i32, &i32, u32, &i32, &u32, u32, &u32, &u32) i32
type ExcTestIdentity = fn (u32, u32, u32, i32, &i32, u32, &i32, &u32, u32, &u32, &u32) i32

struct ExcTestClients {
	raise ExcTestRaise
	state ExcTestState
	identity ExcTestIdentity
}

fn exc_test_clients(native bool) ExcTestClients {
	$if macos {
		if native {
			return ExcTestClients{unsafe { ExcTestRaise(C.dlsym(voidptr(-2), c'exception_raise')) },
				unsafe { ExcTestState(C.dlsym(voidptr(-2), c'exception_raise_state')) },
				unsafe { ExcTestIdentity(C.dlsym(voidptr(-2), c'exception_raise_state_identity')) }}
		}
	}
	library := '/usr/lib/libSystem.B.dylib'
	a := runtime_symbol(library, '_exception_raise') or { panic(err) }
	b := runtime_symbol(library, '_exception_raise_state') or { panic(err) }
	c := runtime_symbol(library, '_exception_raise_state_identity') or { panic(err) }
	return ExcTestClients{unsafe { ExcTestRaise(voidptr(a)) }, unsafe { ExcTestState(voidptr(b)) }, unsafe { ExcTestIdentity(voidptr(c)) }}
}

fn exc_test_matrix(clients ExcTestClients, destination u32, worker u32, task u32, simple_result i32, state_result i32) {
	code := [i32(-2147483648), 2147483647]!
	old := [1296]u32{init: 0x76543210}
	for code_count in [u32(0), 1, 2, 3, 0xffffffff]! {
		for old_count in [u32(0), 68, 1296, 1297, 0xffffffff]! {
			for capacity in [u32(0), 68, 1296]! {
				mut output := [1298]u32{init: 0x12345678}
				mut flavor := i32(6)
				mut count := capacity
				a := clients.raise(destination, worker, task, 1, unsafe { &code[0] }, code_count)
				b := clients.state(destination, 1, unsafe { &code[0] }, code_count, unsafe { &flavor }, unsafe { &old[0] }, old_count, unsafe { &output[1] }, unsafe { &count })
				c := clients.identity(destination, worker, task, 1, unsafe { &code[0] }, code_count, unsafe { &flavor }, unsafe { &old[0] }, old_count, unsafe { &output[1] }, unsafe { &count })
				assert a == if code_count > 2 { i32(-307) } else { simple_result }, 'destination=0x${destination.hex()} thread=0x${worker.hex()} task=0x${task.hex()} code_count=${code_count} actual=0x${u32(a).hex()}'
				expected := if code_count > 2 || old_count > 1296 { i32(-307) } else { state_result }
				assert b == expected && c == expected && flavor == 6 && count == capacity
				for value in output { assert value == 0x12345678 }
				for value in old { assert value == 0x76543210 }
				assert code == [i32(-2147483648), 2147483647]!
			}
		}
	}
}

fn exc_test_dead_worker() u32 { return darwin_mach_thread_self() }

fn exc_test_refs(port u32, right i32) u32 {
	mut refs := u32(0)
	assert darwin_mach_port_get_refs(system_data.task_self, port, right, unsafe { &refs }) == 0
	return refs
}

fn exc_test_namespace(clients ExcTestClients) {
	task := system_data.task_self
	worker := darwin_mach_thread_self()
	assert worker != 0
	mut semaphore := u32(0)
	assert darwin_semaphore_create(task, unsafe { &semaphore }, 0, 1) == 0
	worker_refs := exc_test_refs(worker, 0)
	for destination in [task, worker, semaphore]! {
		// Host thread ports belong to the native Mac namespace. Their native
		// task/descriptor cases run above; emulated semaphore names cannot be
		// sent as native descriptors. Vinix's three kinds share one namespace.
		$if macos { if destination == worker { continue } }
		exc_test_matrix(clients, destination, worker, task, 5, 4)
		// Null and dead descriptors are legal COPY_SEND inputs, unlike names
		// with no rights. Invalid destinations take precedence over either.
		for descriptor in [u32(0), 0xffffffff, semaphore]! { exc_test_matrix(clients, destination, descriptor, descriptor, 5, 4) }
		for descriptor in [[u32(0x65432103), task]!, [worker, 0x65432103]!]! {
			// The state-only form has no descriptors, so check it separately.
			code := [i32(1), -2]!
			mut flavor := i32(6)
			mut count := u32(68)
			mut state := [68]u32{init: 0x12345678}
			assert clients.raise(destination, descriptor[0], descriptor[1], 1, unsafe { &code[0] }, 2) == 0x1000000a
			assert clients.identity(destination, descriptor[0], descriptor[1], 1, unsafe { &code[0] }, 2, unsafe { &flavor }, unsafe { &state[0] }, 68, unsafe { &state[0] }, unsafe { &count }) == 0x1000000a
			assert flavor == 6 && count == 68
			for value in state { assert value == 0x12345678 }
		}
	}
	assert exc_test_refs(worker, 0) == worker_refs && exc_test_refs(semaphore, 0) == 1
	// Rejected exception RPCs neither consume COPY_SEND rights nor alter the
	// semaphore's credit. This remains a usable synchronization object.
	assert darwin_semaphore_wait(semaphore) == 0 && darwin_semaphore_signal(semaphore) == 0
	assert darwin_mach_port_mod_refs(task, semaphore, 0, 1) == 0
	assert darwin_semaphore_destroy(task, semaphore) == 0
	assert exc_test_refs(semaphore, 0) == 1 && exc_test_refs(semaphore, 4) == 0
	exc_test_matrix(clients, semaphore, worker, task, 5, 4)
	exc_test_matrix(clients, task, semaphore, semaphore, 5, 4)
	assert darwin_mach_port_deallocate(task, semaphore) == 0
	exc_test_matrix(clients, semaphore, 0x65432103, 0x65432103, 0x10000003, 0x10000003)
	dead_worker := spawn exc_test_dead_worker()
	dead := dead_worker.wait()
	// Native pthread_join can return while the Mac's kernel thread still
	// finishes retiring. Wait for its port to become a dead name explicitly.
	for _ in 0 .. 1000 {
		if exc_test_refs(dead, 4) > 0 { break }
		time.sleep(time.millisecond)
	}
	assert exc_test_refs(dead, 4) > 0
	exc_test_matrix(clients, dead, worker, task, 0x10000003, 0x10000003)
	exc_test_matrix(clients, task, dead, dead, 5, 4)
	assert darwin_mach_port_deallocate(task, dead) == 0
	assert darwin_mach_port_deallocate(task, worker) == 0
}

fn exc_test_state(clients ExcTestClients, id int) {
	mut environment := [32]u64{}
	assert C.fegetenv(unsafe { voidptr(&environment[0]) }) == 0
	previous := unsafe { *C.ios_errno_address() }
	defer { C.fesetenv(unsafe { voidptr(&environment[0]) }); darwin_set_errno(previous) }
	for rounding in [i32(C.FE_TONEAREST), C.FE_UPWARD, C.FE_DOWNWARD, C.FE_TOWARDZERO]! {
		assert C.fesetround(rounding) == 0
		C.feclearexcept(C.FE_ALL_EXCEPT)
		C.feraiseexcept(C.FE_DIVBYZERO | C.FE_INEXACT)
		flags := C.fetestexcept(C.FE_ALL_EXCEPT)
		darwin_set_errno(70 + id)
		for destination in [u32(0), 0xffffffff, 0x65432103]! {
			exc_test_matrix(clients, destination, 0x65432103, 0x65432103, 0x10000003, 0x10000003)
		}
		assert C.fegetround() == rounding && C.fetestexcept(C.FE_ALL_EXCEPT) == flags && unsafe { *C.ios_errno_address() } == 70 + id
	}
}

fn test_mach_exception_clients() {
	clients := exc_test_clients(false)
	$if macos {
		native := exc_test_clients(true)
		exc_test_state(native, 0)
		task := C.mach_task_self()
		worker := darwin_mach_thread_self()
		for api in [native, clients]! {
			for destination in [task, worker]! {
				exc_test_matrix(api, destination, worker, task, 5, 4)
			}
		}
		assert C.ios_native_port_deallocate(worker) == 0
	}
	mut previous_semaphore := u32(0)
	for _ in 0 .. 2 {
		system_data_start()!
		exc_test_matrix(clients, previous_semaphore, 0, 0, 0x10000003, 0x10000003)
		exc_test_namespace(clients)
		exc_test_state(clients, 0)
		mut workers := []thread{cap: 8}
		for id in 0 .. 8 { workers << spawn exc_test_state(clients, id) }
		workers.wait()
		unsafe { workers.free() }
		assert darwin_semaphore_create(system_data.task_self, unsafe { &previous_semaphore }, 0, 0) == 0
		image_atfork_start()!
		child := C.ios_fork()
		assert child >= 0
		if child == 0 {
			exc_test_matrix(clients, previous_semaphore, 0, 0, 0x10000003, 0x10000003)
			C._exit(0)
		}
		mut status := i32(-1)
		assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0
		image_atfork_stop()
		exc_test_matrix(clients, previous_semaphore, 0, 0, 5, 4)
		system_data_stop()
		assert system_data == unsafe { nil }
	}
	for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! {
		for name in ['_exception_raise', '_exception_raise_state', '_exception_raise_state_identity']! {
			mut rejected := false
			runtime_symbol(library, name) or { rejected = true }
			assert rejected
		}
	}
	println('IOS-MACH-EXCEPTION: native oracle, code/state bounds and error precedence, task/thread/semaphore send and dead rights, COPY_SEND ownership and credits, unchanged inputs/outputs/errno/fenv, eight concurrent callers, fork and two teardowns passed; Vinix user exception delivery remains unsupported')
}
