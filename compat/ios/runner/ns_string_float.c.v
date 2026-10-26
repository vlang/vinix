// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math as bits

fn ns_string_float_digit(unit u32) int {
	// Foundation's scanner consumes BMP decimal digits as UTF-16 units.
	for zero in [u32(0x30), 0x660, 0x6f0, 0x7c0, 0x966, 0x9e6, 0xa66, 0xae6,
		0xb66, 0xbe6, 0xc66, 0xce6, 0xd66, 0xde6, 0xe50, 0xed0, 0xf20, 0x1040,
		0x1090, 0x17e0, 0x1810, 0x1946, 0x19d0, 0x1a80, 0x1a90, 0x1b50,
		0x1bb0, 0x1c40, 0x1c50, 0xa620, 0xa8d0, 0xa900, 0xa9d0, 0xa9f0,
		0xaa50, 0xabf0, 0xff10]! {
		if unit >= zero && unit < zero + 10 { return int(unit - zero) }
	}
	return -1
}

fn ns_string_float_space(unit u32) bool {
	return unit in [u32(9), 0x20, 0xa0, 0x1680, 0x202f, 0x205f, 0x3000]!
		|| (unit >= 0x2000 && unit <= 0x200b)
}

// Parse the decimal prefix only: libc's hex, infinity and NaN grammar is not
// NSString's grammar. Normalize Unicode digits, then round through a double,
// as native Foundation does even at binary32 halfway boundaries.
fn ns_string_float(text string) f32 {
	mut cursor := CFStringCompareCursor{text: text}
	mut unit := cursor.next()
	for ns_string_float_space(unit) { unit = cursor.next() }
	mut token := []u8{cap: text.len + 1}
	defer { unsafe { token.free() } }
	if unit == `+` || unit == `-` { token << u8(unit); unit = cursor.next() }
	mut digits := 0
	mut point := false
	for {
		digit := ns_string_float_digit(unit)
		if digit >= 0 {
			token << u8(`0` + digit)
			digits++
		} else if unit == `.` && !point {
			token << u8(`.`)
			point = true
		} else { break }
		unit = cursor.next()
	}
	if digits == 0 { return 0 }
	if unit == `e` || unit == `E` {
		end := token.len
		token << u8(`e`)
		unit = cursor.next()
		if unit == `+` || unit == `-` { token << u8(unit); unit = cursor.next() }
		mut exponent_digits := 0
		for {
			digit := ns_string_float_digit(unit)
			if digit < 0 { break }
			token << u8(`0` + digit)
			exponent_digits++
			unit = cursor.next()
		}
		if exponent_digits == 0 { token.trim(end) }
	}
	token << u8(0)
	return f32(C.strtod(unsafe { &char(token.data) }, unsafe { nil }))
}

fn ns_string_float_return(object u64, mut frame RegisterFrame) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	// The borrowed buffer cannot change or be released while parsing it.
	frame.q[0] = u64(bits.f32_bits(ns_string_float(mutable_string_source(object))))
	frame.q[1] = 0
}
