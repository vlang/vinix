// SPDX-License-Identifier: GPL-2.0-or-later
import gpu.agx.event
import drm.syncobj

fn main() {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000,
		unsafe { u64(&firmware) })
	for i := u32(0); i < event.max_stamps; i++ {
		slot := event.reserve_stamp() or { panic('allocate initial stamp') }
		assert slot == i
		assert driver[i] == (i << 24), 'slot ${i}: driver stamp ${driver[i]}'
		assert firmware[i] == 0
		assert (event.advance_stamp(slot) or { panic('advance initial stamp') }) == (i << 24) + 0x100
		assert !event.stamp_completed(slot)
	}
	assert event.reserve_stamp() == none
	event.reset_event_manager()
	driver = [128]u32{}
	mut em := event.EventManager{
		initialized:   true
		stamp_phys:    unsafe { u64(&driver) }
		fw_stamp_phys: unsafe { u64(&firmware) }
	}
	mut expected := u32(0)
	for _ in 0 .. 300 {
		slot := em.alloc_stamp() or { panic('allocate stamp') }
		assert slot == 0
		assert driver[0] == expected && firmware[0] == expected
		assert !em.check_completion(slot), 'a reused slot is not an armed command'
		value := em.next_stamp_value(slot) or { panic('advance stamp') }
		expected += 0x100
		assert value == expected
		assert !em.check_completion(slot), 'the previous owner must not satisfy the next command'
		driver[0] = value
		firmware[0] = value
		assert em.check_completion(slot)
		em.free_stamp(slot)
	}
	// Zero is a valid counter after wrap, not an unarmed-command sentinel.
	driver[0] = 0xffffff00
	firmware[0] = 0xffffff00
	slot := em.alloc_stamp() or { panic('allocate wrap stamp') }
	assert !em.check_completion(slot)
	assert (em.next_stamp_value(slot) or { panic('advance wrap stamp') }) == 0
	assert !em.check_completion(slot)
	mut fence := syncobj.DmaFence{}
	em.set_fence(slot, &fence)
	em.scan_completions()
	assert fence.signals == 0
	driver[0] = 0
	firmware[0] = 0
	em.scan_completions()
	assert fence.signals == 1 && em.check_completion(slot)
	em.scan_completions()
	assert fence.signals == 1, 'completion is signaled only once'
	em.free_stamp(slot)
	if _ := em.next_stamp_value(slot) {
		assert false, 'unowned slot advanced'
	}
	// A 64-command workqueue holds one physical event. Each job retires
	// against its own value even while the newest reservation is pending.
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000,
		unsafe { u64(&firmware) })
	mut queue := event.WorkQueueEvents{}
	mut tickets := [64]event.Ticket{}
	for i in 0 .. tickets.len {
		tickets[i] = queue.retain() or { panic('retain shared event') }
		assert tickets[i].slot == 0 && tickets[i].value == u32(i + 1) * 0x100
		assert tickets[i].sequence == u64(i)
	}
	for i := u32(1); i < event.max_stamps; i++ {
		assert (event.reserve_stamp() or { panic('one event per workqueue') }) == i
	}
	assert event.reserve_stamp() == none
	assert !queue.can_publish(tickets[1].slot, tickets[1].value)
	assert !queue.publish(tickets[1].slot, tickets[1].value), 'out-of-order publication must fail'
	for ticket in tickets {
		assert queue.publish(ticket.slot, ticket.value)
		assert !queue.publish(ticket.slot, ticket.value), 'a ticket cannot be published twice'
	}
	driver[0] = tickets[0].value
	assert event.stamp_value_completed(0, tickets[0].value)
	assert !event.stamp_value_completed(0, tickets[1].value)
	assert !event.stamp_completed(0), 'latest expectation must remain pending'
	assert !queue.release(127, tickets[0].value, true)
	for i in 0 .. 63 {
		assert queue.release(tickets[i].slot, tickets[i].value, true)
		assert queue.busy() && event.reserve_stamp() == none
	}
	driver[0] = tickets[63].value
	assert queue.release(tickets[63].slot, tickets[63].value, true)
	assert !queue.busy()
	assert !queue.release(tickets[63].slot, tickets[63].value, true)
	// Tail cancellation rolls back without resetting physical stamps. An
	// earlier cancellation must not rewind over a later reservation.
	a := queue.retain() or { panic('retain a') }
	b := queue.retain() or { panic('retain b') }
	assert queue.release(b.slot, b.value, false)
	c := queue.retain() or { panic('retain c') }
	assert c.value == b.value
	assert c.sequence == b.sequence, 'cancellation must roll back event sequence too'
	assert queue.release(a.slot, a.value, false)
	d := queue.retain() or { panic('retain d') }
	assert d.value == c.value + 0x100
	assert d.sequence == c.sequence + 1
	assert queue.release(d.slot, d.value, false)
	assert queue.release(c.slot, c.value, false)
	assert !queue.busy()
	driver[0] = 0xffffff00
	wrap_a := queue.retain() or { panic('shared wrap a') }
	wrap_b := queue.retain() or { panic('shared wrap b') }
	assert wrap_a.value == 0 && wrap_b.value == 0x100
	assert !queue.publish(wrap_b.slot, wrap_b.value)
	assert queue.publish(wrap_a.slot, wrap_a.value)
	assert queue.publish(wrap_b.slot, wrap_b.value)
	assert !event.stamp_value_completed(wrap_a.slot, wrap_a.value)
	driver[0] = 0
	assert event.stamp_value_completed(wrap_a.slot, wrap_a.value)
	assert !event.stamp_value_completed(wrap_b.slot, wrap_b.value)
	assert queue.release(wrap_a.slot, wrap_a.value, true)
	driver[0] = 0x100
	assert queue.release(wrap_b.slot, wrap_b.value, true)
	mut window := [127]event.Ticket{}
	for i in 0 .. window.len { window[i] = queue.retain() or { panic('fill event window') } }
	assert queue.retain() == none, 'upstream permits at most 127 pending event values'
	for ticket in window { assert queue.publish(ticket.slot, ticket.value) }
	for i in 1 .. window.len { assert queue.release(window[i].slot, window[i].value, true) }
	// A retained old value bounds the sequence window even when slots in
	// the bookkeeping table are free; no half-range ambiguity can develop.
	newest := queue.retain() or { panic('final free event value') }
	assert newest.value - window[0].value == 127 * 0x100
	assert queue.retain() == none
	assert queue.release(newest.slot, newest.value, false)
	assert queue.release(window[0].slot, window[0].value, true)
	event.reset_event_manager()
	println('AGX events: initial slot counters, 300 slot reuses, stale completion isolation, counter wrap and fence signaling passed')
	println('AGX workqueue events: 64 shared tickets, independent retirement, final-owner release, tail rollback and wrap passed')
}
