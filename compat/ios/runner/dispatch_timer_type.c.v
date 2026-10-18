// SPDX-License-Identifier: GPL-2.0-or-later
module main

// dispatch_source_type_t is an opaque pointer. Applications pass the address
// of this constant to dispatch_source_create; they do not load a pointer cell
// or inspect Apple's private descriptor/vtable. Keep our identity in static
// read-only V storage, independently of queue and image runtime lifetimes.
struct DispatchSourceType {
	kind u64
}

const dispatch_timer_type = DispatchSourceType{ kind: 1 }

fn dispatch_timer_type_address() u64 {
	return u64(unsafe { &dispatch_timer_type })
}
