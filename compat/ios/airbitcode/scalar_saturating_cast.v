// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Preserve all existing floating/integer cache identities; conversion overloads
// have two independent widths and occupy a separate, bounded suffix.
const scalar_conversion_cache_base = 1768
const scalar_intrinsic_cache_slots = scalar_air_half_float_cache_base + 7

fn scalar_saturating_cast(id ScalarIntrinsic) bool { return id in [.fptosi_sat, .fptoui_sat]! }
fn scalar_saturating_cast_overload(name string, id ScalarIntrinsic) !(u32, u32) {
	if !scalar_saturating_cast(id) { return error('AIR intrinsic: saturating conversion family') }
	prefix := if id == .fptosi_sat { 'llvm.fptosi.sat.i' } else { 'llvm.fptoui.sat.i' }
	if !name.starts_with(prefix) || name.len < prefix.len + 5 || name.len > prefix.len + 6 || name[prefix.len] == `0` { return error('AIR intrinsic: saturating conversion spelling') }
	suffix := name.len - 4
	if name[suffix] != `.` || name[suffix + 1] != `f` || !((name[suffix + 2] == `1` && name[suffix + 3] == `6`) || (name[suffix + 2] == `3` && name[suffix + 3] == `2`)) { return error('AIR intrinsic: saturating conversion floating width') }
	mut bits := u32(0)
	for i in prefix.len .. suffix {
		if name[i] < `0` || name[i] > `9` { return error('AIR intrinsic: saturating conversion digits') }
		bits = bits * 10 + u32(name[i] - `0`)
	}
	if bits < 1 || bits > 64 { return error('AIR intrinsic: saturating conversion integer width') }
	return bits, if name[suffix + 2] == `1` { u32(16) } else { u32(32) }
}
fn scalar_saturating_cast_key(id ScalarIntrinsic, source u32, dest u32) !int {
	if !scalar_saturating_cast(id) || source !in [u32(16), 32]! || dest < 1 || dest > 64 { return error('AIR intrinsic: saturating conversion key/width') }
	return scalar_conversion_cache_base + int(id == .fptoui_sat) * 128 + int(source == 16) * 64 + int(dest) - 1
}
fn scalar_saturating_cast_value(id ScalarIntrinsic, source u32, dest u32, word u64) !u64 {
	scalar_saturating_cast_key(id, source, dest)!
	// Widening half is exact for finite values. Both NaN classes map to zero,
	// so widening's permitted canonical NaN has no observable payload effect.
	value := if source == 16 { binary16_to_binary32(u16(word)) } else { u32(word) }
	signed := id == .fptosi_sat
	converted := binary32_to_integer(dest, signed, value)!
	if !converted.poison { return converted.value }
	if value & 0x7fffffff > 0x7f800000 { return 0 }
	negative := value >> 31 != 0
	if signed { sign := u64(1) << (dest - 1); return if negative { sign } else { sign - 1 } }
	return if negative { u64(0) } else { constant_mask(dest) }
}
