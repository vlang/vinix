// SPDX-License-Identifier: GPL-2.0-or-later
// No libc is needed by the translated 32-bit ABI fixture.
module robustbare

@[c_extern]
fn C.robust_bare_write(i32, voidptr, usize) isize
@[c_extern]
fn C.robust_bare_open(&char, i32) i32
@[c_extern]
fn C.robust_bare_exit(i32)

@[export: 'robust_bare_puts']
pub fn bare_puts(text &char) i32 {
	unsafe {
		fd := C.robust_bare_open(c'/dev/com1', 1)
		mut length := usize(0)
		for text[length] != 0 { length++ }
		C.robust_bare_write(if fd >= 0 { fd } else { i32(1) }, text, length)
		C.robust_bare_write(if fd >= 0 { fd } else { i32(1) }, c'\n', 1)
	}
	return 0
}

@[export: 'robust_bare_assert']
pub fn bare_assert(condition bool) {
	if !condition {
		bare_puts(c'STEAM ROBUST ABI FIXTURE: FAIL')
		C.robust_bare_exit(97)
	}
}

@[export: 'robust_bare_strcmp']
pub fn bare_strcmp(a &char, b &char) i32 {
	unsafe {
		mut i := usize(0)
		for a[i] != 0 && a[i] == b[i] { i++ }
		return i32(u8(a[i])) - i32(u8(b[i]))
	}
}

@[export: 'memset']
pub fn bare_memset(destination voidptr, value i32, length usize) voidptr {
	unsafe { for i := usize(0); i < length; i++ { (&u8(destination))[i] = u8(value) } }
	return destination
}

@[export: 'memcpy']
pub fn bare_memcpy(destination voidptr, source voidptr, length usize) voidptr {
	unsafe { for i := usize(0); i < length; i++ { (&u8(destination))[i] = (&u8(source))[i] } }
	return destination
}

@[export: 'memmove']
pub fn bare_memmove(destination voidptr, source voidptr, length usize) voidptr {
	unsafe {
		if usize(destination) <= usize(source) { return bare_memcpy(destination, source, length) }
		for i := length; i > 0; { i--; (&u8(destination))[i] = (&u8(source))[i] }
	}
	return destination
}
