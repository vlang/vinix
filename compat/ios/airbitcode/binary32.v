// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// IEEE binary32, round to nearest/ties to even, with gradual underflow.
// No host floating-point instruction, environment or allocation is involved.
const binary32_nan = u32(0x7fc00000)
fn binary32_is_nan(value u32) bool { return value & 0x7fffffff > 0x7f800000 }
fn binary32_jam(value u64, distance int) u64 {
	if distance == 0 { return value }
	if distance >= 64 { return u64(value != 0) }
	return (value >> distance) | u64(value & ((u64(1) << distance) - 1) != 0)
}
struct Binary32Finite { significand u64 exponent int }
fn binary32_finite(value u32) Binary32Finite {
	encoded := int((value >> 23) & 255)
	mut significand := u64(value & 0x7fffff)
	mut exponent := if encoded == 0 { -126 } else { encoded - 127 }
	if encoded != 0 { significand |= u64(1) << 23 }
	for significand != 0 && significand < u64(1) << 23 { significand <<= 1; exponent-- }
	return Binary32Finite{significand, exponent}
}
fn binary32_pack(sign u32, exponent int, significand u64) u32 {
	mut e := exponent; mut sig := significand
	if e < -126 { sig = binary32_jam(sig, -126 - e); e = -126 }
	mut fraction := sig >> 3; remainder := sig & 7
	if remainder > 4 || (remainder == 4 && fraction & 1 != 0) { fraction++ }
	if fraction >= u64(1) << 24 { fraction >>= 1; e++ }
	if e > 127 { return sign | 0x7f800000 }
	encoded := if fraction >= u64(1) << 23 { u32(e + 127) } else { u32(0) }
	return sign | (encoded << 23) | u32(fraction & 0x7fffff)
}
fn binary32_add(a u32, b u32) u32 {
	if binary32_is_nan(a) || binary32_is_nan(b) { return binary32_nan }
	x := a & 0x7fffffff; y := b & 0x7fffffff
	if x == 0x7f800000 || y == 0x7f800000 {
		if x == y && (a ^ b) & 0x80000000 != 0 { return binary32_nan }
		return if x == 0x7f800000 { a } else { b }
	}
	if x == 0 && y == 0 { return (a & b) & 0x80000000 }
	if x == 0 { return b }; if y == 0 { return a }
	large := if x >= y { a } else { b }; small := if x >= y { b } else { a }
	l := binary32_finite(large); s := binary32_finite(small)
	sign := large & 0x80000000
	mut exponent := l.exponent
	left := l.significand << 3; right := binary32_jam(s.significand << 3, l.exponent - s.exponent)
	mut significand := u64(0)
	if (large ^ small) & 0x80000000 == 0 {
		significand = left + right
		if significand >= u64(1) << 27 { significand = binary32_jam(significand, 1); exponent++ }
	} else {
		significand = left - right
		if significand == 0 { return 0 }
		for significand < u64(1) << 26 { significand <<= 1; exponent-- }
	}
	return binary32_pack(sign, exponent, significand)
}
fn binary32_binary(op u32, a u32, b u32) !u32 {
	if op !in [u32(0), 1, 2, 4, 6]! { return error('AIR binary32: unsupported operation') }
	if op == 0 { return binary32_add(a, b) }
	if op == 1 { return binary32_add(a, b ^ 0x80000000) }
	if op == 6 { return binary32_remainder(a, b) }
	if binary32_is_nan(a) || binary32_is_nan(b) { return binary32_nan }
	x := a & 0x7fffffff; y := b & 0x7fffffff; sign := (a ^ b) & 0x80000000
	if op == 2 {
		if (x == 0x7f800000 && y == 0) || (y == 0x7f800000 && x == 0) { return binary32_nan }
		if x == 0x7f800000 || y == 0x7f800000 { return sign | 0x7f800000 }
		if x == 0 || y == 0 { return sign }
		l := binary32_finite(a); r := binary32_finite(b)
		product := l.significand * r.significand
		wide := product >= u64(1) << 47
		return binary32_pack(sign, l.exponent + r.exponent + int(wide), binary32_jam(product, if wide { 21 } else { 20 }))
	}
	if (x == 0x7f800000 && y == 0x7f800000) || (x == 0 && y == 0) { return binary32_nan }
	if x == 0x7f800000 || y == 0 { return sign | 0x7f800000 }
	if x == 0 || y == 0x7f800000 { return sign }
	l := binary32_finite(a); r := binary32_finite(b)
	adjust := l.significand < r.significand
	numerator := l.significand << if adjust { 27 } else { 26 }
	quotient := (numerator / r.significand) | u64(numerator % r.significand != 0)
	return binary32_pack(sign, l.exponent - r.exponent - int(adjust), quotient)
}
// LLVM frem has fmod semantics: truncate the quotient toward zero, and keep
// the dividend's sign, including an exact zero. Reduce integer significands
// instead of rounding a quotient (which may overflow even for finite inputs).
fn binary32_remainder(a u32, b u32) u32 {
	x := a & 0x7fffffff; y := b & 0x7fffffff; sign := a & 0x80000000
	if binary32_is_nan(a) || binary32_is_nan(b) || x == 0x7f800000 || y == 0 { return binary32_nan }
	if x < y { return a } // Includes signed zero and a finite dividend / infinity.
	if x == y { return sign }
	l := binary32_finite(a); r := binary32_finite(b)
	mut remainder := l.significand
	// At most 276 iterations: normalized exponents range from -149 to 127.
	// Each subtraction leaves less than the divisor; the shift fits in 25 bits.
	for _ in 0 .. l.exponent - r.exponent {
		if remainder >= r.significand { remainder -= r.significand }
		remainder <<= 1
	}
	if remainder >= r.significand { remainder -= r.significand }
	if remainder == 0 { return sign }
	mut exponent := r.exponent
	for remainder < u64(1) << 23 { remainder <<= 1; exponent-- }
	// The exact remainder is representable, including subnormals. No quotient
	// rounding, host FP instruction, environment or allocation participates.
	return binary32_pack(sign, exponent, remainder << 3)
}
fn binary32_compare(predicate u32, a u32, b u32) !bool {
	if predicate > 15 { return error('AIR binary32: comparison predicate') }
	unord := binary32_is_nan(a) || binary32_is_nan(b)
	x := a & 0x7fffffff; y := b & 0x7fffffff
	equal := a == b || (x == 0 && y == 0)
	less := !equal && if (a ^ b) & 0x80000000 != 0 { a >> 31 != 0 } else if a >> 31 == 0 { x < y } else { x > y }
	return match predicate {
		0 { false } 1 { !unord && equal } 2 { !unord && !less && !equal }
		3 { !unord && !less } 4 { !unord && less } 5 { !unord && (less || equal) }
		6 { !unord && !equal } 7 { !unord } 8 { unord } 9 { unord || equal }
		10 { unord || (!less && !equal) } 11 { unord || !less }
		12 { unord || less } 13 { unord || less || equal } 14 { unord || !equal }
		else { true }
	}
}
