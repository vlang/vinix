// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// IEEE binary32 -> binary16, nearest/ties to even with gradual underflow.
// Reuse integer normalization and jam; no host FP cast or allocation.
fn binary16_from_binary32(value u32) u16 {
	sign := u16((value >> 16) & 0x8000); magnitude := value & 0x7fffffff
	if binary32_is_nan(value) { return 0x7e00 }
	if magnitude == 0x7f800000 { return sign | 0x7c00 }
	if magnitude == 0 { return sign }
	finite := binary32_finite(value)
	return binary16_pack(sign, finite.exponent, binary32_jam(finite.significand, 10))
}
// Every finite binary16 value has an exact binary32 representation.
// Conversion NaNs choose the preferred positive quiet NaN, as LLVM permits.
fn binary16_to_binary32(value u16) u32 {
	sign := u32(value & 0x8000) << 16; encoded := u32((value >> 10) & 31)
	mut fraction := u32(value & 0x3ff)
	if encoded == 31 { return if fraction == 0 { sign | 0x7f800000 } else { binary32_nan } }
	if encoded != 0 { return sign | ((encoded + 112) << 23) | (fraction << 13) }
	if fraction == 0 { return sign }
	mut exponent := -14
	for fraction < u32(1) << 10 { fraction <<= 1; exponent-- }
	return sign | (u32(exponent + 127) << 23) | ((fraction & 0x3ff) << 13)
}
fn binary16_from_integer(bits u32, signed bool, value u64) !u16 {
	if bits == 0 || bits > 64 { return error('AIR binary16: integer conversion width') }
	mask := constant_mask(bits); word := value & mask
	negative := signed && word & (u64(1) << (bits - 1)) != 0
	magnitude := if negative { (u64(0) - word) & mask } else { word }
	if magnitude == 0 { return 0 }
	mut scan := magnitude; mut exponent := 0
	for scan > 1 { scan >>= 1; exponent++ }
	// Eleven retained significand bits plus guard/round/sticky. Round once,
	// directly to half, including signed infinity when the result overflows.
	significand := if exponent <= 13 { magnitude << (13 - exponent) } else { binary32_jam(magnitude, exponent - 13) }
	return binary16_pack(if negative { u16(0x8000) } else { u16(0) }, exponent, significand)
}
fn binary16_to_integer(bits u32, signed bool, value u16) !IntegerValue {
	// Widening is exact for every finite half value. The existing integer-only
	// truncation/range checker also rejects infinities and all converted NaNs.
	return binary32_to_integer(bits, signed, binary16_to_binary32(value))!
}
