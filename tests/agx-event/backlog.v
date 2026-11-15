module main

import gpu.agx.event
import memory

fn check_prepared_backlog() {
	check_backlog_retirement()
	check_backlog_cancellation()
	check_backlog_allocation_failure()
	check_backlog_half_range()
	println('AGX event backlog: 1024 prepared tickets, strict64-event admission/host retirement, block-spanning capture/ABA/FIFO, empty middle-block unlink, allocation rollback, half-range guards and zero retained overflow blocks pass')
}

fn check_backlog_retirement() {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	for cycle in 0 .. 20 {
		driver[0] = if cycle % 2 == 0 { u32(0xffffff00) } else { u32(0x7fffff00) }
		mut queue := event.WorkQueueEvents{}
		mut tickets := [1024]event.Ticket{}
		for index in 0 .. tickets.len {
			tickets[index] = queue.retain() or { panic('prepare backlog') }
			assert tickets[index].sequence == u64(index) && tickets[index].slot == 0
		}
		assert memory.outstanding() == 8
		for index in [126, 127, 253, 254, 1023]! {
			assert (queue.ticket(tickets[index].slot, tickets[index].value) or { panic('block lookup') }).serial == tickets[index].serial
		}
		for start := 0; start < tickets.len; start += 64 {
			assert queue.can_submit(64)
			mut values := [64]u32{}
			for offset in 0 .. 64 {
				ticket := tickets[start + offset]
				values[offset] = ticket.value
				assert queue.admit(ticket.slot, ticket.value)
			}
			assert queue.can_publish_batch(tickets[start].slot, values, 64)
			for offset in 0 .. 64 {
				ticket := tickets[start + offset]
				assert queue.publish(ticket.slot, ticket.value)
			}
			assert !queue.can_submit(64), 'prepared backlog cannot bypass publication capacity'
			driver[0] = tickets[start + 63].value
			assert !queue.can_submit(64), 'raw GPU progress does not return host admission credit'
			for offset := 63; offset >= 0; offset-- {
				ticket := tickets[start + offset]
				assert queue.release(ticket.slot, ticket.value, true)
			}
		}
		assert !queue.busy() && memory.outstanding() == 0
	}
	event.reset_event_manager()
}

fn check_backlog_cancellation() {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	for _ in 0 .. 100 {
		mut queue := event.WorkQueueEvents{}
		mut tickets := [384]event.Ticket{}
		for index in 0 .. tickets.len { tickets[index] = queue.retain() or { panic('cancellation backlog') } }
		assert memory.outstanding() == 3
		captured := tickets[253]
		assert event.retain_stamp(captured.slot)
		// Remove an entire middle block while later reservations retain a tail.
		for index in 127 .. 254 { assert queue.release(tickets[index].slot, tickets[index].value, false) }
		assert memory.outstanding() == 2 && queue.ticket(captured.slot, captured.value) == none
		state, _ := queue.resolve_initial(captured)
		assert state == .pending
		for index := 383; index >= 254; index-- { assert queue.release(tickets[index].slot, tickets[index].value, false) }
		assert memory.outstanding() == 0
		// Repeated tail rollback may reuse a value, but never its capture serial.
		old := queue.retain() or { panic('new overflow') }
		assert memory.outstanding() == 1 && event.retain_stamp(old.slot)
		assert queue.release(old.slot, old.value, false) && memory.outstanding() == 0
		future := queue.retain() or { panic('ABA overflow') }
		assert future.value == old.value && future.serial != old.serial
		mut values := [64]u32{}
		for index in 0 .. 64 { values[index] = tickets[index].value; assert queue.admit(tickets[index].slot, values[index]) }
		assert queue.can_publish_batch(0, values, 64)
		for index in 0 .. 64 { assert queue.publish(0, values[index]) }
		state1, fallback := queue.resolve_initial(old)
		assert state1 == .pending, 'remaining older unpublished work in the inline block still blocks'
		assert fallback.value == 0
		// Cancel every older unpublished ticket; the captured target resolves
		// only to the last older publication and excludes the future ABA value.
		for index := 126; index >= 64; index-- { assert queue.release(tickets[index].slot, tickets[index].value, false) }
		state2, last := queue.resolve_initial(old)
		assert state2 == .ready && last.serial == tickets[63].serial && last.value != future.value
		assert queue.release(future.slot, future.value, false) && memory.outstanding() == 0
		driver[0] = tickets[63].value
		for index := 63; index >= 0; index-- { assert queue.release(0, tickets[index].value, true) }
		event.release_stamp(old.slot)
		event.release_stamp(captured.slot)
		assert !queue.busy() && memory.outstanding() == 0
	}
	event.reset_event_manager()
}

fn check_backlog_allocation_failure() {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	mut queue := event.WorkQueueEvents{}
	mut tickets := [255]event.Ticket{}
	for index in 0 .. 254 {
		if index == 127 {
			memory.fail_next(true)
			assert queue.retain() == none && memory.outstanding() == 0
			memory.fail_next(false)
		}
		tickets[index] = queue.retain() or { panic('retry overflow allocation') }
		assert tickets[index].value == u32(index + 1) * 0x100 && tickets[index].serial == u64(index)
	}
	memory.fail_next(true)
	assert queue.retain() == none && memory.outstanding() == 1
	memory.fail_next(false)
	tickets[254] = queue.retain() or { panic('retry third block') }
	assert tickets[254].value == 255 * 0x100 && tickets[254].serial == 254 && memory.outstanding() == 2
	for index := 254; index >= 0; index-- { assert queue.release(0, tickets[index].value, false) }
	assert !queue.busy() && memory.outstanding() == 0
	event.reset_event_manager()
}

fn check_backlog_half_range() {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	mut queue := event.WorkQueueEvents{}
	first := queue.retain() or { panic('first half-range ticket') }
	event.test_cursor(0, 0x7fffff00)
	assert queue.retain() == none, 'future values must remain within the host completion half range'
	event.test_completed(mut queue, 0x7fffff00)
	event.test_cursor(0, 0x80000000)
	assert queue.retain() == none, 'an older retained identity must not be reused across half a counter cycle'
	event.test_completed(mut queue, 0)
	event.test_cursor(0, first.value)
	next := queue.retain() or { panic('after range refusal') }
	assert next.value == 0x200 && next.sequence == 1 && next.serial == 1
	assert queue.release(0, next.value, false) && queue.release(0, first.value, false)
	assert memory.outstanding() == 0
	event.reset_event_manager()
}
