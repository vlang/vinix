@[has_globals]
module katomic

__global before_load fn (voidptr) = unsafe { nil }

pub fn set_load_hook(callback fn (voidptr)) { before_load = callback }

pub fn load[T](value &T) T {
	if before_load != unsafe { nil } { before_load(voidptr(value)) }
	return unsafe { *value }
}

pub fn store[T](mut target T, value T) { target = value }

pub fn inc[T](mut target T) { target++ }

pub fn dec[T](mut target T) bool {
	// Snapshot the value: the host compiler can compare a generic mut
	// parameter's address when it appears directly in a comparison.
	before := target
	assert before > 0
	target--
	return before > 1
}
