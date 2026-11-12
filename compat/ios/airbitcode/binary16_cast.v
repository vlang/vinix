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
	mut exponent := finite.exponent
	distance := 10 + if exponent < -14 { -14 - exponent } else { 0 }
	significand := binary32_jam(finite.significand, distance)
	if exponent < -14 { exponent = -14 }
	mut fraction := significand >> 3; remainder := significand & 7
	if remainder > 4 || (remainder == 4 && fraction & 1 != 0) { fraction++ }
	if fraction >= u64(1) << 11 { fraction >>= 1; exponent++ }
	if exponent > 15 { return sign | 0x7c00 }
	encoded := if fraction >= u64(1) << 10 { u16(exponent + 15) } else { u16(0) }
	return sign | (encoded << 10) | u16(fraction & 0x3ff)
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
