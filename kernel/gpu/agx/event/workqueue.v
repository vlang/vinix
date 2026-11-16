// SPDX-License-Identifier: GPL-2.0-or-later
module event

import memory

// Like Asahi WorkQueue::new_job, acquire an event lazily and retain it until
// every prepared/submitted job has retired or been discarded. The manager
// lock serializes these methods. The physical counters survive slot reuse.
// This is owning state: never copy it while reservations are retained.
pub struct WorkQueueEvents {
mut:
	slot     u32
	users    u32
	sequence u64
	serial   u64 // host identity never rolls back with a canceled stamp value
	completed_value u32 // host-retired prefix, independent of prepared reservations
	published_value u32 // only successful firmware publication consumes capacity
	tickets  TicketBlock
}

// Keep the ordinary queue allocation-free. Prepared backlog can exceed the
// hardware's publication window; overflow blocks own only scalar reservations.
// Every access is serialized by manager.lock, and empty overflow blocks unlink
// before they are freed. No job, capture or firmware record points into them.
struct TicketBlock {
mut:
	next &TicketBlock = unsafe { nil }
	users u32
	entries [127]PendingTicket
}

struct PendingTicket {
mut:
	value     u32
	sequence  u64
	serial    u64
	active    bool
	published bool
	admitted  bool // whole-subqueue admission survives canceled stamp gaps
}

pub struct Ticket {
pub:
	slot     u32
	value    u32
	sequence u64
	serial   u64
}

pub fn (mut queue WorkQueueEvents) retain() ?Ticket {
	if queue.users == ~u32(0) { return none }
	if queue.users == 0 { queue.slot = reserve_stamp() or { return none } }
	value := advance_stamp(queue.slot) or {
		if queue.users == 0 { release_stamp(queue.slot) }
		return none
	}
	// Retained identities and future stamps must remain inside the signed
	// half range. This is independent of the 127-event publication credit.
	if queue.users != 0 && value - queue.completed_value >= u32(0x80000000) {
		gpu_event_mgr.cancel_value(queue.slot, value)
		return none
	}
	mut vacant := 0
	mut target := &TicketBlock(unsafe { nil })
	mut block := unsafe { &queue.tickets }
	mut tail := block
	for block != unsafe { nil } {
		for index, ticket in block.entries {
			if !ticket.active {
				if target == unsafe { nil } { target, vacant = block, index }
				continue
			}
			if value - ticket.value >= u32(0x80000000) {
				gpu_event_mgr.cancel_value(queue.slot, value)
				return none
			}
		}
		tail = block
		block = block.next
	}
	if target == unsafe { nil } {
		target = unsafe { &TicketBlock(memory.malloc_packed_fallible(sizeof(TicketBlock))) } @[freed]
		if target == unsafe { nil } {
			gpu_event_mgr.cancel_value(queue.slot, value)
			return none
		}
		unsafe { *target = TicketBlock{} }
		tail.next = target
	}
	if queue.users == 0 {
		queue.completed_value = value - u32(0x100)
		queue.published_value = queue.completed_value
	}
	sequence := queue.sequence
	queue.sequence++
	serial := queue.serial
	queue.serial++
	target.entries[vacant] = PendingTicket{ value: value, sequence: sequence, serial: serial, active: true }
	target.users++
	queue.users++
	return Ticket{ slot: queue.slot, value: value, sequence: sequence, serial: serial }
}

pub enum InitialState { absent pending ready }

pub fn (queue &WorkQueueEvents) owns_slot(slot u32) bool {
	return queue.users != 0 && queue.slot == slot
}

pub fn (queue &WorkQueueEvents) ticket(slot u32, value u32) ?Ticket {
	if !queue.owns_slot(slot) { return none }
	mut block := unsafe { &queue.tickets }
	for block != unsafe { nil } {
		for entry in block.entries {
			if entry.active && entry.value == value {
				return Ticket{ slot: slot, value: value, sequence: entry.sequence, serial: entry.serial }
			}
		}
		block = block.next
	}
	return none
}

// Caller holds the manager lock and a physical-slot pin. A canceled reservation
// may reuse its value/sequence, but never its host identity. Do not wait on a
// future reservation or discard an older unpublished dependency.
pub fn (queue &WorkQueueEvents) resolve_initial(captured Ticket) (InitialState, Ticket) {
	if stamp_value_completed(captured.slot, captured.value) { return .ready, captured }
	if !queue.owns_slot(captured.slot) { return .absent, Ticket{} }
	mut found := false
	mut latest := Ticket{}
	mut block := unsafe { &queue.tickets }
	for block != unsafe { nil } {
		for entry in block.entries {
			if !entry.active || i64(entry.serial - captured.serial) > 0 { continue }
			if !entry.published { return .pending, Ticket{} }
			if !found || i64(entry.serial - latest.serial) > 0 {
				latest = Ticket{ slot: queue.slot, value: entry.value, sequence: entry.sequence, serial: entry.serial }
				found = true
			}
		}
		block = block.next
	}
	return if found { InitialState.ready } else { InitialState.absent }, latest
}

// Caller holds manager.lock and has proved this publication completed. Return
// admission credit independently of cleanup: tickets, overflow storage and the
// physical stamp stay owned while other render stages or barriers need them.
pub fn (mut queue WorkQueueEvents) record_completion(slot u32, value u32) bool {
	if !queue.owns_slot(slot) { return false }
	mut block := unsafe { &queue.tickets }
	for block != unsafe { nil } {
		for ticket in block.entries {
			if ticket.active && ticket.value == value && ticket.published {
				if i32(value - queue.completed_value) > 0 { queue.completed_value = value }
				return true
			}
		}
		block = block.next
	}
	return false
}

pub fn (mut queue WorkQueueEvents) release(slot u32, value u32, submitted bool) bool {
	if queue.users == 0 || queue.slot != slot { return false }
	mut previous := &TicketBlock(unsafe { nil })
	mut block := unsafe { &queue.tickets }
	for block != unsafe { nil } {
		mut found := false
		for mut ticket in block.entries {
			if ticket.active && ticket.value == value {
				if ticket.published != submitted { return false }
				// A later retired stamp covers earlier work on this physical queue.
				// Reverse cleanup must never move its completed prefix back.
				if submitted && i32(value - queue.completed_value) > 0 { queue.completed_value = value }
				if !submitted && ticket.sequence + 1 == queue.sequence { queue.sequence-- }
				ticket.active = false
				found = true
				break
			}
		}
		if found {
			if !submitted { gpu_event_mgr.cancel_value(slot, value) }
			block.users--
			queue.users--
			if previous != unsafe { nil } && block.users == 0 {
				previous.next = block.next
				memory.free(block)
			}
			if queue.users == 0 { release_stamp(queue.slot) }
			return true
		}
		previous = block
		block = block.next
	}
	return false
}

pub fn (queue &WorkQueueEvents) busy() bool { return queue.users != 0 }

// Asahi checks the entire subqueue job before its first publication. Prepared
// reservations do not consume this window; only host-unretired publications do.
pub fn (queue &WorkQueueEvents) can_submit(count u32) bool {
	if queue.users == 0 { return false }
	busy := i32(queue.published_value - queue.completed_value) >> 8
	free_slots := if busy >= 127 { i32(0) } else { i32(127) - busy }
	return u32(free_slots) > count
}

// Caller has checked every participating subqueue under the manager lock.
// This grants one existing prepared ticket, without publishing or pinning it.
// The file poller's FIFO excludes a later batch until this grant is consumed
// or canceled. Like Asahi's Job, admitted events are not charged twice.
pub fn (mut queue WorkQueueEvents) admit(slot u32, value u32) bool {
	if !queue.owns_slot(slot) { return false }
	mut block := unsafe { &queue.tickets }
	for block != unsafe { nil } {
		for mut ticket in block.entries {
			if ticket.active && ticket.value == value && !ticket.published {
				ticket.admitted = true
				return true
			}
		}
		block = block.next
	}
	return false
}

// Validate the complete admitted sequence before writing any command. Checking
// only its first ticket would miss an omitted unpublished ticket in the middle.
pub fn (queue &WorkQueueEvents) can_publish_batch(slot u32, values [64]u32, count u32) bool {
	if count == 0 || count > 64 || !queue.owns_slot(slot) { return false }
	for index := u32(0); index < count; index++ {
		if index != 0 && i32(values[index] - values[index - 1]) <= 0 { return false }
		mut found := false
		mut block := unsafe { &queue.tickets }
		for block != unsafe { nil } {
			for ticket in block.entries {
				if ticket.active && ticket.value == values[index] && ticket.admitted && !ticket.published { found = true; break }
			}
			if found { break }
			block = block.next
		}
		if !found { return false }
	}
	mut block := unsafe { &queue.tickets }
	for block != unsafe { nil } {
		for ticket in block.entries {
			if !ticket.active || ticket.published || i32(ticket.value - values[count - 1]) > 0 { continue }
			mut included := false
			for index := u32(0); index < count; index++ { if ticket.value == values[index] { included = true; break } }
			if !included { return false }
		}
		block = block.next
	}
	return true
}

// Asahi rejects out-of-order commit/submit. A higher stamp published first
// would make a later low-valued command look complete before GPU execution.
pub fn (queue &WorkQueueEvents) can_publish(slot u32, value u32) bool {
	if queue.users == 0 || queue.slot != slot { return false }
	mut found := false
	mut admitted := false
	mut block := unsafe { &queue.tickets }
	for block != unsafe { nil } {
		for ticket in block.entries {
			if !ticket.active { continue }
			if ticket.value == value {
				if ticket.published { return false }
				found = true
				admitted = ticket.admitted
			} else if !ticket.published && i32(value - ticket.value) > 0 {
				return false
			}
		}
		block = block.next
	}
	return found && (admitted || queue.can_submit(1))
}

// Call only after the ring publication succeeds, while holding the same
// manager lock used by can_publish(). Failure leaves reservations unchanged.
pub fn (mut queue WorkQueueEvents) publish(slot u32, value u32) bool {
	if !queue.can_publish(slot, value) { return false }
	mut block := unsafe { &queue.tickets }
	for block != unsafe { nil } {
		for mut ticket in block.entries {
			if ticket.active && ticket.value == value {
				ticket.published = true
				ticket.admitted = false
				queue.published_value = value
				return true
			}
		}
		block = block.next
	}
	return false
}
