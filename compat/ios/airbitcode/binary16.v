// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const binary16_nan = u16(0x7e00)
fn binary16_is_nan(value u16) bool { return value & 0x7fff > 0x7c00 }
struct Binary16Finite { significand u64 exponent int }
fn binary16_finite(value u16) Binary16Finite {
	encoded := int((value >> 10) & 31)
	mut significand := u64(value & 0x3ff)
	mut exponent := if encoded == 0 { -14 } else { encoded - 15 }
	if encoded != 0 { significand |= u64(1) << 10 }
	for significand != 0 && significand < u64(1) << 10 { significand <<= 1; exponent-- }
	return Binary16Finite{significand, exponent}
}
fn binary16_pack(sign u16, exponent int, significand u64) u16 {
	mut e := exponent; mut sig := significand
	if e < -14 { sig = binary32_jam(sig, -14 - e); e = -14 }
	mut fraction := sig >> 3; remainder := sig & 7
	if remainder > 4 || (remainder == 4 && fraction & 1 != 0) { fraction++ }
	if fraction >= u64(1) << 11 { fraction >>= 1; e++ }
	if e > 15 { return sign | 0x7c00 }
	encoded := if fraction >= u64(1) << 10 { u16(e + 15) } else { u16(0) }
	return sign | (encoded << 10) | u16(fraction & 0x3ff)
}
fn binary16_add(a u16, b u16) u16 {
	if binary16_is_nan(a) || binary16_is_nan(b) { return binary16_nan }
	x := a & 0x7fff; y := b & 0x7fff
	if x == 0x7c00 || y == 0x7c00 {
		if x == y && (a ^ b) & 0x8000 != 0 { return binary16_nan }
		return if x == 0x7c00 { a } else { b }
	}
	if x == 0 && y == 0 { return (a & b) & 0x8000 }
	if x == 0 { return b }; if y == 0 { return a }
	large := if x >= y { a } else { b }; small := if x >= y { b } else { a }
	l := binary16_finite(large); s := binary16_finite(small); sign := large & 0x8000
	mut exponent := l.exponent
	left := l.significand << 3; right := binary32_jam(s.significand << 3, l.exponent - s.exponent)
	mut significand := u64(0)
	if (large ^ small) & 0x8000 == 0 {
		significand = left + right
		if significand >= u64(1) << 14 { significand = binary32_jam(significand, 1); exponent++ }
	} else {
		significand = left - right
		if significand == 0 { return 0 }
		for significand < u64(1) << 13 { significand <<= 1; exponent-- }
	}
	return binary16_pack(sign, exponent, significand)
}
fn binary16_remainder(a u16, b u16) u16 {
	x := a & 0x7fff; y := b & 0x7fff; sign := a & 0x8000
	if binary16_is_nan(a) || binary16_is_nan(b) || x == 0x7c00 || y == 0 { return binary16_nan }
	if x < y { return a }; if x == y { return sign }
	l := binary16_finite(a); r := binary16_finite(b)
	mut remainder := l.significand
	// At most 39 exponent steps. The residual stays below twice the divisor.
	for _ in 0 .. l.exponent - r.exponent {
		if remainder >= r.significand { remainder -= r.significand }
		remainder <<= 1
	}
	if remainder >= r.significand { remainder -= r.significand }
	if remainder == 0 { return sign }
	mut exponent := r.exponent
	for remainder < u64(1) << 10 { remainder <<= 1; exponent-- }
	return binary16_pack(sign, exponent, remainder << 3)
}
fn binary16_binary(op u32, a u16, b u16) !u16 {
	if op !in [u32(0), 1, 2, 4, 6]! { return error('AIR binary16: unsupported operation') }
	if op == 0 { return binary16_add(a, b) }
	if op == 1 { return binary16_add(a, b ^ 0x8000) }
	if op == 6 { return binary16_remainder(a, b) }
	if binary16_is_nan(a) || binary16_is_nan(b) { return binary16_nan }
	x := a & 0x7fff; y := b & 0x7fff; sign := (a ^ b) & 0x8000
	if op == 2 {
		if (x == 0x7c00 && y == 0) || (y == 0x7c00 && x == 0) { return binary16_nan }
		if x == 0x7c00 || y == 0x7c00 { return sign | 0x7c00 }
		if x == 0 || y == 0 { return sign }
		l := binary16_finite(a); r := binary16_finite(b); product := l.significand * r.significand
		wide := product >= u64(1) << 21
		return binary16_pack(sign, l.exponent + r.exponent + int(wide), binary32_jam(product, if wide { 8 } else { 7 }))
	}
	if (x == 0x7c00 && y == 0x7c00) || (x == 0 && y == 0) { return binary16_nan }
	if x == 0x7c00 || y == 0 { return sign | 0x7c00 }
	if x == 0 || y == 0x7c00 { return sign }
	l := binary16_finite(a); r := binary16_finite(b); adjust := l.significand < r.significand
	numerator := l.significand << if adjust { 14 } else { 13 }
	quotient := (numerator / r.significand) | u64(numerator % r.significand != 0)
	return binary16_pack(sign, l.exponent - r.exponent - int(adjust), quotient)
}
fn binary16_compare(predicate u32, a u16, b u16) !bool {
	// Exact widening preserves finite ordering and zero signs. Both NaN classes
	// are unordered; their sign/payload does not participate in a comparison.
	return binary32_compare(predicate, binary16_to_binary32(a), binary16_to_binary32(b))!
}
