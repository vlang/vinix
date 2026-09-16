module eventstruct

import klock

// Enough slots for the contention a threaded process generates: musl serialises
// every pthread_create on one futex, so a thread pool waits on a single event.
pub const max_listeners = 64

pub struct EventListener {
pub mut:
	thrd  voidptr
	which u64
}

pub struct Event {
pub mut:
	@lock       klock.Lock
	pending     u64
	generation  u64
	listeners_i u64
	listeners   [max_listeners]EventListener
}
