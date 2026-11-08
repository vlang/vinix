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
