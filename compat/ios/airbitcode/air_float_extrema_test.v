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
	assert scalar_intrinsic_cache_slots == 2201
	for i, name in ['air.fmin.f32', 'air.fmax.f32'] {
		id, slot := air_float_intrinsic(name)!
		assert id == if i == 0 { ScalarIntrinsic.air_fmin } else { ScalarIntrinsic.air_fmax }
		assert slot == i + 8 && scalar_air_float_cache_base + slot == 2176 + i
		assert scalar_intrinsic_name(name)! == id && scalar_intrinsic_arity(id) == 2 && !scalar_integer_intrinsic(id)
		if _, _ := air_integer_intrinsic(name) { assert false }
		for bits in [u32(16), 64]! { if _ := scalar_intrinsic_value(id, bits, 0, 0) { assert false } }
	}
	for name in ['air.fmin.f16','air.fmax.f64','air.fmin.v2f32','air.fmax.i32','air.fmin.f032','air.fmax.f+32','air.fmin.f32.spoof','air.fast_fmin.f32','air.fast_fmax.f32','air.min.f32','air.minnum.f32','air.clamp.f64'] {
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
