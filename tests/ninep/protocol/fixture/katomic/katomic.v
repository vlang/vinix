module katomic

// Explicit value casts keep the fixture's result a value comparison under
// the pinned compiler, matching the kernel's atomic nonzero result.
pub fn dec[T](mut value T) bool {
	value--
	return int(value) != 0
}

pub fn inc[T](mut value T) T {
	value++
	return value
}
