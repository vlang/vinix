// SPDX-License-Identifier: GPL-2.0-or-later
module main

type TaskPortsTestQuery = fn (u32, u32, voidptr, voidptr, voidptr, voidptr, voidptr) i32
struct TaskPortsSnapshot {
mut:
	bytes [416]u8
	result i32
}
fn task_ports_test_snapshot(client TaskPortsTestQuery, task u32, mask u32, incoming u32, shift int) TaskPortsSnapshot {
	mut snapshot := TaskPortsSnapshot{bytes: [416]u8{init: 0xa5}}
	base := u64(unsafe { &snapshot.bytes[0] }) + u64(shift)
	C.memcpy(voidptr(base + 96), unsafe { voidptr(&incoming) }, 4)
	darwin_set_errno(83)
	snapshot.result = client(task, mask, voidptr(base + 16), voidptr(base + 96), voidptr(base + 176), voidptr(base + 256), voidptr(base + 336))
	assert unsafe { *C.ios_errno_address() } == 83
	return snapshot
}
fn task_ports_test_word(snapshot &TaskPortsSnapshot, offset int) u32 {
	mut value := u32(0)
	C.memcpy(unsafe { voidptr(&value) }, unsafe { &snapshot.bytes[offset] }, 4)
	return value
}
fn task_ports_test_drop(snapshot &TaskPortsSnapshot, shift int) {
	$if macos {
		if snapshot.result != 0 { return }
		count := task_ports_test_word(snapshot, 96 + shift)
		assert count <= 14
		for i in 0 .. count {
			port := task_ports_test_word(snapshot, 176 + shift + int(i) * 4)
			if port != 0 && port != 0xffffffff { assert C.ios_native_port_deallocate(port) == 0 }
		}
	}
}
fn task_ports_test_default(client TaskPortsTestQuery, task u32) {
	for mask in [u32(0),2,4,0x400,0x800,0x2000,0x1bfe,0x3ffe,1,0x4000,0x80000000,0xffffffff]! {
		for incoming in [u32(0),1,13,14,0xffffffff]! {
			for shift in [0,1,3]! {
				actual := task_ports_test_snapshot(client, task, mask, incoming, shift)
				mut expected := TaskPortsSnapshot{bytes: [416]u8{init: 0xa5}}
				base := u64(unsafe { &expected.bytes[0] }) + u64(shift)
				valid := mask & ~u32(0x3ffe) == 0
				words := [mask,u32(mask != 0),0]!
				C.memcpy(voidptr(base + 96), unsafe { voidptr(&incoming) }, 4)
				if valid {
					C.memcpy(voidptr(base + 96), unsafe { &words[1] }, 4)
					if mask != 0 {
						C.memcpy(voidptr(base + 16), unsafe { &words[0] }, 4)
						for offset in [176,256,336]! { C.memcpy(voidptr(base + u64(offset)), unsafe { &words[2] }, 4) }
					}
				}
				assert actual.result == if valid { i32(0) } else { i32(4) }
				assert C.memcmp(unsafe { &actual.bytes[0] }, unsafe { &expected.bytes[0] }, 416) == 0
			}
		}
	}
}
fn task_ports_test_native(client TaskPortsTestQuery, task u32) {
	$if macos {
		native_query := unsafe { TaskPortsTestQuery(voidptr(C.task_get_exception_ports)) }
		for mask in [u32(0),2,4,0x400,0x800,0x2000,0x1bfe,0x3ffe,1,0x4000,0xffffffff]! {
			for incoming in [u32(0),1,14,0xffffffff]! { for shift in [0,1,3]! {
				// Retain the native baseline rights while comparing, so repeated
				// COPY_SEND results coalesce to the same native port names.
				baseline := task_ports_test_snapshot(native_query, C.mach_task_self(), mask, incoming, shift)
				actual := task_ports_test_snapshot(client, task, mask, incoming, shift)
				assert actual.result == baseline.result
				assert C.memcmp(unsafe { &actual.bytes[0] }, unsafe { &baseline.bytes[0] }, 416) == 0
				task_ports_test_drop(unsafe { &actual }, shift)
				task_ports_test_drop(unsafe { &baseline }, shift)
			} }
		}
		println('NATIVE-TASK-EXCEPTION-PORTS: live kernel inventory and COPY_SEND names, output-only counts, all fields and guarded unaligned extents match')
	}
}
fn task_ports_test_error(client TaskPortsTestQuery, task u32, expected i32) {
	for mask in [u32(0),2,0xffffffff]! {
		actual := task_ports_test_snapshot(client, task, mask, 0x98765432, 1)
		mut stamp := TaskPortsSnapshot{bytes: [416]u8{init: 0xa5}}
		value := u32(0x98765432)
		C.memcpy(unsafe { &stamp.bytes[97] }, unsafe { &value }, 4)
		assert actual.result == expected
		assert C.memcmp(unsafe { &actual.bytes[0] }, unsafe { &stamp.bytes[0] }, 416) == 0
		assert client(task, mask, voidptr(-1), voidptr(-1), voidptr(-1), voidptr(-1), voidptr(-1)) == expected
	}
}
fn task_ports_test_alias(client TaskPortsTestQuery, task u32) {
	// Use an unset exception type for native/adapter alias ordering. A
	// native host can have resource/corpse handlers installed independently.
	for first in 0 .. 5 { for second in first + 1 .. 5 {
		mut bytes := [416]u8{init: 0xa5}
		mut expected := [416]u8{init: 0xa5}
		base := u64(unsafe { &bytes[0] })
		mut positions := [16,96,176,256,336]!
		positions[second] = positions[first]
		values := [u32(2),1,0,0,0]!
		for i in 0 .. 5 { C.memcpy(unsafe { &expected[positions[i]] }, unsafe { &values[i] }, 4) }
		assert client(task, 2, voidptr(base + u64(positions[0])), voidptr(base + u64(positions[1])), voidptr(base + u64(positions[2])), voidptr(base + u64(positions[3])), voidptr(base + u64(positions[4]))) == 0
		assert C.memcmp(unsafe { &bytes[0] }, unsafe { &expected[0] }, 416) == 0
	} }
}
fn task_ports_test_guard(client TaskPortsTestQuery, task u32) {
	page := usize(C.getpagesize())
	mapping := C.mmap(unsafe { nil }, page * 10, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert mapping != voidptr(-1)
	defer { assert C.munmap(mapping, page * 10) == 0 }
	mut pointers := [5]voidptr{}
	for i in 0 .. 5 {
		pointers[i] = voidptr(u64(mapping) + u64(page) * u64(i * 2 + 1) - 4)
		assert C.mprotect(voidptr(u64(mapping) + u64(page) * u64(i * 2 + 1)), page, C.PROT_NONE) == 0
	}
	assert client(task, 2, pointers[0], pointers[1], pointers[2], pointers[3], pointers[4]) == 0
	values := [u32(2),1,0,0,0]!
	for i in 0 .. 5 { assert read32(u64(pointers[i])) == values[i] }
	assert client(task, 0, voidptr(-1), pointers[1], voidptr(-1), voidptr(-1), voidptr(-1)) == 0
	assert read32(u64(pointers[1])) == 0
	assert client(task, 0xffffffff, voidptr(-1), voidptr(-1), voidptr(-1), voidptr(-1), voidptr(-1)) == 4
}
struct TaskPortsWorker {
	client TaskPortsTestQuery
	task u32
}
fn task_ports_test_worker(context voidptr) voidptr {
	state := unsafe { &TaskPortsWorker(context) }
	for _ in 0 .. 1000 {
		actual := task_ports_test_snapshot(state.client, state.task, 2, 0, 0)
		assert actual.result == 0 && task_ports_test_word(unsafe { &actual }, 96) == 1
		assert task_ports_test_word(unsafe { &actual }, 16) == 2
		$if linux { assert task_ports_test_word(unsafe { &actual }, 176) == 0 && task_ports_test_word(unsafe { &actual }, 256) == 0 && task_ports_test_word(unsafe { &actual }, 336) == 0 }
		task_ports_test_drop(unsafe { &actual }, 0)
	}
	return unsafe { nil }
}
fn test_task_exception_ports() {
	client := unsafe { TaskPortsTestQuery(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_task_get_exception_ports')!)) }
	task_ports_test_error(client, 0, 0x10000003)
	for _ in 0 .. 2 {
		system_data_start()!
		task := system_data.task_self
		$if macos { task_ports_test_native(client, task) }
		$if linux { task_ports_test_default(client, task) }
		task_ports_test_alias(client, task)
		task_ports_test_guard(client, task)
		for name in [u32(0),0xffffffff,0x65432103]! { task_ports_test_error(client, name, 0x10000003) }
		worker := darwin_mach_thread_self()
		host := darwin_mach_host_self()
		mut semaphore := u32(0)
		assert darwin_semaphore_create(task, unsafe { &semaphore }, 0, 1) == 0
		for name in [worker,host,semaphore]! { task_ports_test_error(client, name, 4) }
		assert darwin_semaphore_wait(semaphore) == 0
		mut port := u32(0)
		assert darwin_mach_port_allocate(task, 1, unsafe { &port }) == 0
		task_ports_test_error(client, port, 0x10000003)
		assert darwin_mach_port_insert_right(task, port, port, 20) == 0
		task_ports_test_error(client, port, 46)
		mut references := u32(0)
		assert darwin_mach_port_get_refs(task, port, 0, unsafe { &references }) == 0 && references == 1
		mut handles := [8]u64{}
		state := TaskPortsWorker{client,task}
		for i in 0 .. 8 { assert C.pthread_create(unsafe { voidptr(&handles[i]) }, unsafe { nil }, task_ports_test_worker, unsafe { voidptr(&state) }) == 0 }
		for handle in handles { assert C.pthread_join(voidptr(handle), unsafe { nil }) == 0 }
		image_atfork_start()!
		child := C.ios_fork()
		assert child >= 0
		if child == 0 {
			$if linux { task_ports_test_default(client, task) }
			$if macos { task_ports_test_native(client, task) }
			C._exit(0)
		}
		mut status := i32(-1)
		assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0
		image_atfork_stop()
		assert darwin_mach_port_destroy(task, port) == 0
		assert darwin_semaphore_destroy(task, semaphore) == 0
		assert darwin_mach_port_deallocate(task, worker) == 0 && darwin_mach_port_deallocate(task, host) == 0
		system_data_stop()
		task_ports_test_error(client, task, 0x10000003)
	}
	mut rejected := false; runtime_symbol('/usr/lib/libobjc.A.dylib', '_task_get_exception_ports') or { rejected = true }; assert rejected
	println('IOS-TASK-EXCEPTION-PORTS: native/current-task query, output-only counts, masks and error precedence, exact unaligned/guarded/aliased writes, port ownership, eight threads, fork and two runtimes; Vinix exception handler installation/delivery remains unsupported')
}
