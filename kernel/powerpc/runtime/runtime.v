// SPDX-License-Identifier: GPL-2.0-or-later
module runtime

// Freestanding PPC32 has no compiler-rt __udivdi3. The timebase needs a
// full-width quotient so uptime does not wrap every few minutes.
pub fn divide_u64(value u64, divisor u32) u64 {
	if divisor == 0 { return 0 }
	mut remainder := u64(0)
	mut quotient := u64(0)
	for bit := 63; bit >= 0; bit-- {
		remainder = (remainder << 1) | ((value >> bit) & 1)
		if remainder >= divisor { remainder -= divisor; quotient |= u64(1) << bit }
	}
	return quotient
}

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
		$if ppc { asm volatile ppc raw { "trap" } }
		for {}
	}
	return int(value)
}
