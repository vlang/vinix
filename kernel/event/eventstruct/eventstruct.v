module eventstruct

import klock

// Enough slots for the contention a threaded process generates: musl serialises
// every pthread_create on one futex, so a thread pool waits on a single event.
pub const max_listeners = 64

// Nearly every event has at most a waiter or two, and one is embedded in every
// file, socket and pipe -- and copied into every interface value that names
// one. The first few slots live here; the rest are allocated while more
// threads than that are waiting, and given back when they are gone.
pub const inline_listeners = 8

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
	listeners   [inline_listeners]EventListener
	overflow    &EventListener = unsafe { nil }
}

// The listener in slot `i`, below listeners_i or the one reserve() made room
// for. Called with the lock held.
pub fn (mut e Event) slot(i u64) &EventListener {
	if i < inline_listeners {
		return &e.listeners[i]
	}
	return unsafe { &e.overflow[i - inline_listeners] }
}

// Make room for one more listener, reporting whether there is any. Called with
// the lock held.
pub fn (mut e Event) reserve() bool {
	if e.listeners_i >= max_listeners {
		return false
	}
	if e.listeners_i >= inline_listeners && e.overflow == unsafe { nil } {
		e.overflow = unsafe { &EventListener(malloc(sizeof(EventListener) * (max_listeners - inline_listeners))) }
		if e.overflow == unsafe { nil } {
			return false
		}
	}
	return true
}

// Give the overflow slots back once the listeners fit without them. Called with
// the lock held.
pub fn (mut e Event) shrink() {
	if e.listeners_i <= inline_listeners && e.overflow != unsafe { nil } {
		unsafe { free(e.overflow) }
		e.overflow = unsafe { nil }
	}
}
