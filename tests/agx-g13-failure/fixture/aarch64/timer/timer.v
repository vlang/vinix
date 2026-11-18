@[has_globals]
module timer

import klock

__global fake_ns = u64(0)
__global wait_lock = unsafe { &klock.Lock(nil) }
__global wait_observer fn () = unsafe { nil }

pub fn get_us() u64 { return fake_ns / 1000 }

pub fn require_unlocked_waits(guard &klock.Lock) {
	wait_lock = unsafe { guard }
}

pub fn watch_busywait(observer fn ()) { wait_observer = observer }

pub fn get_ns() u64 {
	fake_ns += 1_000_000
	return fake_ns
}

pub fn busywait_us(us u64) {
	if wait_observer != unsafe { nil } { wait_observer() }
	if wait_lock != unsafe { nil } {
		assert !wait_lock.is_held()
	}
	fake_ns += us * 1000
}
