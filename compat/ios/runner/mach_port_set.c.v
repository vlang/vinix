// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn darwin_mach_port_move_member(task u32, name u32, group_name u32) i32 {
	previous := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(previous) }
	if system_data == unsafe { nil } || task != system_data.task_self { return 4 }
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	mut port := mach_receive_find(name)
	if port == unsafe { nil } { return if name == 0 || name == 0xffffffff || mach_exception_right(name) != .missing { i32(17) } else { i32(15) } }
	mut group := unsafe { &MachReceivePort(nil) }
	if group_name != 0 {
		group = mach_receive_find(group_name)
		if group == unsafe { nil } { return if group_name == 0xffffffff || mach_exception_right(group_name) != .missing { i32(17) } else { i32(15) } }
		if !group.receive || !group.is_set { return 17 }
	}
	// Darwin resolves the destination before checking the member's right kind.
	if !port.receive || port.is_set { return 17 }
	if group_name == 0 && port.group == unsafe { nil } { return 12 }
	if voidptr(port.group) == voidptr(group) { return 0 }
	// Namespace -> set guard -> member guard. Enqueue releases the member
	// guard before notifying its current set, so neither direction reverses it.
	if group != unsafe { nil } && C.pthread_mutex_lock(group.guard) != 0 { panic('iOS: cannot guard port set membership') }
	if C.pthread_mutex_lock(port.guard) != 0 { panic('iOS: cannot guard member queue') }
	port.group = group
	if port.head != unsafe { nil } { port.ready_order = mach_receive_next_order() }
	C.pthread_mutex_unlock(port.guard)
	if group != unsafe { nil } {
		if C.pthread_cond_broadcast(group.changed) != 0 { panic('iOS: cannot wake port set receivers') }
		C.pthread_mutex_unlock(group.guard)
	}
	return 0
}

// The sender still holds its call pin, but holds no queue guard here. Looking
// up membership under the namespace prevents a concurrent move/destroy from
// leaving a stale set pointer and closes the empty-scan/wait notification gap.
fn mach_port_set_notify(port &MachReceivePort) {
	C.ios_mach_threads_lock(); defer { C.ios_mach_threads_unlock() }
	group := port.group
	if group == unsafe { nil } { return }
	if C.pthread_mutex_lock(group.guard) != 0 { panic('iOS: cannot notify port set') }
	if C.pthread_cond_broadcast(group.changed) != 0 { panic('iOS: cannot wake port set receivers') }
	C.pthread_mutex_unlock(group.guard)
}

// Caller holds the namespace and set guard. Only one member guard is held
// at a time. Readiness order implements Darwin's rotation of ready queues;
// FIFO order remains local to each member. The returned member is pinned and
// locked, including a recheck against concurrent direct receives.
fn mach_port_set_select(group &MachReceivePort) ?&MachReceivePort {
	for {
		mut selected := unsafe { &MachReceivePort(nil) }; mut order := ~u64(0)
		mut port := system_data.receive_ports
		for port != unsafe { nil } {
			if voidptr(port.group) == voidptr(group) {
				if C.pthread_mutex_lock(port.guard) != 0 { panic('iOS: cannot inspect member queue') }
				if port.head != unsafe { nil } && port.ready_order < order { selected = port; order = port.ready_order }
				C.pthread_mutex_unlock(port.guard)
			}
			port = port.next
		}
		if selected == unsafe { nil } { return none }
		if C.pthread_mutex_lock(selected.guard) != 0 { panic('iOS: cannot receive from member') }
		if selected.head != unsafe { nil } { selected.calls++; return selected }
		C.pthread_mutex_unlock(selected.guard)
	}
}

fn mach_port_set_receive(mut group MachReceivePort, message voidptr, limit u32, options u32, timeout u32) i32 {
	deadline := mach_message_deadline(timeout)
	for {
		C.ios_mach_threads_lock()
		if C.pthread_mutex_lock(group.guard) != 0 { panic('iOS: cannot receive from port set') }
		if group.dead { C.pthread_mutex_unlock(group.guard); C.ios_mach_threads_unlock(); return i32(0x10004006) }
		if member := mach_port_set_select(group) {
			C.pthread_mutex_unlock(group.guard); C.ios_mach_threads_unlock()
			mut selected := member
			return mach_port_set_deliver(mut selected, message, limit, options)
		}
		C.ios_mach_threads_unlock()
		// The guard remains held from the empty scan until cond_wait releases
		// it atomically. Never reacquire the namespace while holding this guard.
		ready := mach_message_wait(group, options & 0x100 != 0, deadline)
		C.pthread_mutex_unlock(group.guard)
		if !ready { return i32(0x10004003) }
	}
}

fn mach_port_set_deliver(mut member MachReceivePort, message voidptr, limit u32, options u32) i32 {
	defer { mach_receive_unpin(mut member) }
	defer { C.pthread_mutex_unlock(member.guard) }
	return mach_message_copy_locked(mut member, message, limit, member.name, options)
}
