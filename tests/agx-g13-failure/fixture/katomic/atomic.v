@[has_globals]
module katomic

__global barrier_count = u32(0)
__global next_sync fn () = unsafe { nil }

pub fn load[T](value &T) T { return unsafe { *value } }

pub fn store[T](mut target T, value T) { target = value }

pub fn inc[T](mut target T) T {
	previous := target
	target++
	return previous
}

pub fn dec[T](mut target T) bool {
	target--
	return target != 0
}

pub fn cas_acquire[T](mut target T, expected T, value T) bool {
	if unsafe { *target } != expected { return false }
	target = value
	return true
}

pub fn sync() {
	barrier_count++
	if next_sync != unsafe { nil } {
		callback := next_sync
		next_sync = unsafe { nil }
		callback()
	}
}

pub fn on_next_sync(callback fn ()) { next_sync = callback }

pub fn barriers() u32 { return barrier_count }
