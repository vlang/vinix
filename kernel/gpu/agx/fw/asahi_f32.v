// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module fw

// The G13 InitData builders compute their float coefficients the way Asahi's
// software F32 does (drivers/gpu/drm/asahi/float.rs, Linux-Aurora bed544bdf),
// so every word matches the reference bit for bit. That arithmetic is not
// IEEE: it keeps a 33-bit mantissa, multiplies and divides with truncated
// operands, rounds exact ties up and flushes subnormals to zero. A correctly
// rounded result can differ from it in the last place.
//
// Values are binary32 bit patterns; the kernel has no floating point.

struct AsahiF32U {
mut:
	sign bool
	exp  i32
	frac i64
}

const asahi_f32_one = u32(0x3f80_0000)

fn asahi_f32_leading_zeros(value i64) i32 {
	if value < 0 {
		return 0
	}
	mut count := i32(64)
	mut rest := u64(value)
	for rest != 0 {
		rest >>= 1
		count--
	}
	return count
}

fn (value AsahiF32U) is_zero() bool {
	return value.frac == 0 || value.exp < -126
}

fn (value AsahiF32U) is_inf() bool {
	return value.exp > 127
}

// Leading one at bit 32, as F32U::norm().
fn (value AsahiF32U) norm() AsahiF32U {
	mut out := value
	zeros := asahi_f32_leading_zeros(out.frac)
	if zeros > 31 {
		out.frac <<= u32(zeros - 31)
		out.exp -= zeros - 31
	} else if zeros < 31 {
		out.frac >>= u32(31 - zeros)
		out.exp += 31 - zeros
	}
	if out.is_zero() {
		return AsahiF32U{
			sign: out.sign
		}
	}
	return out
}

fn asahi_f32_unpack(bits u32) AsahiF32U {
	return AsahiF32U{
		sign: bits & 0x8000_0000 != 0
		exp:  i32((bits >> 23) & 0xff) - 127
		frac: i64((bits & 0x7f_ffff) | 0x80_0000) << 9
	}.norm()
}

// ?u32 is none for an infinite result, which Asahi would publish as is: the
// builders never divide by zero, and nothing infinite goes to the firmware.
fn (value AsahiF32U) pack() ?u32 {
	mut out := value.norm()
	if !out.is_zero() {
		out.frac += 0x100
		out = out.norm()
	}
	sign := if out.sign { u32(0x8000_0000) } else { u32(0) }
	if out.is_inf() {
		return none
	}
	if out.is_zero() {
		return sign
	}
	return sign | (u32(out.exp + 127) << 23) | u32((out.frac >> 9) & 0x7f_ffff)
}

fn asahi_f32_from_u64(value u64) AsahiF32U {
	mut exp := i32(32)
	mut frac := value
	if frac >= u64(1) << 63 {
		exp = 31
		frac >>= 1
	}
	return AsahiF32U{
		exp:  exp
		frac: i64(frac)
	}.norm()
}

fn (mut value AsahiF32U) shr(shift i32) {
	if shift > 63 {
		value.exp = 0
		value.frac = 0
	} else {
		value.frac >>= u32(shift)
	}
}

fn asahi_f32_align(mut left AsahiF32U, mut right AsahiF32U) {
	if left.exp > right.exp {
		right.shr(left.exp - right.exp)
		right.exp = left.exp
	} else {
		left.shr(right.exp - left.exp)
		left.exp = right.exp
	}
}

fn asahi_f32_add(left AsahiF32U, right AsahiF32U) AsahiF32U {
	mut a := left
	mut b := right
	asahi_f32_align(mut a, mut b)
	if a.sign == b.sign {
		a.frac += b.frac
	} else {
		a.frac -= b.frac
	}
	if a.frac < 0 {
		a.sign = !a.sign
		a.frac = -a.frac
	}
	return a
}

fn asahi_f32_mul(left AsahiF32U, right AsahiF32U) AsahiF32U {
	return AsahiF32U{
		sign: left.sign != right.sign
		exp:  left.exp + right.exp
		frac: ((left.frac >> 8) * (right.frac >> 8)) >> 16
	}
}

fn asahi_f32_div(left AsahiF32U, right AsahiF32U) ?AsahiF32U {
	if right.frac == 0 || left.is_inf() {
		return none
	}
	return AsahiF32U{
		sign: left.sign != right.sign
		exp:  left.exp - right.exp
		frac: (left.frac << 24) / (right.frac >> 8)
	}
}

// F32::from(u32).
fn firmware_u32_to_f32_bits(value u32) ?u32 {
	return asahi_f32_from_u64(value).pack()
}

// F32::from(numerator) / F32::from(denominator); with a numerator of one this
// is the reference's f32!(1.0) / denominator.into().
fn firmware_fraction_to_f32_bits(numerator u32, denominator u32) ?u32 {
	return (asahi_f32_div(asahi_f32_from_u64(numerator), asahi_f32_from_u64(denominator))?).pack()
}

// F32::from(numerator) / divisor, for a divisor given as a binary32 constant.
fn firmware_u32_div_f32_bits(numerator u32, divisor u32) ?u32 {
	return (asahi_f32_div(asahi_f32_from_u64(numerator), asahi_f32_unpack(divisor))?).pack()
}

fn firmware_f32_multiply_bits(left u32, right u32) ?u32 {
	return asahi_f32_mul(asahi_f32_unpack(left), asahi_f32_unpack(right)).pack()
}

// f32!(1.0) - value.
fn firmware_f32_one_minus_bits(value u32) ?u32 {
	return asahi_f32_add(asahi_f32_unpack(asahi_f32_one), asahi_f32_unpack(value ^ 0x8000_0000)).pack()
}
