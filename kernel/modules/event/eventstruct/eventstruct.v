// eventstruct.v: Event structures.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module eventstruct

import klock

pub const max_listeners = 32

pub struct EventListener {
pub mut:
	thrd  voidptr
	which u64
}

pub struct Event {
pub mut:
	@lock       klock.Lock
	pending     u64
	listeners_i u64
	listeners   [eventstruct.max_listeners]EventListener
}
