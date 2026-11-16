@[has_globals]
module event

pub const max_stamps = u32(128)

pub fn scan_all_completions() {}

__global completed = [128]bool{}
__global reported_stamps = [128]u32{}
__global has_value = [128]bool{}

pub fn stamp_completed(slot u32) bool { return completed[slot] }

pub fn stamp_value_completed(slot u32, value u32) bool {
	return if has_value[slot] { i32(reported_stamps[slot] - value) >= 0 } else { completed[slot] }
}

pub fn set_completed(slot u32, value bool) { completed[slot] = value; has_value[slot] = false }

pub fn set_value(slot u32, value u32) { reported_stamps[slot] = value; has_value[slot] = true }

// Seed scalar event metadata only. The exact production queue structs,
// record_completion, owns_slot, ticket and can_submit bodies are compiled
// beside this firmware-stamp test double; allocation/slot ownership is tested
// separately by the complete production event fixture.
pub fn published_queue(slot u32, value u32) WorkQueueEvents {
	return credit_queue(slot, value - u32(0x100), 1)
}

pub fn credit_queue(slot u32, baseline u32, count u32) WorkQueueEvents {
	assert count > 0 && count <= 127
	mut queue := WorkQueueEvents{slot: slot, users: count, sequence: u64(count), serial: u64(count),
		completed_value: baseline, published_value: baseline + count * u32(0x100)}
	queue.tickets.users = count
	for index := u32(0); index < count; index++ {
		queue.tickets.entries[index] = PendingTicket{value: baseline + (index + 1) * u32(0x100),
			sequence: u64(index), serial: u64(index), active: true, published: true}
	}
	return queue
}
