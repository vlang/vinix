// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_air_integer_intrinsic_identity() {
	assert scalar_air_integer_cache_base == 2154 && scalar_intrinsic_cache_slots == 2156
	for i, name in ['air.popcount.i32', 'air.reverse_bits.i32'] {
		id, slot := air_integer_intrinsic(name)!
		assert slot == i && id == if i == 0 { ScalarIntrinsic.ctpop } else { ScalarIntrinsic.bitreverse }
		assert scalar_intrinsic_name(name)! == id && scalar_intrinsic_arity(id) == 1
		assert scalar_integer_intrinsic_width(name, id)! == 32
		if _ := scalar_integer_intrinsic_width(name, if i == 0 { ScalarIntrinsic.bitreverse } else { ScalarIntrinsic.ctpop }) { assert false }
	}
	for name in ['air.popcount.i1', 'air.popcount.i16', 'air.popcount.i64', 'air.popcount.i032', 'air.popcount.i+32', 'air.popcount.v2i32', 'air.popcount.f32', 'air.popcount.i32.spoof', 'air.reverse_bits.i0', 'air.reverse_bits.i16', 'air.reverse_bits.i64', 'air.reverse_bits.v4i32', 'air.reverse_bits.i32.spoof', 'air.ctpop.i32', 'air.bitreverse.i32', 'air.clz.i32'] {
		if _ := scalar_intrinsic_name(name) { assert false, name }
	}
	println('AIR-INTEGER-NAMES: two exact i32 names, separate appended slots, unary identity and unsupported width/vector/family/spelling guards PASS')
}
