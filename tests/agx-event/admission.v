module main

import gpu.agx.event

fn check_publication_window() {
	mut driver := [128]u32{}
	mut firmware := [128]u32{}
	assert event.configure_event_manager(0x10000, unsafe { u64(&driver) }, 0x20000, unsafe { u64(&firmware) })
	baselines := [u32(0), 0xffffff00, 0xffff8000, 0x7fffff00, 0x80000000]!
	for cycle in 0 .. 1000 {
		driver[0] = baselines[cycle % baselines.len]
		mut queue := event.WorkQueueEvents{}
		mut tickets := [127]event.Ticket{}
		for index in 0 .. 127 {
			tickets[index] = queue.retain() or { panic('prepare full window') }
		}
		for index in 0 .. 126 {
			assert queue.publish(tickets[index].slot, tickets[index].value)
		}
		assert !queue.can_publish(tickets[126].slot, tickets[126].value)
		assert !queue.publish(tickets[126].slot, tickets[126].value)
		driver[0] = tickets[125].value
		assert !queue.can_publish(tickets[126].slot, tickets[126].value), 'GPU progress alone cannot release the host window'
		assert queue.release(tickets[0].slot, tickets[0].value, true)
		assert queue.publish(tickets[126].slot, tickets[126].value)
		driver[0] = tickets[126].value
		assert queue.release(tickets[126].slot, tickets[126].value, true)
		// Later GPU completion covers the earlier prefix even with its metadata
		// still retained. Reverse callbacks must not move that high-water back.
		tail := queue.retain() or { panic('newer tail') }
		assert queue.publish(tail.slot, tail.value)
		for index := 125; index > 0; index-- {
			assert queue.release(tickets[index].slot, tickets[index].value, true)
		}
		next := queue.retain() or { panic('after reverse cleanup') }
		assert queue.publish(next.slot, next.value)
		driver[0] = next.value
		assert queue.release(next.slot, next.value, true)
		assert queue.release(tail.slot, tail.value, true) && !queue.busy()
		probe := event.reserve_stamp() or { panic('physical owner leaked') }
		assert probe == 0
		event.release_stamp(probe)
	}
	// Canceling the prepared tail may reuse its value but cannot grant host
	// publication capacity. Older holes remain accounted for until retirement.
	mut queue := event.WorkQueueEvents{}
	mut tickets := [127]event.Ticket{}
	for index in 0 .. 127 { tickets[index] = queue.retain() or { panic('cancellation window') } }
	assert queue.release(tickets[0].slot, tickets[0].value, false)
	for index in 1 .. 126 {
		assert queue.publish(tickets[index].slot, tickets[index].value)
	}
	assert queue.release(tickets[126].slot, tickets[126].value, false)
	replacement := queue.retain() or { panic('tail replacement') }
	assert replacement.value == tickets[126].value && replacement.serial != tickets[126].serial
	assert !queue.publish(replacement.slot, replacement.value)
	driver[replacement.slot] = tickets[125].value
	assert queue.release(tickets[125].slot, tickets[125].value, true)
	assert queue.publish(replacement.slot, replacement.value)
	for index := 124; index > 0; index-- {
		assert queue.release(tickets[index].slot, tickets[index].value, true)
	}
	driver[replacement.slot] = replacement.value
	assert queue.release(replacement.slot, replacement.value, true) && !queue.busy()
	// No command has been published in this new window. A large gap of
	// canceled reservations must still admit the first actual job.
	mut gaps := event.WorkQueueEvents{}
	for index in 0 .. 127 {
		tickets[index] = gaps.retain() or { panic('all canceled predecessors') }
	}
	for index in 0 .. 126 {
		assert gaps.release(tickets[index].slot, tickets[index].value, false)
	}
	assert gaps.publish(tickets[126].slot, tickets[126].value)
	blocked := gaps.retain() or { panic('after published gap') }
	assert !gaps.publish(blocked.slot, blocked.value), 'published gaps still consume the reference delta until host retirement'
	driver[tickets[126].slot] = tickets[126].value
	assert !gaps.can_publish(blocked.slot, blocked.value)
	assert gaps.release(tickets[126].slot, tickets[126].value, true)
	assert gaps.publish(blocked.slot, blocked.value)
	driver[blocked.slot] = blocked.value
	assert gaps.release(blocked.slot, blocked.value, true) && !gaps.busy()
	event.reset_event_manager()
	println('AGX event admission: 1000 full prepared windows, 126-event publication, host-retirement retry, raw-progress refusal, signed/zero wrap, reverse cleanup and cancellation holes passed')
}
