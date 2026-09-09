module katomic

pub fn bts[T](mut var T, bit u8) bool {
	mut ret := false
	unsafe {
		asm volatile amd64 {
			lock bts var, bit
			; +m (*var) as var
			  =@ccc (ret)
			; r (u16(bit)) as bit
			; memory
		}
	}
	return ret
}

pub fn btr[T](mut var T, bit u8) bool {
	mut ret := false
	unsafe {
		asm volatile amd64 {
			lock btr var, bit
			; +m (*var) as var
			  =@ccc (ret)
			; r (u16(bit)) as bit
			; memory
		}
	}
	return ret
}

pub fn cas[T](mut here T, _ifthis T, writethis T) bool {
	// For a pointer-valued T, using *here as an inline-assembly operand makes
	// V's C backend emit **here and atomically dereference the slot's value.
	// Work on width-specific integer views so the operand is always the queue
	// slot itself. This also compares pointer bits instead of struct contents.
	if sizeof(T) == 1 {
		mut expected := u8(0)
		mut desired := u8(0)
		unsafe {
			C.memcpy(&expected, &_ifthis, 1)
			C.memcpy(&desired, &writethis, 1)
		}
		mut ret := false
		mut target := unsafe { &u8(here) }
		asm volatile amd64 {
			lock cmpxchg target, desired
			; +a (expected)
			  +m (*target) as target
			  =@ccz (ret)
			; r (desired)
			; memory
		}
		return ret
	}
	if sizeof(T) == 4 {
		mut expected := u32(0)
		mut desired := u32(0)
		unsafe {
			C.memcpy(&expected, &_ifthis, 4)
			C.memcpy(&desired, &writethis, 4)
		}
		mut ret := false
		mut target := unsafe { &u32(here) }
		asm volatile amd64 {
			lock cmpxchg target, desired
			; +a (expected)
			  +m (*target) as target
			  =@ccz (ret)
			; r (desired)
			; memory
		}
		return ret
	}
	if sizeof(T) == 8 {
		mut expected := u64(0)
		mut desired := u64(0)
		unsafe {
			C.memcpy(&expected, &_ifthis, 8)
			C.memcpy(&desired, &writethis, 8)
		}
		mut ret := false
		mut target := unsafe { &u64(here) }
		asm volatile amd64 {
			lock cmpxchg target, desired
			; +a (expected)
			  +m (*target) as target
			  =@ccz (ret)
			; r (desired)
			; memory
		}
		return ret
	}
	panic('katomic.cas: unsupported operand width')
}

pub fn inc[T](mut var T) T {
	mut diff := unsafe { T(1) }
	unsafe {
		asm volatile amd64 {
			lock xadd var, diff
			; +m (*var) as var
			  +r (diff)
			; ; memory
		}
	}
	return diff
}

pub fn dec[T](mut var T) bool {
	mut ret := false
	unsafe {
		mut diff := T(-1)
		asm volatile amd64 {
			lock xadd var, diff
			; +m (*var) as var
			  +r (diff)
			  =@ccnz (ret)
			; ; memory
		}
	}
	return ret
}

pub fn store[T](mut var T, value T) {
	unsafe {
		asm volatile amd64 {
			lock xchg var, value
			; +m (*var) as var
			  +r (value)
			; ; memory
		}
	}
}

pub fn load[T](var &T) T {
	mut ret := unsafe { T(0) }
	unsafe {
		asm volatile amd64 {
			lock xadd var, ret
			; +m (*var) as var
			  +r (ret)
			; ; memory
		}
	}
	return ret
}
