// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

$if macos {
	fn C.mach_task_self() u32
	fn C.mach_port_allocate(u32, i32, &u32) i32
	fn C.mach_port_insert_right(u32, u32, u32, u32) i32
	fn C.mach_port_destroy(u32, u32) i32
	fn C.mach_port_get_refs(u32, u32, i32, &u32) i32
	fn C.mach_port_mod_refs(u32, u32, i32, i32) i32
	fn C.mach_port_type(u32, u32, &u32) i32
	fn C.mach_port_deallocate(u32, u32) i32
	fn C.mach_msg(voidptr, u32, u32, u32, u32, u32, u32) i32
}

type MachMsgCall = fn (voidptr, u32, u32, u32, u32, u32, u32) i32
type MachPortAllocate = fn (u32, i32, &u32) i32
type MachPortInsert = fn (u32, u32, u32, u32) i32
type MachPortDestroy = fn (u32, u32) i32
__global mm_ready = [8]u64{}

fn mm_task(native bool) u32 { $if macos { if native { return C.mach_task_self() } }; return system_data.task_self }
fn mm_call(native bool, bytes voidptr, options u32, send_size u32, limit u32, name u32, timeout u32) i32 {
	$if macos { if native { return C.mach_msg(bytes, options, send_size, limit, name, timeout, 0) } }
	call := unsafe { MachMsgCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_mach_msg') or { panic(err) })) }
	return call(bytes, options, send_size, limit, name, timeout, 0)
}
fn mm_new(native bool, send_right bool) u32 {
	mut port := u32(0)
	$if macos { if native { assert C.mach_port_allocate(mm_task(true), 1, unsafe { &port }) == 0; if send_right { assert C.mach_port_insert_right(mm_task(true), port, port, 20) == 0 }; return port } }
	allocate := unsafe { MachPortAllocate(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_mach_port_allocate') or { panic(err) })) }
	insert := unsafe { MachPortInsert(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_mach_port_insert_right') or { panic(err) })) }
	assert allocate(mm_task(false), 1, unsafe { &port }) == 0
	if send_right { assert insert(mm_task(false), port, port, 20) == 0 }; return port
}
fn mm_destroy(native bool, name u32) i32 {
	$if macos { if native { return C.mach_port_destroy(mm_task(true), name) } }
	destroy := unsafe { MachPortDestroy(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_mach_port_destroy') or { panic(err) })) }; return destroy(mm_task(false), name)
}
fn mm_refs(native bool, name u32, right i32) u32 {
	mut refs := u32(777)
	$if macos { if native { assert C.mach_port_get_refs(mm_task(true), name, right, unsafe { &refs }) == 0; return refs } }
	assert darwin_mach_port_get_refs(mm_task(false), name, right, unsafe { &refs }) == 0; return refs
}
fn mm_mod(native bool, name u32, right i32, delta i32) i32 {
	$if macos { if native { return C.mach_port_mod_refs(mm_task(true), name, right, delta) } }
	return darwin_mach_port_mod_refs(mm_task(false), name, right, delta)
}
fn mm_type(native bool, name u32) u32 {
	mut kind := u32(777)
	$if macos { if native { assert C.mach_port_type(mm_task(true), name, unsafe { &kind }) == 0; return kind } }
	assert darwin_mach_port_type(mm_task(false), name, unsafe { &kind }) == 0; return kind
}
fn mm_send(native bool, port u32, id u32, options u32) i32 {
	mut message := [u32(19), 24, port, 0, 0, id]!
	return mm_call(native, unsafe { voidptr(&message[0]) }, options, 24, 0, 0, 0)
}
fn mm_receive(native bool, port u32, expected u32) {
	mut message := [16]u32{}
	assert mm_call(native, unsafe { voidptr(&message[0]) }, 0x102, 0, 64, port, 0) == 0
	assert message[0] == 0x1100 && message[1] == 24 && message[2] == 0 && message[3] == port && message[4] == 0 && message[5] == expected && message[6] == 0 && message[7] == 8
}

fn mm_extents(native bool) {
	for size in [u32(24), 28, 36, 64]! { for limit in [u32(0), 8, 23, 24, 25, 27, 28, 31, 32, 35, 36, 64, 72, 128]! { for large in [u32(0), 4, 12]! {
		port := mm_new(native, true); mut input := [64]u32{}
		for i in 0 .. 64 { input[i] = 0x80000000 + u32(i) }; input[0] = 19; input[1] = 0x12345678; input[2] = port; input[3] = 0; input[4] = 0; input[5] = 0xdeadbeef
		before := input
		assert mm_call(native, unsafe { voidptr(&input[0]) }, 0x11, size, 0, 0, 0) == 0 && input == before
		mut output := [66]u32{}; mut expected := [64]u32{}
		for i in 0 .. 66 { output[i] = 0xa5a5a5a5 }; for i in 0 .. 64 { expected[i] = 0xa5a5a5a5 }
		oversized := limit < size + 8
		result := mm_call(native, unsafe { voidptr(&output[1]) }, 0x102 | large, 0, limit, port, 0)
		if oversized && large & 4 != 0 {
			assert result == i32(0x10004004)
			if limit >= 8 { expected[1] = size }; if large & 8 != 0 && limit >= 16 { expected[3] = port }
		} else if limit < 24 { assert result == i32(0x10004008) }
		else {
			assert result == if oversized { i32(0x10004004) } else { i32(0) }
			length := if oversized { u32(24) } else { size }
			for i in 0 .. int(length / 4) { expected[i] = input[i] }
			expected[0] = 0x1100; expected[1] = length; expected[2] = 0; expected[3] = port; expected[4] = 0
			mut trailer := [u32(0), 8]!
			count := if limit - length < 8 { limit - length } else { u32(8) }
			unsafe { C.memcpy(voidptr(u64(&expected[0]) + u64(length)), voidptr(&trailer[0]), usize(count)) }
		}
		assert output[0] == 0xa5a5a5a5 && output[65] == 0xa5a5a5a5
		assert C.memcmp(unsafe { voidptr(&output[1]) }, unsafe { voidptr(&expected[0]) }, 256) == 0, 'native=${native} size=${size} limit=${limit} large=${large} result=${u32(result).hex()}'
		mut next := [64]u32{}; next_result := mm_call(native, unsafe { voidptr(&next[0]) }, 0x102, 0, 256, port, 0)
		if oversized && large & 4 != 0 { assert next_result == 0 && next[1] == size && next[5] == 0xdeadbeef }
		else { assert next_result == i32(0x10004003) }
		assert mm_destroy(native, port) == 0
	}}}
}

fn mm_rights_and_pressure(native bool) {
	port := mm_new(native, true); assert mm_type(native, port) == 0x30000 && mm_refs(native, port, 0) == 1 && mm_refs(native, port, 1) == 1
	for id in 0 .. 5 { assert mm_send(native, port, u32(id), 0x11) == 0 }
	mut failed := [u32(19), 0x12345678, port, 0, 0, 77]!
	assert mm_call(native, unsafe { voidptr(&failed[0]) }, 0x11, 24, 0, 0, 0) == i32(0x10000004)
	assert failed[0] == 17 && failed[1] == 24 && failed[2] == port && failed[5] == 77 && mm_refs(native, port, 0) == 2
	assert mm_call(native, unsafe { voidptr(&failed[0]) }, 0x11, 24, 0, 0, 0) == i32(0x10000004) && mm_refs(native, port, 0) == 2
	for id in 0 .. 5 { mm_receive(native, port, u32(id)) }
	assert mm_call(native, unsafe { voidptr(&failed[0]) }, 0x11, 24, 0, 0, 0) == 0 && mm_refs(native, port, 0) == 1
	mm_receive(native, port, 77)
	assert mm_mod(native, port, 0, -1) == 0 && mm_type(native, port) == 0x20000
	assert mm_send(native, port, 88, 0x11) == i32(0x10000003)
	mut make := [u32(20), 24, port, 0, 0, 89]!
	assert mm_call(native, unsafe { voidptr(&make[0]) }, 0x11, 24, 0, 0, 0) == 0 && mm_refs(native, port, 0) == 0
	mm_receive(native, port, 89)
	assert mm_mod(native, port, 1, -1) == 0
	retained := mm_new(native, true); assert mm_mod(native, retained, 1, -1) == 0
	assert mm_type(native, retained) == 0x100000 && mm_refs(native, retained, 4) == 1
	assert mm_mod(native, retained, 4, -1) == 0
	port2 := mm_new(native, true); mut untouched := [16]u32{}
	start := darwin_mach_absolute_time()
	assert mm_call(native, unsafe { voidptr(&untouched[0]) }, 0x102, 0, 64, port2, 25) == i32(0x10004003)
	elapsed := darwin_mach_absolute_time() - start; assert elapsed >= 15_000_000 && elapsed < 5_000_000_000
	// The send completes even if the receive half subsequently fails.
	untouched[0] = 19; untouched[1] = 24; untouched[2] = port2; untouched[5] = 91
	assert mm_call(native, unsafe { voidptr(&untouched[0]) }, 3, 24, 64, 0, 0) == i32(0x10004002); mm_receive(native, port2, 91)
	assert mm_destroy(native, port2) == 0
}

fn mm_waiter(native bool, port u32, index int) i32 {
	darwin_set_errno(80 + index); C.ios_store_pointer(unsafe { &mm_ready[index] }, 1)
	mut message := [16]u32{}; result := mm_call(native, unsafe { voidptr(&message[0]) }, 6, 0, 64, port, 0)
	assert unsafe { *C.ios_errno_address() } == 80 + index
	if result == 0 { assert message[5] == 0xdeadbeef }; return result
}
fn mm_sender(native bool, port u32) i32 { C.ios_store_pointer(unsafe { &mm_ready[0] }, 1); return mm_send(native, port, 99, 1) }
fn mm_wait_calls(native bool, port u32, wanted u64) {
	if native { time.sleep(40 * time.millisecond); return }
	for _ in 0 .. 2000 {
		C.ios_mach_threads_lock(); state := mach_receive_find(port); count := if state == unsafe { nil } { u64(0) } else { state.calls }; C.ios_mach_threads_unlock()
		if count >= wanted { return }; time.sleep(time.millisecond)
	}; panic('message callers failed to wait')
}
fn mm_blocking(native bool) {
	port := mm_new(native, true); mut receivers := []thread i32{cap: 8}
	for i in 0 .. 8 { C.ios_store_pointer(unsafe { &mm_ready[i] }, 0); receivers << spawn mm_waiter(native, port, i) }
	mm_wait_calls(native, port, 8)
	for _ in 0 .. 8 { assert mm_send(native, port, 0xdeadbeef, 1) == 0 }
	results := receivers.wait(); for result in results { assert result == 0 }; unsafe { results.free(); receivers.free() }
	assert mm_destroy(native, port) == 0
	for dying in [false, true]! {
		pending := mm_new(native, true); mut waiters := []thread i32{cap: 8}
		for i in 0 .. 8 { waiters << spawn mm_waiter(native, pending, i) }; mm_wait_calls(native, pending, 8)
		assert if dying { mm_mod(native, pending, 1, -1) == 0 } else { mm_destroy(native, pending) == 0 }
		codes := waiters.wait(); for code in codes { assert code == i32(0x10004006) || (native && code == i32(0x10004002)), 'native=${native} dying=${dying} result=${u32(code).hex()}' }; unsafe { codes.free(); waiters.free() }
		if dying { assert mm_destroy(native, pending) == 0 }
	}
	for retire in [false, true]! {
		full := mm_new(native, true); for id in 0 .. 5 { assert mm_send(native, full, u32(id), 1) == 0 }
		mut sender := spawn mm_sender(native, full); mm_wait_calls(native, full, 1)
		if retire { assert mm_destroy(native, full) == 0; assert sender.wait() == 0 }
		else { mm_receive(native, full, 0); assert sender.wait() == 0; for id in 1 .. 5 { mm_receive(native, full, u32(id)) }; mm_receive(native, full, 99); assert mm_destroy(native, full) == 0 }
	}
}

fn test_mach_messages() {
	assert darwin_mach_msg(unsafe { nil }, 0, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff) == 0
	mut retired := u32(0)
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		if retired != 0 { mut kind := u32(777); assert darwin_mach_port_type(mm_task(false), retired, unsafe { &kind }) == 15 && kind == 777 }
		mm_extents(false); mm_rights_and_pressure(false); mm_blocking(false)
		$if macos { mm_extents(true); mm_rights_and_pressure(true); mm_blocking(true) }
		assert system_data.receive_ports == unsafe { nil }
		port := mm_new(false, true)
		assert darwin_host_statistics(port, 2, unsafe { nil }, unsafe { nil }) == 46
		assert darwin_exception_raise(port, mm_task(false), mm_task(false), 1, unsafe { nil }, 0) == 46
		assert darwin_semaphore_signal(port) == 20 && darwin_semaphore_destroy(mm_task(false), port) == 4
		mut bytes := [u32(19), 24, port, 0, 0, 0, 0, 0]!
		assert mm_call(false, unsafe { voidptr(&bytes[0]) }, 0x102, 0, 32, mm_task(false), 0) == i32(0x10004002)
		assert mm_call(false, unsafe { voidptr(&bytes[0]) }, 0x11, 25, 0, 0, 0) == i32(0x10000008)
		assert mm_call(false, unsafe { voidptr(&bytes[0]) }, 0x11, 65540, 0, 0, 0) == i32(0x1000000e)
		bytes[0] = 0x80000013; assert mm_call(false, unsafe { voidptr(&bytes[0]) }, 0x11, 24, 0, 0, 0) == i32(0x10000013)
		bytes[0] = 19; bytes[3] = port; assert mm_call(false, unsafe { voidptr(&bytes[0]) }, 0x11, 24, 0, 0, 0) == i32(0x10000013)
		bytes[3] = 0; bytes[2] = mm_task(false); assert mm_call(false, unsafe { voidptr(&bytes[0]) }, 0x11, 24, 0, 0, 0) == i32(0x10000013)
		assert mm_refs(false, port, 0) == 1
		// Fork with one blocked receiver and a queued packet on another port.
		mut worker := spawn mm_waiter(false, port, 0); mm_wait_calls(false, port, 1)
		queued := mm_new(false, true); assert mm_send(false, queued, 123, 1) == 0
		full := mm_new(false, true); for id in 0 .. 5 { assert mm_send(false, full, u32(id), 1) == 0 }
		mut pending_sender := spawn mm_sender(false, full); mm_wait_calls(false, full, 1)
		C.ios_mach_threads_lock(); state := mach_receive_find(full); assert state != unsafe { nil }
		assert C.pthread_mutex_lock(state.guard) == 0; assert state.pending != unsafe { nil } && state.count == 5
		C.pthread_mutex_unlock(state.guard); C.ios_mach_threads_unlock()
		image_atfork_start()!; child := C.ios_fork(); assert child >= 0
		if child == 0 { assert system_data.receive_ports == unsafe { nil }; mut kind := u32(777); assert darwin_mach_port_type(mm_task(false), port, unsafe { &kind }) == 15; fresh := mm_new(false, true); assert mm_destroy(false, fresh) == 0; C._exit(0) }
		mut status := i32(-1); assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0; image_atfork_stop()
		assert mm_send(false, port, 0xdeadbeef, 1) == 0 && worker.wait() == 0; assert mm_destroy(false, port) == 0
		mm_receive(false, queued, 123); assert mm_destroy(false, queued) == 0
		mm_receive(false, full, 0); assert pending_sender.wait() == 0
		for id in 1 .. 5 { mm_receive(false, full, u32(id)) }; mm_receive(false, full, 99); assert mm_destroy(false, full) == 0
		// Image retirement owns both live port objects and queued packets.
		retired = mm_new(false, true); assert mm_send(false, retired, 101, 1) == 0
		system_data_stop(); objc_stop(); assert system_data == unsafe { nil }
	}
	for symbol in ['_mach_msg', '_mach_port_allocate', '_mach_port_insert_right', '_mach_port_destroy']! {
		for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! { mut rejected := false; runtime_symbol(library, symbol) or { rejected = true }; assert rejected }
	}
	println('IOS-MACH-MESSAGE: native inline ABI and trailers, guarded output extents, large retry/discard, FIFO queue pressure and pseudo-received references, blocking send/receive, eight waiters, destruction, errno, fork and image retirement passed')
}
