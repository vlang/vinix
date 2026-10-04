module event

import eventstruct

// stack_list is a list for await() over storage the caller keeps, usually a
// fixed array on its stack. A `[&e]` literal was a heap allocation for every
// wait. The list cannot grow, freeing it does nothing, and it is good for as
// long as `storage` is.
@[unsafe]
pub fn stack_list(storage &&eventstruct.Event, count int) []&eventstruct.Event {
	mut events := []&eventstruct.Event{}
	events.data = voidptr(storage)
	events.len = count
	events.cap = count
	events.flags = .nogrow | .nofree
	return events
}

// await_one is await() for a single event, allocating nothing.
pub fn await_one(mut e eventstruct.Event, block bool) ?u64 {
	mut storage := [unsafe { &e }]!
	mut events := unsafe { stack_list(&storage[0], 1) }
	return await(mut events, block)
}

// await_one_from_generation is await_from_generation() for a single event,
// allocating nothing.
pub fn await_one_from_generation(mut e eventstruct.Event, block bool, generation u64) ?u64 {
	mut storage := [unsafe { &e }]!
	mut events := unsafe { stack_list(&storage[0], 1) }
	return await_from_generation(mut events, block, 0, generation)
}
