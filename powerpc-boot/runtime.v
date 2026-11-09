// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Compiler-generated aggregate copies need these even with -no-builtin.
// No allocator or hosted libc is available before the kernel takes control.
@[export: 'memcpy']
fn copy_bytes(destination voidptr, source voidptr, count uint) voidptr {
	unsafe {
		mut dst := &u8(destination)
		src := &u8(source)
		for i := uint(0); i < count; i++ { dst[i] = src[i] }
	}
	return destination
}

@[export: 'memset']
fn fill_bytes(destination voidptr, value int, count uint) voidptr {
	unsafe {
		mut dst := &u8(destination)
		for i := uint(0); i < count; i++ { dst[i] = u8(value) }
	}
	return destination
}

@[export: 'memmove']
fn move_bytes(destination voidptr, source voidptr, count uint) voidptr {
	if uint(destination) <= uint(source) || uint(destination) - uint(source) >= count {
		return copy_bytes(destination, source, count)
	}
	unsafe {
		mut dst := &u8(destination)
		src := &u8(source)
		mut i := count
		for i > 0 {
			i--
			dst[i] = src[i]
		}
	}
	return destination
}

@[export: 'v_fixed_index']
fn checked_index(index i64, length int) int {
	if index < 0 || index >= length {
		puts(c'VINIX-PPC: FAIL array bounds\r\n')
		for {}
	}
	return int(index)
}
