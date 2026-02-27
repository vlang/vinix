module kio

import aarch64.cpu

// ARM has no port I/O -- only MMIO.

pub fn mmin[T](addr &T) T {
	mut ret := T(0)
	asm volatile aarch64 {
		ldr ret, [addr]
		; =r (ret)
		; r (addr)
		; memory
	}
	cpu.dmb_ish()
	return ret
}

pub fn mmout[T](addr &T, value T) {
	cpu.dmb_ish()
	asm volatile aarch64 {
		str value, [addr]
		; ; r (addr)
		  r (value)
		; memory
	}
}

pub fn mmin32(addr &u32) u32 {
	mut ret := u32(0)
	asm volatile aarch64 {
		ldr ret, [addr]
		; =r (ret)
		; r (addr)
		; memory
	}
	cpu.dmb_ish()
	return ret
}

pub fn mmout32(addr &u32, value u32) {
	cpu.dmb_ish()
	asm volatile aarch64 {
		str value, [addr]
		; ; r (addr)
		  r (value)
		; memory
	}
}
