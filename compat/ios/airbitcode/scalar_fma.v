// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Exact finite FMA on a 2^-298 grid. Binary32 coefficients have at most 24
// bits and powers -149..104: their product occupies bits 0..553, and the
// addend bits 149..425. Nine fixed stack limbs retain the entire sum before
// one rounding. Half values fit the same grid. No host FP or allocation.
fn scalar_fma_coefficient(value u64, fraction_bits int, bias int) (u64, int) {
	encoded := int(value >> fraction_bits)
	return if encoded == 0 { value } else { (value & ((u64(1) << fraction_bits) - 1)) | (u64(1) << fraction_bits) }, if encoded == 0 { 1 - bias - fraction_bits } else { encoded - bias - fraction_bits }
}
fn scalar_fma_place(mut limbs [9]u64, coefficient u64, shift int) {
	word := shift / 64; offset := shift % 64
	limbs[word] = coefficient << offset
	if offset != 0 && word + 1 < 9 { limbs[word + 1] = coefficient >> (64 - offset) }
}
fn scalar_fma(bits u32, a u64, b u64, c u64) !u64 {
	if bits !in [u32(16), 32]! { return error('AIR FMA: floating width') }
	sign_mask := u64(1) << (bits - 1); x := a & (sign_mask - 1); y := b & (sign_mask - 1); z := c & (sign_mask - 1)
	inf := if bits == 16 { u64(0x7c00) } else { u64(0x7f800000) }
	nan := if bits == 16 { u64(0x7e00) } else { u64(0x7fc00000) }
	product_sign := (a ^ b) & sign_mask; addend_sign := c & sign_mask
	if x > inf || y > inf || z > inf || (x == inf && y == 0) || (y == inf && x == 0) { return nan }
	if x == inf || y == inf { return if z == inf && product_sign != addend_sign { nan } else { product_sign | inf } }
	if z == inf { return addend_sign | inf }
	if x == 0 || y == 0 { return if z == 0 { product_sign & addend_sign } else { c } }
	fraction_bits := if bits == 16 { 10 } else { 23 }; bias := if bits == 16 { 15 } else { 127 }
	ac, ap := scalar_fma_coefficient(x, fraction_bits, bias)
	bc, bp := scalar_fma_coefficient(y, fraction_bits, bias)
	cc, cp := scalar_fma_coefficient(z, fraction_bits, bias)
	mut left := [9]u64{}; mut right := [9]u64{}
	scalar_fma_place(mut left, ac * bc, ap + bp + 298)
	scalar_fma_place(mut right, cc, cp + 298)
	mut sign := product_sign
	if product_sign == addend_sign {
		mut carry := u64(0)
		for i in 0 .. 9 {
			sum := left[i] + right[i]; next := sum + carry
			carry = u64(sum < left[i] || next < sum); left[i] = next
		}
	} else {
		mut order := 0
		for n in 0 .. 9 { i := 8 - n; if left[i] != right[i] { order = if left[i] > right[i] { 1 } else { -1 }; break } }
		if order == 0 { return 0 } // Exact cancellation is +0 in nearest mode.
		if order < 0 { sign = addend_sign }
		mut borrow := u64(0)
		for i in 0 .. 9 {
			large := if order > 0 { left[i] } else { right[i] }; small := if order > 0 { right[i] } else { left[i] }
			difference := large - small; next := difference - borrow
			borrow = u64(large < small || difference < borrow); left[i] = next
		}
	}
	mut highest := -1
	for n in 0 .. 9 {
		i := 8 - n
		if left[i] == 0 { continue }
		mut word := left[i]; highest = i * 64
		for word > 1 { word >>= 1; highest++ } // At most 63 steps.
		break
	}
	if highest < 0 { return sign }
	shift := highest - fraction_bits - 3
	mut extended := u64(0)
	if shift < 0 { extended = left[0] << -shift }
	else {
		word := shift / 64; offset := shift % 64
		extended = left[word] >> offset
		if offset != 0 && word + 1 < 9 { extended |= left[word + 1] << (64 - offset) }
		mut sticky := offset != 0 && left[word] & ((u64(1) << offset) - 1) != 0
		for i in 0 .. word { if left[i] != 0 { sticky = true } }
		extended |= u64(sticky)
	}
	return if bits == 16 { u64(binary16_pack(u16(sign), highest - 298, extended)) } else { u64(binary32_pack(u32(sign), highest - 298, extended)) }
}
