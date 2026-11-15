// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn vector_shift_reference(signed bool, width u32, value u64, amount u64) IntegerValue {
	mask := constant_mask(width)
	x := value & mask
	shift := amount & mask
	if shift >= u64(width) { return IntegerValue{ poison: true } }
	if !signed {
		mut v := x
		for _ in u64(0) .. shift {
			if v > mask - v { return IntegerValue{ value: mask } }
			v += v
		}
		return IntegerValue{ value: v }
	}
	sign := u64(1) << (width - 1)
	maximum := i64(sign - 1)
	minimum := -maximum - 1
	mut v := if x & sign == 0 { i64(x) } else { -i64((~x) & mask) - 1 }
	for _ in u64(0) .. shift {
		if v > maximum / 2 { return IntegerValue{ value: u64(maximum) } }
		if v < minimum / 2 { return IntegerValue{ value: u64(minimum) & mask } }
		v += v
	}
	return IntegerValue{ value: u64(v) & mask }
}

fn test_vector_saturating_shift_values() {
	mut comparisons := 0
	mut poisoned := 0
	for id in [ScalarIntrinsic.sshl_sat, .ushl_sat]! {
		for width in u32(1) .. 65 {
			mask := constant_mask(width)
			sign := u64(1) << (width - 1)
			for n in 1 .. 17 {
				for sample in 0 .. int(width + 3) {
					mut a := ScalarVectorValue{}
					mut b := a
					for lane in 0 .. n {
						k := sample + lane
						a.lanes[lane] = IntegerValue{ value: (if k % 4 == 0 {
							sign
						} else if k % 4 == 1 {
							sign - 1
						} else if k % 4 == 2 {
							u64(0)
						} else {
							u64(k) * u64(0x9e3779b97f4a7c15)
						}) | ~mask }
						b.lanes[lane] = IntegerValue{ value: u64(k % int(width + 2)) | ~mask }
					}
					before_a := a
					before_b := b
					result := saturating_shift_intrinsic_vector(id, a, b, width, n)!
					for lane in 0 .. n {
						expected := vector_shift_reference(id == .sshl_sat, width, a.lanes[lane].value, b.lanes[lane].value)
						assert result.lanes[lane] == expected
						if expected.poison { poisoned++ }
						comparisons++
					}
					assert a == before_a && b == before_b
				}
			}
			samples := if width <= 8 { int(u64(1) << (width * 2)) } else { 4096 }
			for chunk in 0 .. (samples + 15) / 16 {
				mut a := ScalarVectorValue{}
				mut b := a
				for lane in 0 .. 16 {
					k := u64((chunk * 16 + lane) % samples)
					a.lanes[lane] = IntegerValue{ value: (if width <= 8 {
						k & mask
					} else {
						k * u64(0x9e3779b97f4a7c15)
					}) | ~mask }
					b.lanes[lane] = IntegerValue{ value: (if width <= 8 {
						k >> width
					} else {
						k % u64(width + 2)
					}) | ~mask }
				}
				result := saturating_shift_intrinsic_vector(id, a, b, width, 16)!
				for lane in 0 .. 16 {
					expected := vector_shift_reference(id == .sshl_sat, width, a.lanes[lane].value, b.lanes[lane].value)
					assert result.lanes[lane] == expected
					comparisons++
					if expected.poison { poisoned++ }
				}
			}
		}
	}
	assert comparisons == 1251520 && poisoned == 232928
	println('VECTOR-SAT-SHIFT: ${comparisons} independent checked-doubling value/tag comparisons (${poisoned} poison), all widths/shapes, narrow pairs, wide patterns, masking and snapshots PASS')
}

fn test_vector_saturating_shift_states_and_guards() {
	mut checks := 0
	for id in [ScalarIntrinsic.sshl_sat, .ushl_sat]! {
		for w in u32(1) .. 65 {
			for n in 1 .. 17 {
				for input in 0 .. 2 {
					for lane in 0 .. n {
						mut a := ScalarVectorValue{}
						mut b := a
						if input == 0 {
							a.lanes[lane] = IntegerValue{ poison: true }
						} else {
							b.lanes[lane] = IntegerValue{ poison: true }
						}
						result := saturating_shift_intrinsic_vector(id, a, b, w, n)!
						for j in 0 .. n {
							assert result.lanes[j].poison == (j == lane)
						}
						assert frozen_vector(result, n)!.lanes[lane] == IntegerValue{}
						if input == 0 { a.undef = u16(1) << lane } else { b.undef = u16(1) << lane }
						if _ := saturating_shift_intrinsic_vector(id, a, b, w, n) {
							assert false, 'undef'
						}
						checks++
					}
				}
			}
		}
	}
	for name in ['llvm.sshl.sat.v0i32', 'llvm.sshl.sat.v01i32', 'llvm.ushl.sat.v17i1',
		'llvm.sshl.sat.v2i65', 'llvm.ushl.sat.v2i01', 'llvm.sshl.sat.v2f32', 'llvm.sshl.sat.nxv2i32',
		'air.sshl.sat.v2i32'] {
		if _, _, _ := vector_float_intrinsic_name(name) {
			assert false, name
		}
	}
	assert checks == 34816
	for id in [ScalarIntrinsic.sshl_sat, .ushl_sat]! {
		for tag in [IntegerValue{aggregate: true}, IntegerValue{vector: true}] {
			mut source := ScalarVectorValue{}
			source.lanes[0] = tag
			if _ := saturating_shift_intrinsic_vector(id, source, ScalarVectorValue{}, 32, 1) { assert false, 'left lane tag' }
			if _ := saturating_shift_intrinsic_vector(id, ScalarVectorValue{}, source, 32, 1) { assert false, 'right lane tag' }
		}
	}
	for id in [ScalarIntrinsic.sadd_sat, .smin]! {
		if _ := saturating_shift_intrinsic_vector(id, ScalarVectorValue{}, ScalarVectorValue{}, 32, 2) {
			assert false
		}
	}
	for w in [u32(0), 65]! {
		if _ := saturating_shift_intrinsic_vector(.sshl_sat, ScalarVectorValue{}, ScalarVectorValue{}, w, 1) {
			assert false
		}
	}
	for n in [0, 17] {
		if _ := saturating_shift_intrinsic_vector(.ushl_sat, ScalarVectorValue{}, ScalarVectorValue{}, 32, n) {
			assert false
		}
	}
	println('VECTOR-SAT-SHIFT-STATES: ${checks} source poison/undef/freeze positions and shape/name/family guards PASS')
}
