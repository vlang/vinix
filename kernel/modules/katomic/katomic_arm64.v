module katomic

// AArch64 atomic operations using LSE atomics and LDXR/STXR.
// This file provides the same API as katomic_amd64.v but for ARM64.
// The build system selects between this and the x86 version.

pub fn bts[T](mut var T, bit u8) bool {
	mask := unsafe { T(1) << bit }
	mut old := unsafe { T(0) }
	unsafe {
		asm volatile aarch64 {
			ldset mask, old, [var]
			; =r (old)
			; r (mask)
			  r (var)
			; memory
		}
	}
	return old & mask != 0
}

pub fn btr[T](mut var T, bit u8) bool {
	// LDCLR atomically computes *var = *var & ~operand, so the operand must
	// be the bit(s) to clear (mask), NOT its complement. Passing ~mask would
	// clear every OTHER bit and leave the target bit set.
	mask := unsafe { T(1) << bit }
	mut old := unsafe { T(0) }
	unsafe {
		asm volatile aarch64 {
			ldclr mask, old, [var]
			; =r (old)
			; r (mask)
			  r (var)
			; memory
		}
	}
	return old & mask != 0
}

pub fn cas[T](mut here T, _ifthis T, writethis T) bool {
	mut ifthis := _ifthis
	unsafe {
		asm volatile aarch64 {
			cas ifthis, writethis, [here]
			; +r (ifthis)
			; r (writethis)
			  r (here)
			; memory
		}
	}
	// Compare raw bytes, NOT V's == operator. V's == on pointer types
	// (e.g. &Process) dereferences and compares struct contents, which
	// crashes when the pointers are nil.
	return unsafe { C.memcmp(voidptr(&ifthis), voidptr(&_ifthis), sizeof(T)) == 0 }
}

// cas_acquire is a compare-and-swap with acquire ordering on success (CASA).
// Lock acquisition must use this so that memory accesses inside the critical
// section cannot be reordered before the lock is taken. A plain relaxed CAS
// plus a compiler "memory" clobber does NOT provide CPU acquire ordering.
pub fn cas_acquire[T](mut here T, _ifthis T, writethis T) bool {
	mut ifthis := _ifthis
	unsafe {
		asm volatile aarch64 {
			casa ifthis, writethis, [here]
			; +r (ifthis)
			; r (writethis)
			  r (here)
			; memory
		}
	}
	return unsafe { C.memcmp(voidptr(&ifthis), voidptr(&_ifthis), sizeof(T)) == 0 }
}

pub fn inc[T](mut var T) T {
	mut ret := unsafe { T(0) }
	one := unsafe { T(1) }
	unsafe {
		asm volatile aarch64 {
			ldadd one, ret, [var]
			; =r (ret)
			; r (one)
			  r (var)
			; memory
		}
	}
	return ret
}

pub fn dec[T](mut var T) bool {
	mut old := unsafe { T(0) }
	neg_one := unsafe { T(-1) }
	unsafe {
		asm volatile aarch64 {
			ldadd neg_one, old, [var]
			; =r (old)
			; r (neg_one)
			  r (var)
			; memory
		}
	}
	return old + neg_one != 0
}

pub fn store[T](mut var T, value T) {
	unsafe {
		asm volatile aarch64 {
			stlr value, [var]
			; ; r (value)
			  r (var)
			; memory
		}
	}
}

pub fn load[T](var &T) T {
	mut ret := unsafe { T(0) }
	unsafe {
		asm volatile aarch64 {
			ldar ret, [var]
			; =r (ret)
			; r (var)
			; memory
		}
	}
	return ret
}
