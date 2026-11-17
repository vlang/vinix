// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module event

import event.eventstruct

__global eventfd_block_action fn () = unsafe { nil }

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
