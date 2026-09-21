module katomic

// AArch64 atomic operations using LSE atomics and acquire/release accesses.
// This file provides the same API as katomic_amd64.v but for ARM64.
//
// Every access goes through a width-exact routine in asm/aarch64/kio.S. V's
// inline assembler renders an operand as `%[name]`, which on AArch64 always
// names the 64-bit register; a 32-bit or 8-bit field therefore got an 8-byte
// atomic, clobbering its neighbour or faulting on alignment (LDAR/STLR and
// the LSE ops require natural alignment for the register width). Widths are
// selected at compile time from T (`$if T is ...`; this backend does not
// support `$if sizeof(T) == n`); a width with no routine is a build error
// rather than a silent 64-bit access.

fn C.vinix_ldar8(addr voidptr) u8
fn C.vinix_ldar16(addr voidptr) u16
fn C.vinix_ldar32(addr voidptr) u32
fn C.vinix_ldar64(addr voidptr) u64
fn C.vinix_stlr8(addr voidptr, value u8)
fn C.vinix_stlr16(addr voidptr, value u16)
fn C.vinix_stlr32(addr voidptr, value u32)
fn C.vinix_stlr64(addr voidptr, value u64)
fn C.vinix_ldadd32(addr voidptr, value u32) u32
fn C.vinix_ldadd64(addr voidptr, value u64) u64
fn C.vinix_ldset32(addr voidptr, value u32) u32
fn C.vinix_ldset64(addr voidptr, value u64) u64
fn C.vinix_ldclr32(addr voidptr, value u32) u32
fn C.vinix_ldclr64(addr voidptr, value u64) u64
fn C.vinix_cas32(addr voidptr, expected u32, desired u32) u32
fn C.vinix_cas64(addr voidptr, expected u64, desired u64) u64
fn C.vinix_casa32(addr voidptr, expected u32, desired u32) u32
fn C.vinix_casa64(addr voidptr, expected u64, desired u64) u64

pub fn bts[T](mut var T, bit u8) bool {
	mask := unsafe { T(1) << bit }
	$if T is u32 || T is i32 || T is int {
		old := C.vinix_ldset32(voidptr(var), u32(mask))
		return old & u32(mask) != 0
	} $else $if T is u64 || T is i64 || T is usize || T is isize || T is voidptr {
		old := C.vinix_ldset64(voidptr(var), u64(mask))
		return old & u64(mask) != 0
	} $else {
		$compile_error('katomic.bts: unsupported operand width')
	}
	return false
}

pub fn btr[T](mut var T, bit u8) bool {
	// LDCLR atomically computes *var = *var & ~operand, so the operand must
	// be the bit(s) to clear (mask), NOT its complement.
	mask := unsafe { T(1) << bit }
	$if T is u32 || T is i32 || T is int {
		old := C.vinix_ldclr32(voidptr(var), u32(mask))
		return old & u32(mask) != 0
	} $else $if T is u64 || T is i64 || T is usize || T is isize || T is voidptr {
		old := C.vinix_ldclr64(voidptr(var), u64(mask))
		return old & u64(mask) != 0
	} $else {
		$compile_error('katomic.btr: unsupported operand width')
	}
	return false
}

// Compare raw bits, NOT V's == operator: on pointer types V's == dereferences
// and compares struct contents, which crashes when the pointers are nil.
//
// The width is picked by sizeof rather than by a list of types, because the
// callers that matter pass a reference — cas[&proc.Thread] on the run queue —
// and no `$if T is ...` arm can name one: `$pointer` does not match `&Thread`,
// and spelling the type out would mean katomic importing proc. Nothing in
// either arm casts a T, so both typecheck whatever T turns out to be, and
// sizeof folds away at compile time.
pub fn cas[T](mut here T, _ifthis T, writethis T) bool {
	if sizeof(T) == 4 {
		mut expected := u32(0)
		mut desired := u32(0)
		unsafe {
			C.memcpy(&expected, &_ifthis, 4)
			C.memcpy(&desired, &writethis, 4)
		}
		return C.vinix_cas32(voidptr(here), expected, desired) == expected
	}
	if sizeof(T) == 8 {
		mut expected := u64(0)
		mut desired := u64(0)
		unsafe {
			C.memcpy(&expected, &_ifthis, 8)
			C.memcpy(&desired, &writethis, 8)
		}
		return C.vinix_cas64(voidptr(here), expected, desired) == expected
	}
	panic('katomic.cas: unsupported operand width')
}

// cas_acquire is a compare-and-swap with acquire ordering on success (CASA).
// Lock acquisition must use this so that memory accesses inside the critical
// section cannot be reordered before the lock is taken.
pub fn cas_acquire[T](mut here T, _ifthis T, writethis T) bool {
	if sizeof(T) == 4 {
		mut expected := u32(0)
		mut desired := u32(0)
		unsafe {
			C.memcpy(&expected, &_ifthis, 4)
			C.memcpy(&desired, &writethis, 4)
		}
		return C.vinix_casa32(voidptr(here), expected, desired) == expected
	}
	if sizeof(T) == 8 {
		mut expected := u64(0)
		mut desired := u64(0)
		unsafe {
			C.memcpy(&expected, &_ifthis, 8)
			C.memcpy(&desired, &writethis, 8)
		}
		return C.vinix_casa64(voidptr(here), expected, desired) == expected
	}
	panic('katomic.cas_acquire: unsupported operand width')
}

// Returns the value before the increment.
pub fn inc[T](mut var T) T {
	$if T is u32 || T is i32 || T is int {
		return T(C.vinix_ldadd32(voidptr(var), u32(1)))
	} $else $if T is u64 || T is i64 || T is usize || T is isize || T is voidptr {
		return T(C.vinix_ldadd64(voidptr(var), u64(1)))
	} $else {
		$compile_error('katomic.inc: unsupported operand width')
	}
	return T(0)
}

// Decrements and reports whether the result is non-zero.
pub fn dec[T](mut var T) bool {
	$if T is u32 || T is i32 || T is int {
		old := C.vinix_ldadd32(voidptr(var), u32(0xffffffff))
		return old - u32(1) != 0
	} $else $if T is u64 || T is i64 || T is usize || T is isize || T is voidptr {
		old := C.vinix_ldadd64(voidptr(var), u64(0xffffffffffffffff))
		return old - u64(1) != 0
	} $else {
		$compile_error('katomic.dec: unsupported operand width')
	}
	return false
}

pub fn store[T](mut var T, value T) {
	// bool gets its own arm: V refuses to cast one to u8, and there is no
	// numeric conversion to lean on in either direction.
	$if T is bool {
		C.vinix_stlr8(voidptr(var), if value { u8(1) } else { u8(0) })
	} $else $if T is u8 || T is i8 {
		C.vinix_stlr8(voidptr(var), u8(value))
	} $else $if T is u16 || T is i16 {
		C.vinix_stlr16(voidptr(var), u16(value))
	} $else $if T is u32 || T is i32 || T is int {
		C.vinix_stlr32(voidptr(var), u32(value))
	} $else $if T is u64 || T is i64 || T is usize || T is isize || T is voidptr {
		C.vinix_stlr64(voidptr(var), u64(value))
	} $else {
		$compile_error('katomic.store: unsupported operand width')
	}
}

pub fn load[T](var &T) T {
	$if T is bool {
		return C.vinix_ldar8(voidptr(var)) != 0
	} $else $if T is u8 || T is i8 {
		return T(C.vinix_ldar8(voidptr(var)))
	} $else $if T is u16 || T is i16 {
		return T(C.vinix_ldar16(voidptr(var)))
	} $else $if T is u32 || T is i32 || T is int {
		return T(C.vinix_ldar32(voidptr(var)))
	} $else $if T is u64 || T is i64 || T is usize || T is isize || T is voidptr {
		return T(C.vinix_ldar64(voidptr(var)))
	} $else {
		$compile_error('katomic.load: unsupported operand width')
	}
	// Unreachable: every arm above returns and the $else is a build error.
	// It cannot be written as `return T(0)`, because T may be bool.
	panic('katomic.load: unreachable')
}
