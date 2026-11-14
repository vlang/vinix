// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Decode a rational significand and scale it with bounded arithmetic. This
// reference does not use the production float unpacker or cast range checker.
fn saturation_expected(source u32, dest u32, signed bool, word u64) u64 {
	fraction_bits := if source == 16 { u32(10) } else { u32(23) }
	exponent_bits := if source == 16 { u32(5) } else { u32(8) }
	bias := if source == 16 { 15 } else { 127 }
	fraction := word & ((u64(1) << fraction_bits) - 1)
	exponent := (word >> fraction_bits) & ((u64(1) << exponent_bits) - 1)
	negative := word & (u64(1) << (source - 1)) != 0
	if exponent == (u64(1) << exponent_bits) - 1 && fraction != 0 { return 0 }
	if !signed && negative { return 0 }
	sign := u64(1) << (dest - 1)
	limit := if signed { if negative { sign } else { sign - 1 } } else { constant_mask(dest) }
	mut magnitude := fraction | if exponent != 0 { u64(1) << fraction_bits } else { u64(0) }
	mut power := int(if exponent == 0 { u64(1) } else { exponent }) - bias - int(fraction_bits)
	if exponent == (u64(1) << exponent_bits) - 1 { magnitude = limit } else if power < 0 {
		magnitude = if power <= -64 { u64(0) } else { magnitude >> u32(-power) }
	} else { for power > 0 { if magnitude > limit / 2 { magnitude = limit; break }; magnitude *= 2; power-- } }
	if magnitude > limit { magnitude = limit }
	return if negative { (u64(0) - magnitude) & constant_mask(dest) } else { magnitude }
}
fn test_saturating_cast_all_half_and_float_boundaries() {
	mut checks := 0
	for dest in u32(1) .. 65 { for id in [ScalarIntrinsic.fptosi_sat, .fptoui_sat]! {
		for word in u64(0) .. 65536 { assert scalar_saturating_cast_value(id, 16, dest, word)! == saturation_expected(16, dest, id == .fptosi_sat, word); checks++ }
		for sample in u32(0) .. 4096 {
			// Every sign/exponent with fraction endpoints and reproducible patterns.
			word := (sample % 512) << 23 | match sample / 512 { 0 { u32(0) } 1 { u32(1) } 2 { u32(0x7fffff) } 3 { u32(0x400000) } else { (sample * u32(0x1f123bb5)) & 0x7fffff } }
			assert scalar_saturating_cast_value(id, 32, dest, word)! == saturation_expected(32, dest, id == .fptosi_sat, word); checks++
		}
	} }
	assert checks == 8912896
	println('AIR-SATURATING-CAST-VALUES: ${checks} independent rational checks, all half encodings and float sign/exponent/fraction boundaries, signed/unsigned i1-i64, NaNs/infinities/zeros/subnormals/fractions/clamping PASS')
}
fn test_saturating_cast_overloads_and_cache() {
	mut seen := [scalar_intrinsic_cache_slots]bool{}
	mut count := 0
	for width in u32(1) .. 65 { for source in [u32(16), 32]! { for id in [ScalarIntrinsic.fptosi_sat, .fptoui_sat]! {
		op := if id == .fptosi_sat { 'fptosi' } else { 'fptoui' }; name := 'llvm.${op}.sat.i${width}.f${source}'
		assert scalar_intrinsic_name(name)! == id && scalar_intrinsic_arity(id) == 1
		i, f := scalar_saturating_cast_overload(name, id)!; assert i == width && f == source
		key := scalar_saturating_cast_key(id, source, width)!; assert key >= 1768 && key < seen.len && !seen[key]; seen[key] = true; count++
		unsafe { name.free() }
	} } }
	assert count == 256
	for name in ['llvm.fptosi.sat.i0.f32', 'llvm.fptoui.sat.i65.f16', 'llvm.fptosi.sat.i01.f32', 'llvm.fptosi.sat.i+1.f32', 'llvm.fptosi.sat.i1x.f32', 'llvm.fptosi.sat.i1.f64', 'llvm.fptosi.sat.i1.bf16', 'llvm.fptosi.sat.v2i32.v2f32', 'llvm.fptosi.sat.i32.f32.spoof', 'air.fptosi.sat.i32.f32', 'llvm.fptosi.sat.i32', 'llvm.fptosi.sat.i128.f32'] { if _ := scalar_intrinsic_name(name) { assert false, 'unsupported overload admitted' } }
	for id in [ScalarIntrinsic.fptosi_sat, .fptoui_sat]! { for source in [u32(0), 15, 64]! { if _ := scalar_saturating_cast_value(id, source, 32, 0) { assert false, 'floating width' } }; for dest in [u32(0), 65]! { if _ := scalar_saturating_cast_value(id, 32, dest, 0) { assert false, 'integer width' } } }
	if _ := scalar_saturating_cast_value(.trunc, 32, 32, 0) { assert false, 'wrong family' }
	if _ := scalar_intrinsic_value(.fptosi_sat, 32, 0, 0) { assert false, 'single-width evaluator' }
	println('AIR-SATURATING-CAST-OVERLOADS: 256 distinct cache identities after existing families, strict names, width/family guards and unary arity PASS')
}
