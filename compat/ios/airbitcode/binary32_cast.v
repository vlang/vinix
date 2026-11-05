// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn binary32_from_integer(bits u32, signed bool, value u64) !u32 {
	if bits == 0 || bits > 64 { return error('AIR binary32: integer conversion width') }
	mask := constant_mask(bits); word := value & mask
	negative := signed && word & (u64(1) << (bits - 1)) != 0
	magnitude := if negative { (u64(0) - word) & mask } else { word }
	if magnitude == 0 { return 0 }
	mut scan := magnitude; mut exponent := 0
	for scan > 1 { scan >>= 1; exponent++ }
	significand := if exponent <= 26 { magnitude << (26 - exponent) } else { binary32_jam(magnitude, exponent - 26) }
	return binary32_pack(if negative { u32(0x80000000) } else { u32(0) }, exponent, significand)
}
fn binary32_to_integer(bits u32, signed bool, value u32) !IntegerValue {
	if bits == 0 || bits > 64 { return error('AIR binary32: integer conversion width') }
	abs := value & 0x7fffffff
	if abs >= 0x7f800000 { return IntegerValue{poison: true} }
	if abs == 0 { return IntegerValue{} }
	finite := binary32_finite(value)
	if finite.exponent < 0 { return IntegerValue{} } // Negative fractions also truncate to zero.
	if finite.exponent >= 64 { return IntegerValue{poison: true} }
	magnitude := if finite.exponent >= 23 { finite.significand << (finite.exponent - 23) } else { finite.significand >> (23 - finite.exponent) }
	negative := value >> 31 != 0; mask := constant_mask(bits)
	if signed {
		sign := u64(1) << (bits - 1); limit := if negative { sign } else { sign - 1 }
		if magnitude > limit { return IntegerValue{poison: true} }
	} else if negative || magnitude > mask { return IntegerValue{poison: true} }
	return IntegerValue{value: if negative { (u64(0) - magnitude) & mask } else { magnitude }}
}
