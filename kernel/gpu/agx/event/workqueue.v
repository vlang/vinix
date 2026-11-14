// SPDX-License-Identifier: GPL-2.0-or-later
module event

// Like Asahi WorkQueue::new_job, acquire an event lazily and retain it until
// every prepared/submitted job has retired or been discarded. The manager
// lock serializes these methods. The physical counters survive slot reuse.
pub struct WorkQueueEvents {
mut:
	slot     u32
	users    u32
	sequence u64
	tickets  [127]PendingTicket
}

struct PendingTicket {
mut:
	value     u32
	sequence  u64
	active    bool
	published bool
}

pub struct Ticket {
pub:
	slot     u32
	value    u32
	sequence u64
}

pub fn (mut queue WorkQueueEvents) retain() ?Ticket {
	if queue.users >= 127 { return none }
	if queue.users == 0 { queue.slot = reserve_stamp() or { return none } }
	value := advance_stamp(queue.slot) or {
		if queue.users == 0 { release_stamp(queue.slot) }
		return none
	}
	mut vacant := -1
	for index, ticket in queue.tickets {
		if !ticket.active {
			vacant = index
			continue
		}
		// MAX_JOB_SLOTS in Asahi bounds the sequence window, including
		// earlier jobs retained while newer jobs have already retired.
		if value - ticket.value >= u32(128 * 0x100) {
			gpu_event_mgr.cancel_value(queue.slot, value)
			return none
		}
	}
	if vacant < 0 { return none }
	sequence := queue.sequence
	queue.sequence++
	queue.tickets[vacant] = PendingTicket{ value: value, sequence: sequence, active: true }
	queue.users++
	return Ticket{ slot: queue.slot, value: value, sequence: sequence }
}

pub fn (mut queue WorkQueueEvents) release(slot u32, value u32, submitted bool) bool {
	if queue.users == 0 || queue.slot != slot { return false }
	mut found := false
	for mut ticket in queue.tickets {
		if ticket.active && ticket.value == value {
			if ticket.published != submitted { return false }
			if !submitted && ticket.sequence + 1 == queue.sequence { queue.sequence-- }
			ticket.active = false
			found = true
			break
		}
	}
	if !found { return false }
	if !submitted { gpu_event_mgr.cancel_value(slot, value) }
	queue.users--
	if queue.users == 0 { release_stamp(queue.slot) }
	return true
}

pub fn (queue &WorkQueueEvents) busy() bool { return queue.users != 0 }

// Asahi rejects out-of-order commit/submit. A higher stamp published first
// would make a later low-valued command look complete before GPU execution.
pub fn (queue &WorkQueueEvents) can_publish(slot u32, value u32) bool {
	if queue.users == 0 || queue.slot != slot { return false }
	mut found := false
	for ticket in queue.tickets {
		if !ticket.active { continue }
		if ticket.value == value {
			if ticket.published { return false }
			found = true
		} else if !ticket.published && i32(value - ticket.value) > 0 {
			return false
		}
	}
	return found
}

// Call only after the ring publication succeeds, while holding the same
// manager lock used by can_publish(). Failure leaves reservations unchanged.
pub fn (mut queue WorkQueueEvents) publish(slot u32, value u32) bool {
	if !queue.can_publish(slot, value) { return false }
	for mut ticket in queue.tickets {
		if ticket.active && ticket.value == value {
			ticket.published = true
			return true
		}
	}
	return false
}
