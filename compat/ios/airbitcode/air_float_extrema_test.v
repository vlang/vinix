// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn air_number_reference(minimum bool, a u32, b u32) u32 {
	xnan := a & 0x7fffffff > 0x7f800000; ynan := b & 0x7fffffff > 0x7f800000
	if xnan && ynan { return 0x7fc00000 }
	if xnan { return b }; if ynan { return a }
	if a & 0x7fffffff == 0 && b & 0x7fffffff == 0 { return a }
	xkey := if a >> 31 != 0 { ~a } else { a | u32(0x80000000) }
	ykey := if b >> 31 != 0 { ~b } else { b | u32(0x80000000) }
	return if (xkey < ykey) == minimum { a } else { b }
}

fn test_air_float_extrema_identity_values_and_first_zero() {
	assert scalar_intrinsic_cache_slots == 2203
	for i, name in ['air.fmin.f32', 'air.fmax.f32'] {
		id, slot := air_float_intrinsic(name)!
		assert id == if i == 0 { ScalarIntrinsic.air_fmin } else { ScalarIntrinsic.air_fmax }
		assert slot == i + 8 && scalar_air_float_cache_base + slot == 2176 + i
		assert scalar_intrinsic_name(name)! == id && scalar_intrinsic_arity(id) == 2 && !scalar_integer_intrinsic(id)
		if _, _ := air_integer_intrinsic(name) { assert false }
		for bits in [u32(0),64]! { if _ := scalar_intrinsic_value(id, bits, 0, 0) { assert false } }
	}
	for name in ['air.fmin.f64','air.fmax.f64','air.fmin.v2f32','air.fmax.i32','air.fmin.f032','air.fmax.f+32','air.fmin.f32.spoof','air.fast_fmin.f32','air.fast_fmax.f32','air.min.f32','air.minnum.f32','air.clamp.f64'] {
		if _ := scalar_intrinsic_name(name) { assert false, name }
	}
	assert scalar_intrinsic_value(.air_fmin, 32, 0, 0x80000000)! == 0
	assert scalar_intrinsic_value(.air_fmin, 32, 0x80000000, 0)! == 0x80000000
	assert scalar_intrinsic_value(.air_fmax, 32, 0x80000000, 0)! == 0x80000000
	assert scalar_intrinsic_value(.air_fmax, 32, 0, 0x80000000)! == 0
	assert scalar_intrinsic_value(.minnum, 32, 0, 0x80000000)! == 0x80000000
	assert scalar_intrinsic_value(.maxnum, 32, 0x80000000, 0)! == 0
	mut checks := 0
	edges := [u32(0),0x80000000,1,0x80000001,0x007fffff,0x807fffff,0x00800000,0x80800000,0x3f800000,0xbf800000,0x3f800001,0xbf800001,0x7f7fffff,0xff7fffff,0x7f800000,0xff800000,0x7f800001,0xff800001,0x7fc00000,0xffc00000,0x7fc12345,0xffc12345,0x3f000000,0xbf000000]!
	for sample in 0..65536 {
		a := if sample < 576 { edges[sample / 24] } else { u32(sample) * u32(0x9e3779b9) }
		b := if sample < 576 { edges[sample % 24] } else if sample % 4 == 0 { a } else { u32(sample) * u32(0x85ebca6b) ^ u32(0xa5a5a5a5) }
		for minimum in [false,true]! { for swapped in [false,true]! {
			x := if swapped { b } else { a }; y := if swapped { a } else { b }
			id := if minimum { ScalarIntrinsic.air_fmin } else { ScalarIntrinsic.air_fmax }
			assert scalar_intrinsic_value(id, 32, u64(x) | u64(0x12345678)<<32, u64(y) | u64(0x87654321)<<32)! == air_number_reference(minimum,x,y)
			checks++
		} }
	}
	assert checks == 262144
	println('AIR-FLOAT-EXTREMA-UNIT: ${checks} independent ordered-key comparisons, both orders, exact names/slots/widths, NaN preference, first signed zero and preserved LLVM zero ordering PASS')
}

fn air_half_number_reference(minimum bool, a u16, b u16) u16 {
 xnan := a & 0x7fff > 0x7c00; ynan := b & 0x7fff > 0x7c00
 if xnan && ynan { return 0x7e00 }
 if xnan { return b }; if ynan { return a }
 if a & 0x7fff == 0 && b & 0x7fff == 0 { return a }
 xkey := if a >> 15 != 0 { ~a } else { a | u16(0x8000) }
 ykey := if b >> 15 != 0 { ~b } else { b | u16(0x8000) }
 return if (xkey < ykey) == minimum { a } else { b }
}
fn test_air_half_extrema_all_encodings_against_boundary_peers() {
 assert scalar_intrinsic_cache_slots == 2203
 for i, name in ['air.fmin.f16','air.fmax.f16'] {
  id, slot := air_float_intrinsic(name)!
  assert id == if i==0 {ScalarIntrinsic.air_fmin}else{ScalarIntrinsic.air_fmax}
  assert scalar_air_float_cache_base+slot == 2201+i && scalar_intrinsic_name(name)! == id
  assert scalar_intrinsic_arity(id)==2 && !scalar_integer_intrinsic(id)
 }
 edges := [u16(0),0x8000,1,0x8001,0x03ff,0x83ff,0x0400,0x8400,0x3c00,0xbc00,0x3c01,0xbc01,0x7bff,0xfbff,0x7c00,0xfc00,0x7c01,0xfc01,0x7e00,0xfe00,0x7e45,0xfe45,0x3800,0xb800]!
 mut checks := 0
 for raw in 0..65536 {for peer in edges {for minimum in [false,true]! {for swapped in [false,true]! {
  a := if swapped {peer}else{u16(raw)}; b := if swapped {u16(raw)}else{peer}
  id := if minimum {ScalarIntrinsic.air_fmin}else{ScalarIntrinsic.air_fmax}
  assert scalar_intrinsic_value(id,16,u64(a)|~u64(0xffff),u64(b)|~u64(0xffff))! == air_half_number_reference(minimum,a,b)
  checks++
 }}}}
 assert checks == 6291456
 assert scalar_intrinsic_value(.air_fmin,16,0,0x8000)! == 0
 assert scalar_intrinsic_value(.air_fmax,16,0x8000,0)! == 0x8000
 assert scalar_intrinsic_value(.minnum,16,0,0x8000)! == 0x8000
 assert scalar_intrinsic_value(.maxnum,16,0x8000,0)! == 0
 for family in ['fmin','fmax'] {for suffix in ['f016','f+16','f16.spoof','v2f16','f64','i16'] {
  if _ := scalar_intrinsic_name('air.${family}.${suffix}') { assert false }
 }}
 for bits in [u32(0),1,64]! {if _ := scalar_air_float_extremum(.air_fmin,bits,0,0) {assert false}}
 println('AIR-HALF-EXTREMA: two exact binary identities, stable old keys, 6291456 independent ordered-key checks across every half encoding, 24 boundary peers and both operand orders, masking, NaN preference and AIR/LLVM signed-zero policies PASS')
}
