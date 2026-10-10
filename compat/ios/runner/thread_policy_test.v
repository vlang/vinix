// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct PolicyLiveTest {
mut:
	name u64
	release u64
}

fn policy_test_live_worker(state &PolicyLiveTest) u32 {
	name := darwin_mach_thread_self()
	mut before := [i32(-1), -1, -1]!
	assert C.ios_thread_getsched(u64(C.pthread_self()), unsafe { &before[0] }) == 0
	C.ios_store_pointer(unsafe { &state.name }, name)
	for C.ios_load_pointer(unsafe { &state.release }) == 0 { C.sched_yield() }
	$if linux {
		mut after := [i32(-1), -1, -1]!
		assert C.ios_thread_getsched(u64(C.pthread_self()), unsafe { &after[0] }) == 0
		assert before[0] == after[0] && before[1] == after[1]
	}
	return name
}

fn policy_test_remote() {
	state := unsafe { &PolicyLiveTest(C.calloc(1, sizeof(PolicyLiveTest))) }
	assert state != unsafe { nil }
	job := spawn policy_test_live_worker(state)
	mut name := u32(0)
	for name == 0 {
		name = u32(C.ios_load_pointer(unsafe { &state.name }))
		C.sched_yield()
	}
	mut fair := i32(1)
	darwin_set_errno(177)
	assert darwin_thread_policy_set(name, 4, unsafe { &fair }, 1) == 46
	$if linux {
		assert darwin_thread_policy_set(name, 1, unsafe { &fair }, 1) == 46
	}
	assert unsafe { *C.ios_errno_address() } == 177
	C.ios_store_pointer(unsafe { &state.release }, 1)
	assert job.wait() == name
	assert darwin_thread_policy_set(name, 4, unsafe { nil }, 0) == 0x10000003
	assert darwin_mach_port_deallocate(system_data.task_self, name) == 0
	C.free(state)
}

fn policy_test_worker() u32 {
	port := darwin_mach_thread_self()
	assert port != 0
	mut input := [i32(0x5a5a5a5a), 1, 0x5a5a5a5a]!
	for _ in 0 .. 1000 {
		darwin_set_errno(177)
		assert darwin_thread_policy_set(port, 4, unsafe { &input[1] }, 1) == 46
		assert unsafe { *C.ios_errno_address() } == 177
		assert input[0] == 0x5a5a5a5a && input[1] == 1 && input[2] == 0x5a5a5a5a
	}
	assert darwin_thread_policy_set(port, 4, unsafe { nil }, 0) == 46
	assert darwin_thread_policy_set(port, 1, unsafe { nil }, 0) == 0
	assert darwin_thread_policy_set(port, 1, unsafe { &input[1] }, 1) == 0
	$if linux {
		mut native := [i32(-1), -1, -1]!
		assert C.ios_thread_getsched(u64(C.pthread_self()), unsafe { &native[0] }) == 0
		assert native[0] == 0 && native[1] == 0
		// Verify that standard policy actually restores fair native scheduling
		// after changing the live caller to FIFO. This standalone guest is root.
		assert C.ios_thread_setsched(u64(C.pthread_self()), 1, 5, 0) == 0
		assert C.ios_thread_getsched(u64(C.pthread_self()), unsafe { &native[0] }) == 0
		assert native[0] == 1 && native[1] == 5
		assert darwin_thread_policy_set(port, 1, unsafe { nil }, 0) == 0
		assert C.ios_thread_getsched(u64(C.pthread_self()), unsafe { &native[0] }) == 0
		assert native[0] == 0 && native[1] == 0
		input[1] = 0
		assert darwin_thread_policy_set(port, 1, unsafe { &input[1] }, 1) == 46
		assert darwin_thread_policy_set(port, 1, unsafe { nil }, 1) == 4
		assert darwin_thread_policy_set(port, 2, unsafe { &input[1] }, 0) == 4
		assert darwin_thread_policy_set(port, 3, unsafe { &input[1] }, 0) == 4
		assert darwin_thread_policy_set(port, 99, unsafe { &input[1] }, 1) == 4
	}
	for count in [u32(17), 1024, 0xffffffff] {
		assert darwin_thread_policy_set(port, 4, unsafe { nil }, count) == -307
		assert darwin_thread_policy_set(0, 4, unsafe { nil }, count) == -307
	}
	for name in [u32(0), 0xffffffff, 0x76543] {
		assert darwin_thread_policy_set(name, 4, unsafe { &input[1] }, 1) == 0x10000003
	}
	return port // The owned send reference becomes a dead name on worker exit.
}

fn test_darwin_thread_policy() {
	for _ in 0 .. 2 {
		system_data_start()!
		policy_test_remote()
		$if linux {
			assert darwin_thread_policy_set(system_data.task_self, 4, unsafe { nil }, 0) == 4
			mut semaphore := u32(0)
			assert darwin_semaphore_create(system_data.task_self, unsafe { &semaphore }, 0, 0) == 0
			assert darwin_thread_policy_set(semaphore, 4, unsafe { nil }, 0) == 4
			assert darwin_mach_port_mod_refs(system_data.task_self, semaphore, 0, 1) == 0
			assert darwin_semaphore_destroy(system_data.task_self, semaphore) == 0
			assert darwin_thread_policy_set(semaphore, 4, unsafe { nil }, 0) == 0x10000003
			assert darwin_mach_port_deallocate(system_data.task_self, semaphore) == 0
		}
		mut workers := []thread u32{}
		for _ in 0 .. 8 { workers << spawn policy_test_worker() }
		names := workers.wait()
		for name in names {
			assert darwin_thread_policy_set(name, 4, unsafe { nil }, 0) == 0x10000003
			assert darwin_mach_port_deallocate(system_data.task_self, name) == 0
		}
		system_data_stop()
		assert darwin_thread_policy_set(0, 4, unsafe { nil }, 0) == 0x10000003
	}
	assert (thread_policy_symbol('_thread_policy_set') or { u64(0) }) != 0
	println('IOS-THREAD-POLICY: affinity/remote rejection, real fair scheduling, guarded inputs, Mach errors, eight workers and two teardowns')
}
