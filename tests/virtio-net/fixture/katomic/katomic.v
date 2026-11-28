module katomic

pub fn load[T](address &T) T {
	return unsafe { *address }
}

pub fn store[T](mut address T, value T) {
	unsafe {
		*address = value
	}
}
