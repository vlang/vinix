// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module event

import event.eventstruct

__global eventfd_block_action fn () = unsafe { nil }
__global poll_wait_action fn (int) = unsafe { nil }
__global pub poll_wait_count = 0

pub fn script_poll_wait(publisher fn (int)) {
	poll_wait_action = publisher
	poll_wait_count = 0
}

pub fn await_changes(mut events []&eventstruct.Event, generations []u64, block bool) ?u64 {
	assert block && poll_wait_action != unsafe { nil }
	poll_wait_count++
	poll_wait_action(poll_wait_count)
	for index, mut target in events {
		if generation(mut target) != generations[index] { return u64(index) }
	}
	panic('no event generation changed in scripted poll wait')
}

pub fn complete_while_enrolling(publisher fn ()) {
	assert eventfd_block_action == unsafe { nil }
	eventfd_block_action = publisher
}

pub fn await_one_from_generation(mut target eventstruct.Event, block bool, seen u64) ?u64 {
	assert block && eventfd_block_action != unsafe { nil }, 'eventfd fixture unexpectedly blocked'
	assert generation(mut target) == seen
	publisher := eventfd_block_action
	eventfd_block_action = unsafe { nil }
	publisher()
	assert generation(mut target) != seen
	return 0
}
