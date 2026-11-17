// SPDX-License-Identifier: GPL-2.0-or-later
module syncobj

import memory

struct EventfdEntry {
	context voidptr
	finish fn (voidptr, bool)
	point u64
	available bool
mut:
	next &EventfdEntry = unsafe { nil }
}

// The tail links back to the first entry. Moving an entry between lists
// transfers its sole ownership without allocating or changing its target.
struct EventfdQueue {
mut:
	tail &EventfdEntry = unsafe { nil }
}

fn (mut queue EventfdQueue) push(entry &EventfdEntry) {
	mut node := unsafe { entry }
	if queue.tail == unsafe { nil } { node.next = unsafe { entry } }
	else {
		node.next = unsafe { queue.tail.next }
		unsafe { queue.tail.next = entry }
	}
	queue.tail = unsafe { entry }
}

fn (mut queue EventfdQueue) pop() ?&EventfdEntry {
	if queue.tail == unsafe { nil } { return none }
	first := unsafe { queue.tail.next }
	if voidptr(first) == voidptr(queue.tail) { queue.tail = unsafe { nil } }
	else { unsafe { queue.tail.next = first.next } }
	return first
}

fn finish_eventfd(entry &EventfdEntry, signal bool) {
	entry.finish(entry.context, signal)
	memory.free(voidptr(entry))
}

fn (mut queue EventfdQueue) finish_all(signal bool) {
	for {
		entry := queue.pop() or { return }
		finish_eventfd(entry, signal)
	}
}

// Caller holds the syncobj lock. Once a point exists, the registration
// belongs exclusively to its captured fence or completes synchronously.
fn (mut obj SyncObj) resolve_eventfd_locked(entry &EventfdEntry) {
	fence := find_chain_fence(obj.fence, entry.point) or {
		obj.eventfd_pending.push(entry)
		return
	}
	if entry.available || fence == unsafe { nil } {
		finish_eventfd(entry, true)
		return
	}
	enable_array(fence)
	mut f := unsafe { fence }
	f.lock.acquire()
	complete := f.signaled
	if !complete { f.eventfd_ready.push(entry) }
	f.lock.release()
	if complete { finish_eventfd(entry, true) }
}

fn (mut obj SyncObj) publish_eventfds_locked() bool {
	if obj.fence == unsafe { nil } || obj.eventfd_pending.tail == unsafe { nil } { return false }
	mut pending := obj.eventfd_pending
	obj.eventfd_pending = EventfdQueue{}
	for {
		entry := pending.pop() or { break }
		obj.resolve_eventfd_locked(entry)
	}
	return true
}

// The caller holds a syncobj reference. Success transfers the retained target
// to an entry; on allocation failure the caller still owns that target.
pub fn register_eventfd(obj &SyncObj, point u64, available bool, context voidptr, finish fn (voidptr, bool)) bool {
	allocation := memory.malloc_packed_fallible(sizeof(EventfdEntry)) @[freed]
	if allocation == unsafe { nil } { return false }
	entry := unsafe { &EventfdEntry(allocation) }
	unsafe { *entry = EventfdEntry{ context: context, finish: finish, point: point, available: available } }
	mut o := unsafe { obj }
	o.lock.acquire()
	o.resolve_eventfd_locked(entry)
	o.lock.release()
	drain_chain_notifications()
	return true
}
