// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.ios_atomic_pair_load(&u64, &u64)
fn C.ios_atomic_pair_exchange(&u64, &u64, &u64) int

fn atomic_queue_head(head u64) &u64 {
	if head == 0 || head & 15 != 0 { panic('iOS: OSAtomic queue head requires 16-byte alignment') }
	return unsafe { &u64(head) }
}

fn atomic_queue_link(node u64, offset u64) &u64 {
	if node == 0 || offset > ~u64(0) - node { panic('iOS: invalid OSAtomic queue link address') }
	return unsafe { &u64(node + offset) }
}

// Darwin's queue is a lock-free LIFO stack with a pointer/generation pair.
// Compare the entire 16-byte head to prevent ABA when nodes are reused. Policy
// stays in V; the assembly primitives provide atomic pair access and barriers.
fn darwin_atomic_enqueue(head u64, node u64, offset u64) {
	queue := atomic_queue_head(head)
	link := atomic_queue_link(node, offset)
	mut observed := [u64(0), 0]!
	C.ios_atomic_pair_load(queue, unsafe { &observed[0] })
	for {
		C.ios_store_pointer(link, observed[0])
		mut desired := [node, observed[1] + 1]!
		if C.ios_atomic_pair_exchange(queue, unsafe { &observed[0] }, unsafe { &desired[0] }) != 0 { return }
	}
}

fn darwin_atomic_dequeue(head u64, offset u64) u64 {
	queue := atomic_queue_head(head)
	mut observed := [u64(0), 0]!
	C.ios_atomic_pair_load(queue, unsafe { &observed[0] })
	for {
		if observed[0] == 0 { return 0 }
		node := observed[0]
		// As on Darwin, callers must keep popped nodes' link storage mapped
		// until concurrent dequeues have returned; this function owns no nodes.
		next := C.ios_load_pointer(atomic_queue_link(node, offset))
		mut desired := [next, observed[1] + 1]!
		if C.ios_atomic_pair_exchange(queue, unsafe { &observed[0] }, unsafe { &desired[0] }) != 0 { return node }
	}
}
