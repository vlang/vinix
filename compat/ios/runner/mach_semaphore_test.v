// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

$if macos {
	fn C.mach_task_self() u32
	fn C.semaphore_create(u32, &u32, i32, i32) i32
	fn C.semaphore_destroy(u32, u32) i32
	fn C.semaphore_signal(u32) i32
	fn C.semaphore_wait(u32) i32
	fn C.mach_port_mod_refs(u32, u32, i32, i32) i32
	fn C.mach_port_get_refs(u32, u32, i32, &u32) i32
	fn C.mach_port_type(u32, u32, &u32) i32
	fn C.mach_port_deallocate(u32, u32) i32
}

fn sem_test_task(native bool) u32 {
	$if macos {
		if native { return C.mach_task_self() }
	}
	return system_data.task_self
}

fn sem_test_create(native bool, output &u32, policy i32, count i32) i32 {
	$if macos {
		if native { return C.semaphore_create(sem_test_task(true), output, policy, count) }
	}
	return darwin_semaphore_create(sem_test_task(false), output, policy, count)
}

fn sem_test_destroy(native bool, name u32) i32 {
	$if macos {
		if native { return C.semaphore_destroy(sem_test_task(true), name) }
	}
	return darwin_semaphore_destroy(sem_test_task(false), name)
}

fn sem_test_signal(native bool, name u32) i32 {
	$if macos {
		if native { return C.semaphore_signal(name) }
	}
	return darwin_semaphore_signal(name)
}

fn sem_test_wait(native bool, name u32) i32 {
	$if macos {
		if native { return C.semaphore_wait(name) }
	}
	return darwin_semaphore_wait(name)
}

fn sem_test_refs(native bool, name u32) u32 {
	mut refs := u32(0x12345678)
	$if macos {
		if native {
			assert C.mach_port_get_refs(sem_test_task(true), name, 0, unsafe { &refs }) == 0
			return refs
		}
	}
	assert darwin_mach_port_get_refs(sem_test_task(false), name, 0, unsafe { &refs }) == 0
	return refs
}

fn sem_test_add_refs(native bool, name u32, count i32) i32 {
	$if macos {
		if native { return C.mach_port_mod_refs(sem_test_task(true), name, 0, count) }
	}
	return darwin_mach_port_mod_refs(sem_test_task(false), name, 0, count)
}

fn sem_test_deallocate(native bool, name u32) i32 {
	$if macos {
		if native { return C.mach_port_deallocate(sem_test_task(true), name) }
	}
	return darwin_mach_port_deallocate(sem_test_task(false), name)
}

fn sem_test_worker(native bool, name u32) i32 {
	darwin_set_errno(187)
	result := sem_test_wait(native, name)
	assert unsafe { *C.ios_errno_address() } == 187
	return result
}

fn sem_test_delayed_signal(native bool, name u32) {
	time.sleep(30 * time.millisecond)
	assert sem_test_signal(native, name) == 0
}

fn sem_test_queue(name u32, wanted int) {
	for _ in 0 .. 1000 {
		mut state := mach_semaphore_pin(name) or { panic('missing test semaphore') }
		assert C.pthread_mutex_lock(state.guard) == 0
		mut count := 0
		mut cursor := state.head
		for cursor != unsafe { nil } {
			count++
			cursor = cursor.next
		}
		assert C.pthread_mutex_unlock(state.guard) == 0
		mach_semaphore_unpin(mut state)
		if count == wanted { return }
		time.sleep(time.millisecond)
	}
	panic('semaphore workers did not enter native waits')
}

fn sem_test_shared(native bool) {
	mut output := [u32(0x11223344), 0x12345678, 0x88776655]!
	darwin_set_errno(177)
	for policy in [i32(-1), 1, 3] {
		assert sem_test_create(native, unsafe { &output[1] }, policy, 0) == 4
		assert output[1] == 0x12345678
	}
	assert sem_test_create(native, unsafe { &output[1] }, 0, -1) == 4 && output[1] == 0x12345678
	for policy in [i32(0), 2] {
		assert sem_test_create(native, unsafe { &output[1] }, policy, 2) == 0
		port := output[1]
		assert output[0] == 0x11223344 && output[2] == 0x88776655
		assert sem_test_refs(native, port) == 1
		assert sem_test_wait(native, port) == 0 && sem_test_wait(native, port) == 0
		worker := spawn sem_test_delayed_signal(native, port)
		start := time.sys_mono_now()
		darwin_set_errno(177)
		assert sem_test_wait(native, port) == 0
		assert unsafe { *C.ios_errno_address() } == 177
		assert time.sys_mono_now() - start >= 15000000
		worker.wait()
		darwin_set_errno(177)
		assert sem_test_add_refs(native, port, 2) == 0
		assert sem_test_destroy(native, port) == 0 && sem_test_refs(native, port) == 2
		assert sem_test_signal(native, port) == 37 && sem_test_wait(native, port) == 37
		mut kind := u32(0)
		$if macos {
			if native {
				assert C.mach_port_type(sem_test_task(true), port, unsafe { &kind }) == 0
			}
		}
		if !native {
			assert darwin_mach_port_type(sem_test_task(false), port, unsafe { &kind }) == 0
		}
		assert kind == 0x10000
		assert sem_test_destroy(native, port) == 0 && sem_test_refs(native, port) == 1
		assert sem_test_deallocate(native, port) == 0
		assert sem_test_signal(native, port) == 15 && sem_test_wait(native, port) == 15
		assert sem_test_destroy(native, port) == 0x1000000a
	}
	assert sem_test_create(native, unsafe { &output[1] }, 0, 0) == 0
	port := output[1]
	mut jobs := []thread i32{}
	for _ in 0 .. 8 { jobs << spawn sem_test_worker(native, port) }
	if native { time.sleep(50 * time.millisecond) } else { sem_test_queue(port, 8) }
	darwin_set_errno(177)
	assert sem_test_destroy(native, port) == 0
	assert unsafe { *C.ios_errno_address() } == 177
	for result in jobs.wait() {
		assert result == 37
	}
	darwin_set_errno(177)
	for _ in 0 .. 64 {
		assert sem_test_create(native, unsafe { &output[1] }, 0, 1) == 0
		assert sem_test_wait(native, output[1]) == 0
		assert sem_test_destroy(native, output[1]) == 0
	}
	assert sem_test_signal(native, 0) == 15 && sem_test_wait(native, 0xffffffff) == 15
	assert sem_test_destroy(native, 0) == 4 && sem_test_destroy(native, 0xffffffff) == 4
}

fn sem_test_order_and_last_right() {
	mut port := u32(0)
	for policy in [i32(0), 2] {
		assert darwin_semaphore_create(system_data.task_self, unsafe { &port }, policy, 0) == 0
		mut jobs := []thread i32{}
		for i in 0 .. 8 {
			jobs << spawn sem_test_worker(false, port)
			sem_test_queue(port, i + 1)
		}
		for i in 0 .. 8 {
			assert darwin_semaphore_signal(port) == 0
			index := if policy == 0 { i } else { 7 - i }
			assert jobs[index].wait() == 0
			sem_test_queue(port, 7 - i)
		}
		assert darwin_semaphore_destroy(system_data.task_self, port) == 0
	}
	assert darwin_semaphore_create(system_data.task_self, unsafe { &port }, 0, 0) == 0
	mut jobs := []thread i32{}
	for _ in 0 .. 8 { jobs << spawn sem_test_worker(false, port) }
	sem_test_queue(port, 8)
	assert darwin_mach_port_deallocate(system_data.task_self, port) == 0
	for result in jobs.wait() {
		assert result == 37
	}
	assert system_data.semaphores == unsafe { nil }
	mut bits := u32(0x12345678)
	assert darwin_mach_port_type(system_data.task_self, port, unsafe { &bits }) == 15 && bits == 0x12345678
	assert darwin_semaphore_create(system_data.task_self, unsafe { &port }, 0, 1) == 0
	assert darwin_mach_port_mod_refs(system_data.task_self, port, 1, 0) == 17
	assert darwin_mach_port_get_refs(system_data.task_self, port, 6, unsafe { &bits }) == 18 && bits == 0x12345678
	assert darwin_mach_port_mod_refs(system_data.task_self, port, 0, -2) == 18
	assert sem_test_refs(false, port) == 1
	assert darwin_semaphore_destroy(system_data.task_self, port) == 0
	assert system_data.semaphores == unsafe { nil }
}

fn sem_test_bounds_and_fork() ! {
	mut port := u32(0x12345678)
	// Only the measured FIFO/LIFO policies are implemented. Reject other flags.
	assert darwin_semaphore_create(system_data.task_self, unsafe { &port }, 4, 0) == 4
	assert port == 0x12345678
	assert darwin_semaphore_create(system_data.task_self, unsafe { nil }, 0, 0) == 4
	assert darwin_semaphore_create(system_data.task_self + 1, unsafe { &port }, 0, 0) == 4
	assert port == 0x12345678
	// The adapter rejects overflow instead of reproducing the Mac's count wrap.
	assert darwin_semaphore_create(system_data.task_self, unsafe { &port }, 0, 0x7fffffff) == 0
	assert darwin_semaphore_signal(port) == 6
	assert darwin_semaphore_wait(port) == 0 && darwin_semaphore_signal(port) == 0
	assert darwin_semaphore_destroy(system_data.task_self, port) == 0
	mut refs := u32(0x12345678)
	assert darwin_mach_port_get_refs(system_data.task_self, port, 6, unsafe { &refs }) == 18
	assert refs == 0x12345678
	assert darwin_mach_port_mod_refs(system_data.task_self, port, 6, 0) == 18
	thread_port := darwin_mach_thread_self()
	assert thread_port != 0
	assert darwin_semaphore_signal(thread_port) == 20 && darwin_semaphore_wait(thread_port) == 20
	assert darwin_semaphore_destroy(system_data.task_self, thread_port) == 4
	assert darwin_mach_port_deallocate(system_data.task_self, thread_port) == 0

	assert darwin_semaphore_create(system_data.task_self, unsafe { &port }, 0, 0) == 0
	worker := spawn sem_test_worker(false, port)
	sem_test_queue(port, 1)
	image_atfork_start()!
	child := C.ios_fork()
	assert child >= 0
	if child == 0 {
		// Inherited names are outside the process-private subset. Other
		// threads vanished; their copied wait nodes must never be visited.
		if system_data.semaphores != unsafe { nil } || darwin_semaphore_signal(port) != 15
			|| darwin_semaphore_wait(port) != 15 {
			C._exit(1)
		}
		C._exit(0)
	}
	mut status := i32(-1)
	assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0
	image_atfork_stop()
	sem_test_queue(port, 1)
	assert darwin_semaphore_signal(port) == 0 && worker.wait() == 0
	assert darwin_semaphore_destroy(system_data.task_self, port) == 0
	assert system_data.semaphores == unsafe { nil }
}

fn test_mach_semaphore() {
	mut old := u32(0)
	for round in 0 .. 2 {
		system_data_start()!
		assert darwin_semaphore_signal(old) == 15
		$if macos {
			if round == 0 { sem_test_shared(true) }
		}
		sem_test_shared(false)
		sem_test_order_and_last_right()
		sem_test_bounds_and_fork()!
		assert system_data.semaphores == unsafe { nil }
		// Image shutdown must reclaim an application-owned, undestroyed object.
		assert darwin_semaphore_create(system_data.task_self, unsafe { &old }, 0, 1) == 0
		for name in ['_semaphore_create', '_semaphore_destroy', '_semaphore_signal', '_semaphore_wait'] {
			assert (pthread_symbol(name) or { u64(0) }) != 0
		}
		system_data_stop()
		assert system_data == unsafe { nil }
	}
	println('IOS-SEMAPHORE: native credits and waits, FIFO/LIFO, eight destroy/drop waiters, send refs, fork and two teardowns')
}
