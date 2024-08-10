// katomic.v: library of atomic operations.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

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
	mut ret := false
	mut ifthis := _ifthis
	unsafe {
		asm volatile amd64 {
			lock cmpxchg here, writethis
			; +a (ifthis)
			  +m (*here) as here
			  =@ccz (ret)
			; r (writethis)
			; memory
		}
	}
	return ret
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
