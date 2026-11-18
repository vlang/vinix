@[has_globals]
module katomic

__global barrier_count = u32(0)
__global next_sync fn () = unsafe { nil }

pub fn load[T](value &T) T { return unsafe { *value } }

pub fn store[T](mut target T, value T) { target = value }

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
