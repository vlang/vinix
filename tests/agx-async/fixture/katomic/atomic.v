module katomic

pub fn load[T](value &T) T { return unsafe { *value } }

pub fn store[T](mut target T, value T) { target = value }

pub fn inc[T](mut target T) { target++ }

pub fn dec[T](mut target T) {
	assert target > 0
	target--
}
