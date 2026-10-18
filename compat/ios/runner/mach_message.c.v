// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn mach_message_read32(buffer voidptr, offset u64) u32 {
	mut value := u32(0)
	unsafe { C.memcpy(voidptr(&value), voidptr(u64(buffer) + offset), 4) }
	return value
}
fn mach_message_write32(buffer voidptr, offset u64, value u32) {
	unsafe { C.memcpy(voidptr(u64(buffer) + offset), voidptr(&value), 4) }
}

fn mach_message_deadline(timeout u32) u64 { return darwin_mach_absolute_time() + u64(timeout) * 1_000_000 }

struct MachPreparedSend {
	code i32
	port &MachReceivePort = unsafe { nil }
	packet &MachInlineMessage = unsafe { nil }
}

// Allocate, copy, pin and register a pending packet under the namespace and
// port guards. Fork never sees a private copy owned only by a vanished sender.
fn mach_message_prepare(message voidptr, size u32, name u32, disposition u32) MachPreparedSend {
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	mut port := mach_receive_find(name)
	if port == unsafe { nil } || !port.receive || ((disposition == 17 || disposition == 19) && port.refs == 0) {
		code := if system_data != unsafe { nil } && mach_exception_right(name) == .send { i32(0x10000013) } else { i32(0x10000003) }
		return MachPreparedSend{code: code}
	}
	if C.pthread_mutex_lock(port.guard) != 0 { panic('iOS: cannot prepare message send') }
	defer { C.pthread_mutex_unlock(port.guard) }
	mut packet := unsafe { &MachInlineMessage(C.malloc(usize(sizeof(MachInlineMessage)) + usize(size))) }
	if packet == unsafe { nil } { return MachPreparedSend{code: i32(0x1000000d)} }
	unsafe { *packet = MachInlineMessage{next: port.pending, size: size, bytes: voidptr(u64(packet) + u64(sizeof(MachInlineMessage)))} }
	C.memcpy(packet.bytes, message, usize(size)); port.pending = packet; port.calls++
	if disposition == 17 && port.refs != 65535 { port.refs-- }
	return MachPreparedSend{port: port, packet: packet}
}

// Caller holds the port guard. A packet moves from this list to the FIFO or
// is freed before its call pin is released; it is never in both lists.
fn mach_message_pending_remove(mut port MachReceivePort, packet &MachInlineMessage) {
	mut link := unsafe { &port.pending }
	for unsafe { voidptr(*link) } != voidptr(packet) {
		if unsafe { *link } == unsafe { nil } { panic('iOS: missing pending message') }
		link = unsafe { &(*link).next }
	}
	unsafe { *link = packet.next }
}

// The existing native condition helper uses bounded realtime waits. Recheck
// the monotonic deadline after every wake, including spurious wakeups.
fn mach_message_wait(port &MachReceivePort, timed bool, deadline u64) bool {
	if !timed { dispatch_wait_interval(port.changed, port.guard, dispatch_forever); return true }
	now := darwin_mach_absolute_time(); if now >= deadline { return false }
	dispatch_wait_interval(port.changed, port.guard, deadline - now)
	return true
}

fn mach_message_send(message voidptr, size u32, options u32, timeout u32) i32 {
	if size < 24 || size & 3 != 0 { return i32(0x10000008) }
	if size > 65536 { return i32(0x1000000e) }
	if message == unsafe { nil } { return i32(0x10000002) }
	bits := mach_message_read32(message, 0)
	if bits & 0x1f == 0 { return i32(0x10000010) }
	// This transport accepts inline send rights with no transferred
	// reply/voucher rights. Descriptors and kernel RPCs need separate support.
	if bits == 18 { return i32(0x10000003) }
	if bits !in [u32(17), 19, 20] || mach_message_read32(message, 12) != 0 || mach_message_read32(message, 16) != 0 { return i32(0x10000013) }
	name := mach_message_read32(message, 8)
	prepared := mach_message_prepare(message, size, name, bits)
	if prepared.code != 0 { return prepared.code }
	mut port := prepared.port
	defer { mach_receive_unpin(mut port) }
	mut packet := prepared.packet
	result := mach_message_enqueue(mut port, mut packet, options, timeout)
	if result != 0 {
		returned_name := mach_receive_restore_send(mut port)
		mach_message_write32(message, 0, 17); mach_message_write32(message, 4, size)
		mach_message_write32(message, 8, returned_name)
	}
	return result
}

fn mach_message_enqueue(mut port MachReceivePort, mut packet MachInlineMessage, options u32, timeout u32) i32 {
	deadline := mach_message_deadline(timeout)
	if C.pthread_mutex_lock(port.guard) != 0 { panic('iOS: cannot guard message send') }
	defer { C.pthread_mutex_unlock(port.guard) }
	for !port.dead && port.count >= 5 {
		if !mach_message_wait(port, options & 0x10 != 0, deadline) {
			mach_message_pending_remove(mut port, packet); C.free(packet); return i32(0x10000004)
		}
	}
	mach_message_pending_remove(mut port, packet)
	// Darwin accepts an in-flight send when its destination is destroyed;
	// the message is discarded rather than pseudo-received by the sender.
	if port.dead { C.free(packet); return 0 }
	packet.next = unsafe { nil }
	if port.tail == unsafe { nil } { port.head = packet } else { port.tail.next = packet }
	port.tail = packet; port.count++
	if C.pthread_cond_broadcast(port.changed) != 0 { panic('iOS: cannot wake message receiver') }
	return 0
}

fn mach_message_receive(message voidptr, limit u32, name u32, options u32, timeout u32) i32 {
	mut port := mach_receive_pin(name) or { return i32(0x10004002) }
	defer { mach_receive_unpin(mut port) }
	deadline := mach_message_deadline(timeout)
	if C.pthread_mutex_lock(port.guard) != 0 { panic('iOS: cannot guard message receive') }
	defer { C.pthread_mutex_unlock(port.guard) }
	for !port.dead && port.head == unsafe { nil } {
		if !mach_message_wait(port, options & 0x100 != 0, deadline) { return i32(0x10004003) }
	}
	if port.dead { return i32(0x10004006) }
	packet := port.head
	large := limit < packet.size + 8
	if large && options & 4 != 0 {
		// MACH_RCV_LARGE leaves the message queued and changes only the size
		// (and optionally destination), if those fields fit in the caller's limit.
		if message == unsafe { nil } && limit >= 8 { return i32(0x10004008) }
		if limit >= 8 { mach_message_write32(message, 4, packet.size) }
		if options & 8 != 0 && limit >= 16 { mach_message_write32(message, 12, name) }
		return i32(0x10004004)
	}
	port.head = packet.next; if port.head == unsafe { nil } { port.tail = unsafe { nil } }; port.count--
	defer { C.free(packet) }
	if C.pthread_cond_broadcast(port.changed) != 0 { panic('iOS: cannot wake message sender') }
	if message == unsafe { nil } || limit < 24 { return i32(0x10004008) }
	// A destructive oversized receive returns a header-only message, whose
	// size is 24, followed by as much of the minimum trailer as fits.
	length := if large { u32(24) } else { packet.size }
	C.memcpy(message, packet.bytes, usize(length))
	mach_message_write32(message, 0, 0x1100)
	mach_message_write32(message, 4, length)
	mach_message_write32(message, 8, 0)
	mach_message_write32(message, 12, name)
	mach_message_write32(message, 16, 0)
	mut trailer := [u32(0), 8]!
	available := limit - length
	count := if available < 8 { available } else { u32(8) }
	if count != 0 { unsafe { C.memcpy(voidptr(u64(message) + u64(length)), voidptr(&trailer[0]), usize(count)) } }
	return if large { i32(0x10004004) } else { i32(0) }
}

fn darwin_mach_msg(message voidptr, options u32, send_size u32, receive_limit u32, receive_name u32, timeout u32, notify u32) i32 {
	previous := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(previous) }
	if options & 3 == 0 { return 0 }
	// Receive trailers other than the minimum format and other option modes
	// are rejected before modifying a queue or consuming any send operation.
	if options & ~u32(0x11f) != 0 { return if options & 1 != 0 { i32(0x10000013) } else { i32(0x10004013) } }
	if options & 1 != 0 { result := mach_message_send(message, send_size, options, timeout); if result != 0 { return result } }
	if options & 2 != 0 { return mach_message_receive(message, receive_limit, receive_name, options, timeout) }
	return 0
}

fn mach_message_symbol(symbol string) ?u64 {
	if address := mach_ports_symbol(symbol) { return address }
	return match symbol {
		'_mach_msg' { u64(unsafe { voidptr(darwin_mach_msg) }) }
		else { return none }
	}
}
