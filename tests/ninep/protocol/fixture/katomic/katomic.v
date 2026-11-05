module katomic

pub fn dec[T](mut value T) bool {
	value--
	return value != 0
}

pub fn inc[T](mut value T) T {
	value++
	return value
}
