// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

$if macos {
	fn C.mach_task_self() u32
	fn C.mach_port_allocate(u32, i32, &u32) i32
	fn C.mach_port_insert_right(u32, u32, u32, u32) i32
	fn C.mach_port_move_member(u32, u32, u32) i32
	fn C.mach_port_destroy(u32, u32) i32
	fn C.mach_port_type(u32, u32, &u32) i32
	fn C.mach_port_get_refs(u32, u32, i32, &u32) i32
	fn C.mach_port_mod_refs(u32, u32, i32, i32) i32
	fn C.mach_port_deallocate(u32, u32) i32
	fn C.mach_msg(voidptr, u32, u32, u32, u32, u32, u32) i32
}

type SetMove = fn (u32, u32, u32) i32
fn ps_task(native bool) u32 { $if macos { if native { return C.mach_task_self() } }; return system_data.task_self }
fn ps_new(native bool, right i32) u32 {
	mut name := u32(0)
	$if macos { if native { assert C.mach_port_allocate(ps_task(true), right, unsafe { &name }) == 0; return name } }
	assert darwin_mach_port_allocate(ps_task(false), right, unsafe { &name }) == 0; return name
}
fn ps_move(native bool, name u32, group u32) i32 {
	$if macos { if native { return C.mach_port_move_member(ps_task(true), name, group) } }
	move := unsafe { SetMove(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_mach_port_move_member') or { panic(err) })) }
	return move(ps_task(false), name, group)
}
fn ps_destroy(native bool, name u32) i32 { $if macos { if native { return C.mach_port_destroy(ps_task(true), name) } }; return darwin_mach_port_destroy(ps_task(false), name) }
fn ps_mod(native bool, name u32, right i32, delta i32) i32 { $if macos { if native { return C.mach_port_mod_refs(ps_task(true), name, right, delta) } }; return darwin_mach_port_mod_refs(ps_task(false), name, right, delta) }
fn ps_drop(native bool, name u32) i32 { $if macos { if native { return C.mach_port_deallocate(ps_task(true), name) } }; return darwin_mach_port_deallocate(ps_task(false), name) }
fn ps_type(native bool, name u32, output &u32) i32 { $if macos { if native { return C.mach_port_type(ps_task(true), name, output) } }; return darwin_mach_port_type(ps_task(false), name, output) }
fn ps_refs(native bool, name u32, right i32) u32 {
	mut refs := u32(777)
	$if macos { if native { assert C.mach_port_get_refs(ps_task(true), name, right, unsafe { &refs }) == 0; return refs } }
	assert darwin_mach_port_get_refs(ps_task(false), name, right, unsafe { &refs }) == 0; return refs
}
fn ps_call(native bool, message voidptr, options u32, size u32, limit u32, name u32, timeout u32) i32 {
	$if macos { if native { return C.mach_msg(message, options, size, limit, name, timeout, 0) } }
	return darwin_mach_msg(message, options, size, limit, name, timeout, 0)
}
fn ps_send(native bool, name u32, id u32, options u32) i32 {
	mut bytes := [u32(20), 24, name, 0, 0, id]!
	return ps_call(native, unsafe { voidptr(&bytes[0]) }, options, 24, 0, 0, 0)
}
fn ps_receive(native bool, name u32, member u32, id u32) {
	mut bytes := [16]u32{}
	assert ps_call(native, unsafe { voidptr(&bytes[0]) }, 0x102, 0, 64, name, 0) == 0
	assert bytes[0] == 0x1100 && bytes[1] == 24 && bytes[2] == 0 && bytes[3] == member && bytes[4] == 0 && bytes[5] == id && bytes[6] == 0 && bytes[7] == 8
}
fn ps_empty(native bool, name u32) {
	mut bytes := [8]u32{}; bytes[0] = 0x12345678
	assert ps_call(native, unsafe { voidptr(&bytes[0]) }, 0x102, 0, 32, name, 0) == i32(0x10004003) && bytes[0] == 0x12345678
}

fn ps_membership(native bool) {
	group := ps_new(native, 3); other := ps_new(native, 3); port := ps_new(native, 1); second := ps_new(native, 1)
	mut kind := u32(777); assert ps_type(native, group, unsafe { &kind }) == 0 && kind == 0x80000
	for right in 0 .. 6 { assert ps_refs(native, group, i32(right)) == if right == 3 { u32(1) } else { u32(0) } }
	for right in [i32(0), 1, 2, 4, 5]! { assert ps_mod(native, group, right, 0) == 17 }
	assert ps_mod(native, group, 3, 0) == 0 && ps_mod(native, group, 3, 1) == 18 && ps_mod(native, group, 3, -2) == 18
	assert ps_move(native, 0, group) == 17 && ps_move(native, 0xffffffff, group) == 17
	assert ps_move(native, group, group) == 17 && ps_move(native, port, port) == 17
	assert ps_move(native, port, 0x123400) == 15 && ps_move(native, 0x123400, group) == 15
	assert ps_move(native, group, 0x123400) == 15 && ps_move(native, 0, 0x123400) == 17 && ps_move(native, port, 0xffffffff) == 17
	assert ps_move(native, port, 0) == 12 && ps_move(native, port, group) == 0 && ps_move(native, port, group) == 0
	assert ps_send(native, port, 1, 0x11) == 0; ps_receive(native, port, port, 1); ps_empty(native, group)
	assert ps_move(native, second, group) == 0
	for id in [u32(11), 12]! { assert ps_send(native, port, id, 0x11) == 0 }
	for id in [u32(13), 14]! { assert ps_send(native, second, id, 0x11) == 0 }
	for pair in [[port, u32(11)]!, [second, u32(13)]!, [port, u32(12)]!, [second, u32(14)]!]! { ps_receive(native, group, pair[0], pair[1]) }
	assert ps_send(native, port, 21, 0x11) == 0 && ps_move(native, port, other) == 0
	ps_empty(native, group); ps_receive(native, other, port, 21)
	assert ps_move(native, port, 0) == 0 && ps_move(native, port, 0) == 12
	assert ps_move(native, port, other) == 0 && ps_destroy(native, other) == 0
	assert ps_move(native, port, 0) == 12 && ps_send(native, port, 22, 0x11) == 0; ps_receive(native, port, port, 22)
	assert ps_destroy(native, second) == 0; ps_empty(native, group)
	assert ps_mod(native, group, 3, -1) == 0; kind = 777; assert ps_type(native, group, unsafe { &kind }) == 15 && kind == 777
	assert ps_destroy(native, port) == 0
	deallocated := ps_new(native, 3); assert ps_drop(native, deallocated) == 0; assert ps_type(native, deallocated, unsafe { &kind }) == 15
}

// Compare every output byte, including partial trailers and untouched guards.
fn ps_extents(native bool) {
	group := ps_new(native, 3); port := ps_new(native, 1); assert ps_move(native, port, group) == 0
	for size in [u32(24), 28, 36, 64]! { for limit in [u32(0), 8, 23, 24, 25, 28, 31, 32, 64, 72]! { for flags in [u32(0), 4, 12]! {
		mut input := [64]u32{}; for i in 0 .. 64 { input[i] = u32(i) + 0x80000000 }; input[0] = 20; input[1] = size; input[2] = port; input[3] = 0; input[4] = 0
		assert ps_call(native, unsafe { voidptr(&input[0]) }, 0x11, size, 0, 0, 0) == 0
		mut output := [66]u32{}; mut expected := [64]u32{}; for i in 0 .. 66 { output[i] = 0xa5a5a5a5 }; for i in 0 .. 64 { expected[i] = 0xa5a5a5a5 }
		large := limit < size + 8; result := ps_call(native, unsafe { voidptr(&output[1]) }, 0x102 | flags, 0, limit, group, 0)
		if large && flags & 4 != 0 {
			assert result == i32(0x10004004); if limit >= 8 { expected[1] = size }; if flags & 8 != 0 && limit >= 16 { expected[3] = port }
		} else if limit < 24 { assert result == i32(0x10004008) }
		else {
			length := if large { u32(24) } else { size }; assert result == if large { i32(0x10004004) } else { i32(0) }
			for i in 0 .. int(length / 4) { expected[i] = input[i] }; expected[0] = 0x1100; expected[1] = length; expected[2] = 0; expected[3] = port; expected[4] = 0
			mut trailer := [u32(0), 8]!; count := if limit - length < 8 { limit - length } else { u32(8) }
			unsafe { C.memcpy(voidptr(u64(&expected[0]) + u64(length)), voidptr(&trailer[0]), usize(count)) }
		}
		assert output[0] == 0xa5a5a5a5 && output[65] == 0xa5a5a5a5
		assert C.memcmp(unsafe { voidptr(&output[1]) }, unsafe { voidptr(&expected[0]) }, 256) == 0, 'native=${native} size=${size} limit=${limit} flags=${flags}'
		if large && flags & 4 != 0 { mut retry := [64]u32{}; assert ps_call(native, unsafe { voidptr(&retry[0]) }, 0x102, 0, 256, group, 0) == 0 && retry[1] == size && retry[3] == port }
		ps_empty(native, group)
	}}}
	assert ps_destroy(native, group) == 0 && ps_destroy(native, port) == 0
}

fn ps_selection(native bool) {
	group := ps_new(native, 3); port := ps_new(native, 1); second := ps_new(native, 1)
	assert ps_move(native, port, group) == 0 && ps_move(native, second, group) == 0
	for direct in [false, true]! {
		mut large := [u32(20), 36, port, 0, 0, 1, 0, 0, 0]!
		assert ps_call(native, unsafe { voidptr(&large[0]) }, 0x11, 36, 0, 0, 0) == 0 && ps_send(native, second, 2, 0x11) == 0
		mut output := [16]u32{}
		assert ps_call(native, unsafe { voidptr(&output[0]) }, 0x10e, 0, 32, if direct { port } else { group }, 0) == i32(0x10004004)
		assert output[1] == 36 && output[3] == port
		ps_receive(native, group, second, 2)
		assert ps_call(native, unsafe { voidptr(&output[0]) }, 0x102, 0, 64, group, 0) == 0 && output[1] == 36 && output[3] == port && output[5] == 1
	}
	assert ps_move(native, port, 0) == 0 && ps_move(native, second, 0) == 0
	assert ps_send(native, port, 3, 1) == 0 && ps_send(native, second, 4, 1) == 0
	assert ps_move(native, second, group) == 0 && ps_move(native, port, group) == 0
	ps_receive(native, group, second, 4); ps_receive(native, group, port, 3)
	assert ps_destroy(native, group) == 0 && ps_destroy(native, port) == 0 && ps_destroy(native, second) == 0
}

fn ps_waiter(native bool, group u32) i32 {
	darwin_set_errno(83); mut bytes := [16]u32{}; result := ps_call(native, unsafe { voidptr(&bytes[0]) }, 6, 0, 64, group, 0)
	assert unsafe { *C.ios_errno_address() } == 83
	if result == 0 { assert bytes[5] == 0xdeadbeef }; return result
}
fn ps_sender(native bool, port u32) i32 { return ps_send(native, port, 99, 1) }
fn ps_wait_calls(native bool, name u32, wanted u64) {
	if native { time.sleep(40 * time.millisecond); return }
	for _ in 0 .. 2000 {
		C.ios_mach_threads_lock(); port := mach_receive_find(name); calls := if port == unsafe { nil } { u64(0) } else { port.calls }; C.ios_mach_threads_unlock()
		if calls >= wanted { return }; time.sleep(time.millisecond)
	}; panic('port set callers failed to wait')
}
fn ps_blocking(native bool) {
	group := ps_new(native, 3); port := ps_new(native, 1); other := ps_new(native, 1)
	assert ps_move(native, port, group) == 0
	mut waiters := []thread i32{cap: 16}; for _ in 0 .. 8 { waiters << spawn ps_waiter(native, group) }; ps_wait_calls(native, group, 8)
	for _ in 0 .. 8 { waiters << spawn ps_waiter(native, port) }; ps_wait_calls(native, port, 8)
	for _ in 0 .. 16 { assert ps_send(native, port, 0xdeadbeef, 1) == 0 }
	results := waiters.wait(); for result in results { assert result == 0 }; unsafe { results.free(); waiters.free() }
	// Moving an already nonempty queue into a set must wake its receiver.
	mut moving := spawn ps_waiter(native, group); ps_wait_calls(native, group, 1)
	assert ps_move(native, port, 0) == 0 && ps_destroy(native, port) == 0
	assert ps_send(native, other, 0xdeadbeef, 1) == 0 && ps_move(native, other, group) == 0 && moving.wait() == 0
	// Draining through the set releases pressure on the member queue.
	for id in 0 .. 5 { assert ps_send(native, other, u32(id), 1) == 0 }
	mut sender := spawn ps_sender(native, other); ps_wait_calls(native, other, 1)
	ps_receive(native, group, other, 0); assert sender.wait() == 0
	for id in 1 .. 5 { ps_receive(native, group, other, u32(id)) }; ps_receive(native, group, other, 99)
	assert ps_destroy(native, other) == 0
	for disposal in 0 .. 3 {
		ending := if disposal == 0 { group } else { ps_new(native, 3) }
		mut blocked := []thread i32{cap: 8}; for _ in 0 .. 8 { blocked << spawn ps_waiter(native, ending) }; ps_wait_calls(native, ending, 8)
		assert if disposal == 0 { ps_destroy(native, ending) == 0 } else if disposal == 1 { ps_mod(native, ending, 3, -1) == 0 } else { ps_drop(native, ending) == 0 }
		codes := blocked.wait(); for code in codes { assert code == i32(0x10004006) || (native && code == i32(0x10004002)) }; unsafe { codes.free(); blocked.free() }
		// Set retirement preserves both queued packets and a blocked sender.
		preserved := ps_new(native, 3); member := ps_new(native, 1); assert ps_move(native, member, preserved) == 0
		for id in 0 .. 5 { assert ps_send(native, member, u32(id), 1) == 0 }
		mut pending := spawn ps_sender(native, member); ps_wait_calls(native, member, 1)
		assert if disposal == 0 { ps_destroy(native, preserved) == 0 } else if disposal == 1 { ps_mod(native, preserved, 3, -1) == 0 } else { ps_drop(native, preserved) == 0 }
		ps_receive(native, member, member, 0); assert pending.wait() == 0
		for id in 1 .. 5 { ps_receive(native, member, member, u32(id)) }; ps_receive(native, member, member, 99)
		assert ps_destroy(native, member) == 0
	}
}

fn test_mach_port_sets() {
	mut retired := u32(0)
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		if retired != 0 { mut kind := u32(777); assert ps_type(false, retired, unsafe { &kind }) == 15 && kind == 777 }
		ps_membership(false); ps_extents(false); ps_selection(false); ps_blocking(false)
		$if macos { ps_membership(true); ps_extents(true); ps_selection(true); ps_blocking(true) }
		assert system_data.receive_ports == unsafe { nil }
		group := ps_new(false, 3); port := ps_new(false, 1); full := ps_new(false, 1); assert ps_move(false, port, group) == 0 && ps_move(false, full, group) == 0
		assert ps_send(false, group, 1, 0x11) == i32(0x10000003) && ps_refs(false, group, 0) == 0
		assert darwin_mach_port_insert_right(ps_task(false), group, group, 20) == 17
		assert darwin_mach_port_move_member(0, port, group) == 4 && darwin_mach_port_move_member(ps_task(false), ps_task(false), group) == 17
		assert darwin_host_statistics(group, 2, unsafe { nil }, unsafe { nil }) == i32(0x10000003)
		assert darwin_exception_raise(group, ps_task(false), ps_task(false), 1, unsafe { nil }, 0) == i32(0x10000003)
		mut waiter := spawn ps_waiter(false, group); ps_wait_calls(false, group, 1)
		// Freeze a waiting set, membership, queued data and a blocked sender.
		assert ps_move(false, full, 0) == 0; for id in 0 .. 5 { assert ps_send(false, full, u32(id), 1) == 0 }
		mut sender := spawn ps_sender(false, full); ps_wait_calls(false, full, 1)
		image_atfork_start()!; child := C.ios_fork(); assert child >= 0
		if child == 0 { assert system_data.receive_ports == unsafe { nil }; mut kind := u32(777); assert ps_type(false, group, unsafe { &kind }) == 15; fresh := ps_new(false, 3); assert ps_drop(false, fresh) == 0; C._exit(0) }
		mut status := i32(-1); assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0; image_atfork_stop()
		assert ps_send(false, port, 0xdeadbeef, 1) == 0 && waiter.wait() == 0
		assert ps_move(false, full, group) == 0; ps_receive(false, group, full, 0); assert sender.wait() == 0
		for id in 1 .. 5 { ps_receive(false, group, full, u32(id)) }; ps_receive(false, group, full, 99)
		assert ps_destroy(false, group) == 0 && ps_destroy(false, port) == 0 && ps_destroy(false, full) == 0
		retired = ps_new(false, 3); survivor := ps_new(false, 1); assert ps_move(false, survivor, retired) == 0 && ps_send(false, survivor, 1, 1) == 0
		system_data_stop(); objc_stop(); assert system_data == unsafe { nil }
	}
	for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! { mut rejected := false; runtime_symbol(library, '_mach_port_move_member') or { rejected = true }; assert rejected }
	println('IOS-MACH-PORT-SET: native rights and membership, ready queue rotation, member identity and guarded extents, large retry, eight set plus eight direct receivers, queue pressure, move/destroy wakeups, preserved member queues and senders, errno, fork and image retirement passed')
}
