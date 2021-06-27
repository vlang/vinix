module eventstruct

import klock

pub struct Event {
pub mut:
	pending   u64
	listeners [16]EventListener
}

struct EventListener {
pub mut:
	l      klock.Lock
	ready  klock.Lock
	thread voidptr
	index  u64
	which  &u64
}

pub fn (mut this Event) get_listener() &EventListener {
	for i := u64(0); i < this.listeners.len; i++ {
		if this.listeners[i].l.test_and_acquire() == true {
			return unsafe { &this.listeners[i] }
		}
	}
	return 0
}
