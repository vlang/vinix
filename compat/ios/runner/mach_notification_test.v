// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

$if macos {
	fn C.mach_task_self() u32
	fn C.mach_port_allocate(u32, i32, &u32) i32
	fn C.mach_port_insert_right(u32, u32, u32, u32) i32
	fn C.mach_port_request_notification(u32, u32, i32, u32, u32, u32, &u32) i32
	fn C.mach_port_type(u32, u32, &u32) i32
	fn C.mach_port_get_refs(u32, u32, i32, &u32) i32
	fn C.mach_port_mod_refs(u32, u32, i32, i32) i32
	fn C.mach_port_deallocate(u32, u32) i32
	fn C.mach_port_destroy(u32, u32) i32
	fn C.mach_port_move_member(u32, u32, u32) i32
	fn C.mach_msg(voidptr, u32, u32, u32, u32, u32, u32) i32
}
type MachNotificationCall = fn (u32, u32, i32, u32, u32, u32, &u32) i32
fn mn_task(native bool) u32 { $if macos { if native { return C.mach_task_self() } }; return system_data.task_self }
fn mn_new(native bool, kind i32) u32 {
	mut name := u32(0); $if macos { if native { assert C.mach_port_allocate(mn_task(true), kind, unsafe { &name }) == 0; return name } }
	assert darwin_mach_port_allocate(mn_task(false), kind, unsafe { &name }) == 0; return name
}
fn mn_insert(native bool, name u32) { $if macos { if native { assert C.mach_port_insert_right(mn_task(true), name, name, 20) == 0; return } }; assert darwin_mach_port_insert_right(mn_task(false), name, name, 20) == 0 }
fn mn_type(native bool, name u32, output &u32) i32 { $if macos { if native { return C.mach_port_type(mn_task(true), name, output) } }; return darwin_mach_port_type(mn_task(false), name, output) }
fn mn_refs(native bool, name u32, kind i32) u32 {
	mut refs := u32(777); $if macos { if native { assert C.mach_port_get_refs(mn_task(true), name, kind, unsafe { &refs }) == 0; return refs } }
	assert darwin_mach_port_get_refs(mn_task(false), name, kind, unsafe { &refs }) == 0; return refs
}
fn mn_mod(native bool, name u32, kind i32, delta i32) i32 { $if macos { if native { return C.mach_port_mod_refs(mn_task(true), name, kind, delta) } }; return darwin_mach_port_mod_refs(mn_task(false), name, kind, delta) }
fn mn_drop(native bool, name u32) i32 { $if macos { if native { return C.mach_port_deallocate(mn_task(true), name) } }; return darwin_mach_port_deallocate(mn_task(false), name) }
fn mn_destroy(native bool, name u32) i32 { $if macos { if native { return C.mach_port_destroy(mn_task(true), name) } }; return darwin_mach_port_destroy(mn_task(false), name) }
fn mn_move(native bool, name u32, group u32) { $if macos { if native { assert C.mach_port_move_member(mn_task(true), name, group) == 0; return } }; assert darwin_mach_port_move_member(mn_task(false), name, group) == 0 }
fn mn_request(native bool, name u32, sync u32, notify u32, disposition u32, output &u32) i32 {
	$if macos { if native { return C.mach_port_request_notification(mn_task(true), name, 70, sync, notify, disposition, output) } }
	call := unsafe { MachNotificationCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_mach_port_request_notification') or { panic(err) })) }
	return call(mn_task(false), name, 70, sync, notify, disposition, output)
}
fn mn_arm(native bool, name u32, sync u32, notify u32) u32 { mut previous := u32(777); assert mn_request(native, name, sync, notify, 21, unsafe { &previous }) == 0; return previous }
fn mn_call(native bool, bytes voidptr, flags u32, size u32, limit u32, name u32) i32 { $if macos { if native { return C.mach_msg(bytes, flags, size, limit, name, 0, 0) } }; return darwin_mach_msg(bytes, flags, size, limit, name, 0, 0) }
fn mn_send(native bool, name u32, disposition u32, id u32, flags u32) i32 {
	mut bytes := [disposition, u32(24), name, 0, 0, id]!
	return mn_call(native, unsafe { voidptr(&bytes[0]) }, flags, 24, 0, 0)
}
fn mn_empty(native bool, name u32) { mut bytes := [16]u32{}; assert mn_call(native, unsafe { voidptr(&bytes[0]) }, 0x102, 0, 64, name) == i32(0x10004003) }
fn mn_receive(native bool, name u32, local u32, id u32, count u32, bits u32) {
	mut bytes := [18]u32{}; for i in 0 .. 18 { bytes[i] = 0xa5a5a5a5 }
	assert mn_call(native, unsafe { voidptr(&bytes[1]) }, 0x102, 0, 64, name) == 0
	size := if id == 70 { u32(36) } else { u32(24) }
	assert bytes[1] == bits && bytes[2] == size && bytes[3] == 0 && bytes[4] == local && bytes[5] == 0 && bytes[6] == id
	if id == 70 { assert bytes[7] == 0 && bytes[8] == 1 && bytes[9] == count }
	assert bytes[1 + size / 4] == 0 && bytes[2 + size / 4] == 8
	for i in int(3 + size / 4) .. 18 { assert bytes[i] == 0xa5a5a5a5 }; assert bytes[0] == 0xa5a5a5a5
}

fn mn_lifetime(native bool) {
	for sync in [u32(0), 1, 10]! {
		port := mn_new(native, 1); target := mn_new(native, 1); assert mn_arm(native, port, sync, target) == 0
		if sync == 0 { mn_receive(native, target, target, 70, 0, 0x1200) } else { mn_empty(native, target) }
		mn_insert(native, port); assert mn_drop(native, port) == 0
		if sync != 0 { mn_receive(native, target, target, 70, 1, 0x1200) }; mn_empty(native, target)
		assert mn_arm(native, port, 2, target) == 0; mn_empty(native, target)
		mn_insert(native, port); mn_insert(native, port); assert mn_refs(native, port, 0) == 2
		assert mn_drop(native, port) == 0; mn_empty(native, target); assert mn_mod(native, port, 0, -1) == 0
		mn_receive(native, target, target, 70, 3, 0x1200); mn_empty(native, target)
		assert mn_destroy(native, port) == 0 && mn_destroy(native, target) == 0
	}
	for disposition in [u32(17), 19, 20]! { for flags in [u32(0), 4, 12]! {
		port := mn_new(native, 1); target := mn_new(native, 1)
		if disposition != 20 { mn_insert(native, port) }; assert mn_arm(native, port, 1, target) == 0
		assert mn_send(native, port, disposition, 99, 0x11) == 0
		if disposition == 19 { assert mn_drop(native, port) == 0 }; mn_empty(native, target)
		mut small := [16]u32{}; assert mn_call(native, unsafe { voidptr(&small[0]) }, 0x102 | flags, 0, 24, port) == i32(0x10004004)
		if flags & 4 != 0 { mn_empty(native, target); mn_receive(native, port, port, 99, 0, 0x1100) }
		mn_receive(native, target, target, 70, 1, 0x1200); mn_empty(native, target)
		assert mn_destroy(native, port) == 0 && mn_destroy(native, target) == 0
	}}
	// A timeout returns a user reference and still counts its MAKE_SEND.
	port := mn_new(native, 1); target := mn_new(native, 1); assert mn_arm(native, port, 1, target) == 0
	for id in 0 .. 5 { assert mn_send(native, port, 20, u32(100 + id), 1) == 0 }
	assert mn_send(native, port, 20, 106, 0x11) == i32(0x10000004) && mn_refs(native, port, 0) == 1
	assert mn_drop(native, port) == 0; mn_empty(native, target)
	for id in 0 .. 5 { mn_receive(native, port, port, u32(100 + id), 0, 0x1100) }
	mn_receive(native, target, target, 70, 6, 0x1200)
	assert mn_destroy(native, port) == 0 && mn_destroy(native, target) == 0
}

fn mn_replacement(native bool) {
	port := mn_new(native, 1); target := mn_new(native, 1); assert mn_arm(native, port, 1, target) == 0
	first := mn_arm(native, port, 1, target); second := mn_arm(native, port, 1, 0)
	mut kind := u32(777); assert first != 0 && second != 0 && first != second
	assert mn_type(native, first, unsafe { &kind }) == 0 && kind == 0x40000
	for right in 0 .. 6 { assert mn_refs(native, first, i32(right)) == if right == 2 { u32(1) } else { u32(0) } }
	assert mn_mod(native, first, 2, 0) == 0 && mn_mod(native, first, 2, 1) == 18 && mn_mod(native, first, 2, -2) == 18
	assert mn_drop(native, first) == 0 && mn_destroy(native, second) == 0
	for _ in 0 .. 2 { mn_receive(native, target, target, 71, 0, 0x1200) }; mn_empty(native, target)
	assert mn_arm(native, port, 1, target) == 0; moved := mn_arm(native, port, 1, 0); mut old := u32(777)
	assert mn_request(native, port, 1, moved, 18, unsafe { &old }) == 0 && old == 0
	kind = 777; assert mn_type(native, moved, unsafe { &kind }) == 15 && kind == 777
	mn_insert(native, port); assert mn_drop(native, port) == 0; mn_receive(native, target, target, 70, 1, 0x1200)
	assert mn_arm(native, port, 2, target) == 0 && mn_destroy(native, port) == 0
	mn_receive(native, target, target, 71, 0, 0x1200); assert mn_destroy(native, target) == 0
}

fn mn_pressure_and_death(native bool) {
	port := mn_new(native, 1); target := mn_new(native, 1)
	for id in 0 .. 5 { assert mn_send(native, target, 20, u32(100 + id), 1) == 0 }
	assert mn_arm(native, port, 0, target) == 0
	for id in 0 .. 5 { mn_receive(native, target, target, u32(100 + id), 0, 0x1100) }; mn_receive(native, target, target, 70, 0, 0x1200)
	assert mn_arm(native, port, 1, target) == 0; once := mn_arm(native, port, 1, 0)
	for id in 0 .. 5 { assert mn_send(native, target, 20, u32(100 + id), 1) == 0 }
	assert mn_send(native, once, 18, 99, 0x11) == 0
	for id in 0 .. 5 { mn_receive(native, target, target, u32(100 + id), 0, 0x1100) }; mn_receive(native, target, target, 99, 0, 0x1200); mn_empty(native, target)
	assert mn_send(native, once, 18, 99, 0x11) == i32(0x10000003)
	assert mn_arm(native, port, 1, target) == 0; dead := mn_arm(native, port, 1, target); assert mn_destroy(native, target) == 0
	mut kind := u32(777); assert mn_type(native, dead, unsafe { &kind }) == 0 && kind == 0x100000 && mn_refs(native, dead, 4) == 1
	assert mn_mod(native, dead, 4, 2) == 0 && mn_refs(native, dead, 4) == 3
	for _ in 0 .. 3 { assert mn_drop(native, dead) == 0 }; assert mn_type(native, dead, unsafe { &kind }) == 15
	assert mn_arm(native, port, 1, 0) == 0xffffffff && mn_destroy(native, port) == 0
	owner := mn_new(native, 1); dying := mn_new(native, 1); assert mn_arm(native, owner, 1, dying) == 0
	saturated := mn_arm(native, owner, 1, 0); assert mn_destroy(native, dying) == 0
	assert mn_mod(native, saturated, 4, 65534) == 0 && mn_refs(native, saturated, 4) == 65535
	assert mn_drop(native, saturated) == 0 && mn_refs(native, saturated, 4) == 65535
	assert mn_mod(native, saturated, 4, -65535) == 0 && mn_type(native, saturated, unsafe { &kind }) == 15
	assert mn_destroy(native, owner) == 0
}

fn mn_pending(native bool) {
	for destroy in [false, true]! {
		port := mn_new(native, 1); target := mn_new(native, 1); assert mn_arm(native, port, 1, target) == 0
		for id in 0 .. 5 { assert mn_send(native, port, 20, u32(100 + id), 1) == 0 }
		mut sender := spawn mn_send(native, port, u32(20), u32(105), u32(1))
		if native { time.sleep(40 * time.millisecond) } else {
			mut ready := false; for _ in 0 .. 2000 { C.ios_mach_threads_lock(); state := mach_receive_find(port); ready = state.calls == 1; C.ios_mach_threads_unlock(); if ready { break }; time.sleep(time.millisecond) }; assert ready
		}
		mn_empty(native, target)
		if destroy {
			assert mn_destroy(native, port) == 0 && sender.wait() == 0; mn_receive(native, target, target, 71, 0, 0x1200)
		} else {
			mn_receive(native, port, port, 100, 0, 0x1100); assert sender.wait() == 0
			for id in 1 .. 5 { mn_receive(native, port, port, u32(100 + id), 0, 0x1100) }; mn_empty(native, target)
			mn_receive(native, port, port, 105, 0, 0x1100); mn_receive(native, target, target, 70, 6, 0x1200); assert mn_destroy(native, port) == 0
		}
		mn_empty(native, target); assert mn_destroy(native, target) == 0
	}
}

fn mn_errors(native bool) {
	port := mn_new(native, 1); target := mn_new(native, 1); group := mn_new(native, 3)
	for watched in [u32(0), 0xffffffff, 0x123400, group, port]! { for notify in [u32(0), 0xffffffff, 0x123400, group, target]! {
		mut previous := u32(777); code := mn_request(native, watched, 1, notify, 21, unsafe { &previous })
		expected := if notify == 0xffffffff { i32(20) } else if notify == 0x123400 { i32(15) } else if notify == group { i32(17) } else if watched == 0 || watched == 0xffffffff { i32(4) } else if watched == 0x123400 { i32(15) } else if watched == group { i32(17) } else { i32(0) }
		assert code == expected
		if code == 0 { assert previous == 0 } else { assert previous == 777 }
		if notify == target && code != 0 { mn_receive(native, target, target, 71, 0, 0x1200) } else { mn_empty(native, target) }
	}}
	assert mn_destroy(native, port) == 0; mn_receive(native, target, target, 71, 0, 0x1200)
	assert mn_destroy(native, target) == 0 && mn_destroy(native, group) == 0
}

fn mn_waiter(native bool, group u32, local u32) i32 {
	darwin_set_errno(81); mut bytes := [16]u32{}
	result := mn_call(native, unsafe { voidptr(&bytes[0]) }, 6, 0, 64, group)
	assert result == 0 && bytes[0] == 0x1200 && bytes[1] == 36 && bytes[3] == local && bytes[5] == 70 && bytes[8] == 1
	assert unsafe { *C.ios_errno_address() } == 81; return result
}
fn mn_blocking(native bool) {
	target := mn_new(native, 1); group := mn_new(native, 3); mn_move(native, target, group)
	mut ports := [8]u32{}; mut workers := []thread i32{cap: 8}
	for i in 0 .. 8 { ports[i] = mn_new(native, 1); mn_insert(native, ports[i]); assert mn_arm(native, ports[i], 1, target) == 0; workers << spawn mn_waiter(native, group, target) }
	if native { time.sleep(40 * time.millisecond) } else {
		mut ready := false; for _ in 0 .. 2000 { C.ios_mach_threads_lock(); state := mach_receive_find(group); ready = state.calls == 8; C.ios_mach_threads_unlock(); if ready { break }; time.sleep(time.millisecond) }; assert ready
	}
	mut drops := []thread i32{cap: 8}; for port in ports { drops << spawn mn_drop(native, port) }
	results := drops.wait(); for code in results { assert code == 0 }; replies := workers.wait(); for code in replies { assert code == 0 }
	unsafe { results.free(); replies.free(); drops.free(); workers.free() }
	for port in ports { assert mn_destroy(native, port) == 0 }; assert mn_destroy(native, group) == 0 && mn_destroy(native, target) == 0
}

fn test_mach_notifications() {
	mut retired := u32(0)
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		if retired != 0 { mut kind := u32(777); assert mn_type(false, retired, unsafe { &kind }) == 15 && kind == 777 }
		mn_lifetime(false); mn_replacement(false); mn_pressure_and_death(false); mn_pending(false); mn_errors(false); mn_blocking(false)
		$if macos { mn_lifetime(true); mn_replacement(true); mn_pressure_and_death(true); mn_pending(true); mn_errors(true); mn_blocking(true) }
		assert system_data.send_once == unsafe { nil } && system_data.receive_ports == unsafe { nil }
		port := mn_new(false, 1); target := mn_new(false, 1); mn_insert(false, port)
		assert mn_arm(false, port, 1, target) == 0; retired = mn_arm(false, port, 1, target)
		queued := mn_new(false, 1); assert mn_arm(false, queued, 0, target) == 0
		image_atfork_start()!; child := C.ios_fork(); assert child >= 0
		if child == 0 { assert system_data.send_once == unsafe { nil } && system_data.receive_ports == unsafe { nil }; fresh := mn_new(false, 1); assert mn_arm(false, fresh, 1, fresh) == 0 && mn_destroy(false, fresh) == 0; C._exit(0) }
		mut status := i32(-1); assert C.ios_waitpid(child, unsafe { &status }, 0) == child && status == 0; image_atfork_stop()
		mn_receive(false, target, target, 70, 0, 0x1200); assert mn_drop(false, port) == 0; mn_receive(false, target, target, 70, 1, 0x1200)
		assert mn_drop(false, retired) == 0; mn_receive(false, target, target, 71, 0, 0x1200)
		for name in [port, target, queued]! { assert mn_destroy(false, name) == 0 }
		// Teardown owns a self-subscription, an exported right and queued data.
		remaining := mn_new(false, 1); assert mn_arm(false, remaining, 1, remaining) == 0; retired = mn_arm(false, remaining, 1, remaining)
		assert mn_send(false, remaining, 20, 100, 1) == 0
		mut previous := u32(777); assert darwin_mach_port_request_notification(mn_task(false), remaining, 72, 1, remaining, 21, unsafe { &previous }) == 46 && previous == 777
		assert darwin_mach_port_request_notification(mn_task(false), remaining, 70, 1, remaining, 19, unsafe { &previous }) == 46 && previous == 777
		system_data_stop(); objc_stop(); assert system_data == unsafe { nil }
	}
	for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! { mut rejected := false; runtime_symbol(library, '_mach_port_request_notification') or { rejected = true }; assert rejected }
	println('IOS-MACH-NOTIFICATION: native no-senders ABI, sync and make counts, queued destination rights, large retry/discard, timeout restoration, send-once ownership, replacement/cancellation, full queues, dead targets, eight set waiters, errno, fork and image retirement passed')
}
