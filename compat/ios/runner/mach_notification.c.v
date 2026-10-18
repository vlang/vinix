// SPDX-License-Identifier: GPL-2.0-or-later
module main

// A subscription owns an internal send-once right. Replacement transfers that
// same right into the public namespace; cancellation/deallocation sends ID 71.
// Reserve its packet at creation so firing a notification never allocates.
struct MachSendOnce {
mut:
	next &MachSendOnce = unsafe { nil }
	name u32
	refs u32 = 1
	target &MachReceivePort = unsafe { nil }
	packet &MachInlineMessage = unsafe { nil }
}

__global mach_send_once_next_name = u64(0x70000117)

fn mach_send_once_known(name u32) bool {
	return name >= 0x70000117 && u64(name) < C.ios_load_pointer(unsafe { &mach_send_once_next_name }) && name & 0xff == 23
}

// Namespace lock is held for every right/subscription operation below.
fn mach_send_once_find(name u32) &MachSendOnce {
	if system_data == unsafe { nil } || name == 0 { return unsafe { nil } }
	mut right := system_data.send_once
	for right != unsafe { nil } { if right.name == name { return right }; right = right.next }
	return unsafe { nil }
}

fn mach_send_once_new(mut target MachReceivePort) ?&MachSendOnce {
	mut right := unsafe { &MachSendOnce(C.calloc(1, sizeof(MachSendOnce))) }; if right == unsafe { nil } { return none }
	mut packet := unsafe { &MachInlineMessage(C.malloc(usize(sizeof(MachInlineMessage)) + 36)) }
	if packet == unsafe { nil } { C.free(right); return none }
	unsafe { *packet = MachInlineMessage{bytes: voidptr(u64(packet) + u64(sizeof(MachInlineMessage))), receive_bits: 0x1200} }
	unsafe { *right = MachSendOnce{target: target, packet: packet, next: system_data.send_once} }
	system_data.send_once = right; target.notice_refs++
	return right
}

fn mach_send_once_free(mut right MachSendOnce) {
	mut link := unsafe { &system_data.send_once }
	for unsafe { voidptr(*link) } != voidptr(right) {
		if unsafe { *link } == unsafe { nil } { panic('iOS: missing send-once right') }
		link = unsafe { &(*link).next }
	}
	unsafe { *link = right.next }
	if right.target.notice_refs == 0 { panic('iOS: notification target reference underflow') }
	right.target.notice_refs--
	C.free(right.packet); C.free(right)
}

fn mach_send_once_emit(mut right MachSendOnce, id u32, count u32) {
	mut target := right.target
	if target.receive {
		mut packet := right.packet; right.packet = unsafe { nil }
		packet.size = if id == 70 { u32(36) } else { u32(24) }
		mut words := [u32(0x1200), packet.size, 0, target.name, 0, id, 0, 1, count]!
		unsafe { C.memcpy(packet.bytes, voidptr(&words[0]), usize(packet.size)) }
		if C.pthread_mutex_lock(target.guard) != 0 { panic('iOS: cannot queue port notification') }
		if target.tail == unsafe { nil } { target.head = packet; target.ready_order = mach_receive_next_order() } else { target.tail.next = packet }
		target.tail = packet; target.count++
		if C.pthread_cond_broadcast(target.changed) != 0 { panic('iOS: cannot wake notification receiver') }
		C.pthread_mutex_unlock(target.guard)
		// Kernel and send-once messages bypass the ordinary queue limit.
		mach_port_set_notify_locked(target)
	}
	mach_send_once_free(mut right)
}

fn mach_send_transit_drop(mut port MachReceivePort) {
	if C.ios_ref_change(unsafe { &port.transit }, -1) <= 0 { panic('iOS: in-transit send reference underflow') }
}

// Dequeue holds only the queue guard. Keep its destination right until this
// namespace-locked release, so a concurrent MAKE_SEND cannot slip between the
// last-right transition and notification delivery. Concurrent completions added
// after the snapshot remain for their callers; no queue guard is acquired here.
fn mach_send_complete(mut port MachReceivePort) {
	count := C.ios_ref_change(unsafe { &port.completed }, 0)
	if count == 0 { return }
	if count < 0 { panic('iOS: completed send reference underflow') }
	C.ios_ref_change(unsafe { &port.completed }, -count)
	if C.ios_ref_change(unsafe { &port.transit }, -count) < count { panic('iOS: in-transit send reference underflow') }
}

fn mach_no_senders_check(mut port MachReceivePort) {
	if !port.receive || port.is_set || port.refs != 0 || C.ios_ref_change(unsafe { &port.transit }, 0) != 0 || !port.had_senders { return }
	port.had_senders = false
	if port.notification != unsafe { nil } {
		mut right := port.notification; port.notification = unsafe { nil }
		mach_send_once_emit(mut right, 70, port.make_send_count)
	}
}

fn mach_send_once_export(mut right MachSendOnce) u32 {
	if !right.target.receive { mach_send_once_free(mut right); return 0xffffffff }
	next := C.ios_load_pointer(unsafe { &mach_send_once_next_name })
	if next >= 0xffffffff { panic('iOS: send-once namespace exhausted') }
	right.name = u32(next); C.ios_store_pointer(unsafe { &mach_send_once_next_name }, next + 0x100)
	return right.name
}

fn darwin_mach_port_request_notification(task u32, name u32, id i32, sync u32, notify u32, disposition u32, previous &u32) i32 {
	saved_errno := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(saved_errno) }
	if system_data == unsafe { nil } || task != system_data.task_self || previous == unsafe { nil } { return 4 }
	// Other notification families and polymorphic send-right descriptors need
	// separate transport semantics; reject them before consuming a descriptor.
	if id != 70 || (disposition != 18 && disposition != 21) { return 46 }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	mut acquired := unsafe { &MachSendOnce(nil) }
	if notify == 0xffffffff { return 20 }
	if notify != 0 {
		if disposition == 21 {
			mut target := mach_receive_find(notify)
			if target == unsafe { nil } { return if mach_send_once_find(notify) != unsafe { nil } || mach_exception_right(notify) != .missing { i32(17) } else { i32(15) } }
			if !target.receive || target.is_set { return 17 }
			acquired = mach_send_once_new(mut target) or { return 6 }
		} else {
			acquired = mach_send_once_find(notify)
			if acquired == unsafe { nil } { return if mach_receive_find(notify) != unsafe { nil } || mach_exception_right(notify) != .missing { i32(17) } else { i32(15) } }
			if !acquired.target.receive { return 17 }
			acquired.name = 0
		}
	}
	mut port := mach_receive_find(name)
	code := if name == 0 || name == 0xffffffff { i32(4) } else if port == unsafe { nil } { if mach_send_once_find(name) != unsafe { nil } || mach_exception_right(name) != .missing { i32(17) } else { i32(15) } } else if !port.receive || port.is_set { i32(17) } else { i32(0) }
	if code != 0 {
		if acquired != unsafe { nil } { mach_send_once_emit(mut acquired, 71, 0) }
		mach_receive_refresh(); return code
	}
	mach_no_senders_check(mut port)
	if port.notification != unsafe { nil } && port.notification.target.receive && C.ios_load_pointer(unsafe { &mach_send_once_next_name }) >= 0xffffffff {
		if acquired != unsafe { nil } { mach_send_once_emit(mut acquired, 71, 0) }; mach_receive_refresh(); return 6
	}
	mut old := port.notification; port.notification = acquired
	returned := if old == unsafe { nil } { u32(0) } else { mach_send_once_export(mut old) }
	// sync gates immediate delivery only. A subsequent last-sender event fires
	// even when its make-send count is below the requested sync value.
	if acquired != unsafe { nil } && port.refs == 0 && C.ios_ref_change(unsafe { &port.transit }, 0) == 0 && port.make_send_count >= sync {
		port.notification = unsafe { nil }; mach_send_once_emit(mut acquired, 70, port.make_send_count)
	}
	unsafe { *previous = returned }; mach_receive_refresh(); return 0
}

fn mach_send_once_remove(name u32, all bool) i32 {
	mut right := mach_send_once_find(name); if right == unsafe { nil } { return 15 }
	if !right.target.receive && !all && right.refs > 1 { if right.refs != 65535 { right.refs-- }; return 0 }
	mach_send_once_emit(mut right, 71, 0); mach_receive_refresh(); return 0
}

fn mach_send_once_type(name u32, output &u32) ?i32 {
	if !mach_send_once_known(name) { return none }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	right := mach_send_once_find(name); if right == unsafe { nil } { return i32(15) }
	unsafe { *output = if right.target.receive { u32(0x40000) } else { u32(0x100000) } }; return i32(0)
}
fn mach_send_once_refs(name u32, kind i32, output &u32) ?i32 {
	if !mach_send_once_known(name) { return none }
	if kind < 0 || kind > 5 { return i32(18) }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	right := mach_send_once_find(name); if right == unsafe { nil } { return i32(15) }
	unsafe { *output = if kind == (if right.target.receive { i32(2) } else { i32(4) }) { right.refs } else { u32(0) } }; return i32(0)
}
fn mach_send_once_mod_refs(name u32, kind i32, delta i32) ?i32 {
	if !mach_send_once_known(name) { return none }
	if kind < 0 || kind > 5 { return i32(18) }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	mut right := mach_send_once_find(name); if right == unsafe { nil } { return i32(15) }
	if kind != (if right.target.receive { i32(2) } else { i32(4) }) { return i32(17) }
	if right.target.receive {
		if delta != 0 && delta != -1 { return i32(18) }
		if delta == -1 { return mach_send_once_remove(name, true) }; return i32(0)
	}
	if delta < -65535 || delta > 65535 { return i32(18) }
	if right.refs == 65535 && delta != -65535 { return i32(0) }
	refs := i64(right.refs) + i64(delta); if refs < 0 { return i32(18) }
	if refs == 0 { return mach_send_once_remove(name, true) }
	right.refs = u32(if refs > 65535 { i64(65535) } else { refs }); return i32(0)
}
fn mach_send_once_deallocate(name u32) ?i32 {
	if !mach_send_once_known(name) { return none }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	return mach_send_once_remove(name, false)
}

// Image/fork cleanup suppresses notifications and retires all rights before
// their target ports. No queue guards are acquired in the frozen fork child.
fn mach_send_once_clear() {
	mut right := system_data.send_once; system_data.send_once = unsafe { nil }
	for right != unsafe { nil } { next := right.next; right.target.notice_refs--; C.free(right.packet); C.free(right); right = next }
}
