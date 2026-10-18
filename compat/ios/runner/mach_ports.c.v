// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct MachInlineMessage {
mut:
	next &MachInlineMessage = unsafe { nil }
	size u32
	bytes voidptr
}

struct MachReceivePort {
mut:
	next &MachReceivePort = unsafe { nil }
	name u32
	refs u32
	receive bool
	calls u64
	guard voidptr
	changed voidptr
	// The native guard protects the queue and termination; namespace state
	// above is protected by ios_mach_threads_lock. Never reverse that order.
	dead bool
	count u32
	head &MachInlineMessage = unsafe { nil }
	tail &MachInlineMessage = unsafe { nil }
	pending &MachInlineMessage = unsafe { nil }
}

__global mach_receive_next_name = u64(0x70000113)

fn mach_receive_known(name u32) bool {
	return name >= 0x70000113 && u64(name) < C.ios_load_pointer(unsafe { &mach_receive_next_name }) && name & 0xff == 19
}

// Caller holds the shared namespace lock. Retired objects can remain pinned
// by blocked calls, but their names no longer resolve to any right.
fn mach_receive_find(name u32) &MachReceivePort {
	if system_data == unsafe { nil } { return unsafe { nil } }
	mut port := system_data.receive_ports
	for port != unsafe { nil } {
		if port.name == name && (port.receive || port.refs != 0) { return port }
		port = port.next
	}
	return unsafe { nil }
}

fn mach_receive_packets_free(mut port MachReceivePort) {
	mut packet := port.head
	port.head = unsafe { nil }; port.tail = unsafe { nil }; port.count = 0
	for packet != unsafe { nil } { next := packet.next; C.free(packet); packet = next }
}

fn mach_receive_free(mut port MachReceivePort, forked bool) {
	if !forked && port.calls != 0 { panic('iOS: active receive port at retirement') }
	if !forked && port.pending != unsafe { nil } { panic('iOS: unowned pending message at retirement') }
	mach_receive_packets_free(mut port)
	// In the fork child, senders vanished with their private copied packets.
	// Queue guards were frozen before fork, so the pending list is complete.
	mut pending := port.pending; port.pending = unsafe { nil }
	for pending != unsafe { nil } { next := pending.next; C.free(pending); pending = next }
	if !forked {
		if C.pthread_cond_destroy(port.changed) != 0 || C.pthread_mutex_destroy(port.guard) != 0 { panic('iOS: active receive port at retirement') }
	}
	C.free(port.changed); C.free(port.guard); C.free(port)
}

fn mach_receive_refresh() {
	mut previous := unsafe { &MachReceivePort(nil) }; mut port := system_data.receive_ports
	for port != unsafe { nil } {
		next := port.next
		if !port.receive && port.refs == 0 && port.calls == 0 {
			if previous == unsafe { nil } { system_data.receive_ports = next } else { previous.next = next }
			mach_receive_free(mut port, false)
		} else { previous = port }
		port = next
	}
}

fn mach_receive_pin(name u32) ?&MachReceivePort {
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	mut port := mach_receive_find(name)
	if port == unsafe { nil } || !port.receive { return none }
	port.calls++
	return port
}

// Failed sends pseudo-receive their in-transit destination right. COPY_SEND
// and MAKE_SEND therefore add a user reference; MOVE_SEND restores its one.
fn mach_receive_restore_send(mut port MachReceivePort) u32 {
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	if !port.receive { return 0xffffffff }
	if port.refs != 65535 { port.refs++ }
	return port.name
}

fn mach_receive_unpin(mut port MachReceivePort) {
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	if port.calls == 0 { panic('iOS: receive port call reference underflow') }
	port.calls--; mach_receive_refresh()
}

// Namespace lock is held. Borrowers release this guard before unpinning, so
// termination can wake them without racing a free or inverting the locks.
fn mach_receive_terminate(mut port MachReceivePort) {
	if C.pthread_mutex_lock(port.guard) != 0 { panic('iOS: cannot retire receive port') }
	port.dead = true; mach_receive_packets_free(mut port)
	if C.pthread_cond_broadcast(port.changed) != 0 { panic('iOS: cannot wake message callers') }
	C.pthread_mutex_unlock(port.guard)
}

fn darwin_mach_port_allocate(task u32, right i32, output &u32) i32 {
	previous := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(previous) }
	if system_data == unsafe { nil } || task != system_data.task_self || output == unsafe { nil } { return 4 }
	if right < 0 || right > 5 { return 18 }
	if right != 1 { return 46 } // Port sets, standalone dead names and send-once allocation are unsupported.
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	next := C.ios_load_pointer(unsafe { &mach_receive_next_name }); if next >= 0xffffffff { return 6 }
	mut port := unsafe { &MachReceivePort(C.calloc(1, sizeof(MachReceivePort))) }; if port == unsafe { nil } { return 6 }
	unsafe { *port = MachReceivePort{name: u32(next), receive: true} }
	port.guard = C.calloc(1, C.ios_sizeof_mutex()); port.changed = C.calloc(1, C.ios_sizeof_cond())
	if port.guard == unsafe { nil } || port.changed == unsafe { nil } { C.free(port.guard); C.free(port.changed); C.free(port); return 6 }
	if C.ios_mutex_create(port.guard, 0) != 0 { C.free(port.guard); C.free(port.changed); C.free(port); return 6 }
	if C.pthread_cond_init(port.changed, unsafe { nil }) != 0 { C.pthread_mutex_destroy(port.guard); C.free(port.guard); C.free(port.changed); C.free(port); return 6 }
	port.next = system_data.receive_ports; system_data.receive_ports = port
	C.ios_store_pointer(unsafe { &mach_receive_next_name }, next + 0x100)
	unsafe { *output = port.name }; return 0
}

fn darwin_mach_port_insert_right(task u32, name u32, source u32, disposition u32) i32 {
	previous := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(previous) }
	if system_data == unsafe { nil } || task != system_data.task_self { return 4 }
	if disposition != 20 || name != source { return 46 }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	mut port := mach_receive_find(name)
	if port == unsafe { nil } { return 15 }
	if !port.receive { return 17 }
	if port.refs != 65535 { port.refs++ }
	return 0
}

fn darwin_mach_port_destroy(task u32, name u32) i32 {
	previous := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(previous) }
	if system_data == unsafe { nil } || task != system_data.task_self { return 4 }
	if name == 0 || name == 0xffffffff { return 0 }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	mut port := mach_receive_find(name)
	if port == unsafe { nil } { return if mach_exception_right(name) == .send { i32(46) } else { i32(15) } }
	port.receive = false; port.refs = 0; mach_receive_terminate(mut port); mach_receive_refresh(); return 0
}

fn mach_receive_port_type(name u32, output &u32) ?i32 {
	if !mach_receive_known(name) { return none }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	port := mach_receive_find(name); if port == unsafe { nil } { return i32(15) }
	unsafe { *output = if !port.receive { u32(0x100000) } else { u32(0x20000) | if port.refs != 0 { u32(0x10000) } else { u32(0) } } }
	return i32(0)
}

fn mach_receive_port_refs(name u32, right i32, output &u32) ?i32 {
	if !mach_receive_known(name) { return none }
	if right < 0 || right > 5 { return i32(18) }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	port := mach_receive_find(name); if port == unsafe { nil } { return i32(15) }
	unsafe { *output = if right == 1 { u32(port.receive) } else if right == (if port.receive { i32(0) } else { i32(4) }) { port.refs } else { u32(0) } }
	return i32(0)
}

fn mach_receive_port_mod_refs(name u32, right i32, delta i32) ?i32 {
	if !mach_receive_known(name) { return none }
	if right < 0 || right > 5 { return i32(18) }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	mut port := mach_receive_find(name); if port == unsafe { nil } { return i32(15) }
	if right == 1 && port.receive {
		if delta != 0 && delta != -1 { return i32(18) }
		if delta == -1 { port.receive = false; mach_receive_terminate(mut port); mach_receive_refresh() }
		return i32(0)
	}
	if right != (if port.receive { i32(0) } else { i32(4) }) || port.refs == 0 { return i32(17) }
	if delta < -65535 || delta > 65535 { return i32(18) }
	if port.refs == 65535 && (port.receive || delta != -65535) { return if delta == -65535 { i32(20) } else { i32(0) } }
	refs := i64(port.refs) + i64(delta); if refs < 0 { return i32(18) }
	port.refs = u32(if refs > 65535 { i64(65535) } else { refs }); mach_receive_refresh(); return i32(0)
}

fn mach_receive_port_deallocate(name u32) ?i32 {
	if !mach_receive_known(name) { return none }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	mut port := mach_receive_find(name); if port == unsafe { nil } { return i32(15) }
	if port.refs == 0 { return i32(17) }
	if port.refs != 65535 { port.refs-- }
	mach_receive_refresh(); return i32(0)
}

// Freeze every queue while the namespace is pinned across fork. The child
// discards native conditions with vanished waiters instead of destroying them.
fn mach_receive_fork_prepare() {
	if system_data == unsafe { nil } { return }
	mut port := system_data.receive_ports
	for port != unsafe { nil } { if C.pthread_mutex_lock(port.guard) != 0 { panic('iOS: cannot pin receive port for fork') }; port = port.next }
}
fn mach_receive_fork_parent() {
	if system_data == unsafe { nil } { return }
	mut port := system_data.receive_ports
	for port != unsafe { nil } { C.pthread_mutex_unlock(port.guard); port = port.next }
}
fn mach_receive_clear(forked bool) {
	if system_data == unsafe { nil } { return }
	mut port := system_data.receive_ports; system_data.receive_ports = unsafe { nil }
	for port != unsafe { nil } { next := port.next; mach_receive_free(mut port, forked); port = next }
}
fn mach_receive_stop() { C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }; mach_receive_clear(false) }

fn mach_ports_symbol(symbol string) ?u64 {
	return match symbol {
		'_mach_port_allocate' { u64(unsafe { voidptr(darwin_mach_port_allocate) }) }
		'_mach_port_insert_right' { u64(unsafe { voidptr(darwin_mach_port_insert_right) }) }
		'_mach_port_destroy' { u64(unsafe { voidptr(darwin_mach_port_destroy) }) }
		else { return none }
	}
}
