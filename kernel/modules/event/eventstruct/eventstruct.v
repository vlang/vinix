module eventstruct

import klock

pub const max_listeners = 32

pub struct EventListener {
pub mut:
	thread voidptr
	which  u64
}

pub struct Event {
pub mut:
	@lock       klock.Lock
	pending     u64
	listeners_i u64
	listeners   [max_listeners]EventListener
}
