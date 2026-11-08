// SPDX-License-Identifier: GPL-2.0-or-later
module runtime

pub fn copy(destination voidptr, source voidptr, count u32) voidptr {
	unsafe {
		mut dst := &u8(destination)
		src := &u8(source)
		for i := u32(0); i < count; i++ { dst[i] = src[i] }
	}
	return destination
}

pub fn fill(destination voidptr, value i32, count u32) voidptr {
	unsafe {
		mut dst := &u8(destination)
		for i := u32(0); i < count; i++ { dst[i] = u8(value) }
	}
	return destination
}

pub fn move(destination voidptr, source voidptr, count u32) voidptr {
	if u32(destination) <= u32(source) || u32(destination) - u32(source) >= count {
		return copy(destination, source, count)
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

pub fn checked_index(value i64, length int) int {
	if value < 0 || value >= length {
		asm volatile ppc raw { "trap" }
		for {}
	}
	return int(value)
}
