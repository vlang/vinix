// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_air_float_names_slots_and_existing_evaluators() {
	assert scalar_air_float_cache_base == 2168 && scalar_intrinsic_cache_slots == 2172
	ids := [ScalarIntrinsic.fabs, .floor, .ceil, .trunc]!
	for i, name in ['air.fabs.f32', 'air.floor.f32', 'air.ceil.f32', 'air.trunc.f32'] {
		id, slot := air_float_intrinsic(name)!
		assert id == ids[i] && slot == i && scalar_intrinsic_name(name)! == id
		assert scalar_intrinsic_arity(id) == 1 && !scalar_integer_intrinsic(id)
		if _, _ := air_integer_intrinsic(name) { assert false }
	}
	for name in ['air.fabs.f16', 'air.floor.f64', 'air.ceil.v2f32', 'air.trunc.i32', 'air.floor.f032', 'air.floor.f+32', 'air.floor.f32.spoof', 'air.fast_floor.f32', 'air.sqrt.f32', 'air.sin.f32'] {
		if _ := scalar_intrinsic_name(name) { assert false, name }
	}
	assert scalar_intrinsic_value(.fabs, 32, 0xff812345, 0)! == 0x7f812345
	assert scalar_intrinsic_value(.floor, 32, 0x80000001, 0)! == 0xbf800000
	assert scalar_intrinsic_value(.ceil, 32, 1, 0)! == 0x3f800000
	assert scalar_intrinsic_value(.trunc, 32, 0x80000001, 0)! == 0x80000000
	println('AIR-FLOAT-NAMES: four exact f32 names, appended slots, unary identities, bit/rounding boundaries and width/vector/family/spelling guards PASS')
}
