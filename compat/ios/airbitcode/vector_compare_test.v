// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn vector_integer_expected(predicate u32, bits u32, a u64, b u64) bool {
	limit := constant_mask(bits); x := a & limit; y := b & limit
	negative_x := x >= (u64(1) << (bits - 1)); negative_y := y >= (u64(1) << (bits - 1))
	less := if negative_x != negative_y { negative_x } else { x < y }
	return match predicate { 32 { x == y } 33 { x != y } 34 { x > y } 35 { x >= y } 36 { x < y } 37 { x <= y } 38 { !less && x != y } 39 { !less } 40 { less } else { less || x == y } }
}
fn test_vector_comparison_integer_lanes() {
	mut checks := 0
	for bits in u32(1) .. 65 { for count in 1 .. 17 { for sample in 0 .. 12 {
		mut left := ScalarVectorValue{}; mut right := ScalarVectorValue{}
		for lane in 0 .. count {
			x := [u64(0), 1, ~u64(0), u64(1) << (bits - 1), (u64(1) << (bits - 1)) - 1, 0x5555555555555555, 0xaaaaaaaaaaaaaaaa, 0x9e3779b97f4a7c15]!
			left.lanes[lane] = IntegerValue{value: x[(sample + lane) % 8], poison: sample == 10 && lane % 3 == 1}
			right.lanes[lane] = IntegerValue{value: x[(sample / 2 + lane * 3) % 8], poison: sample == 11 && lane % 3 == 2}
		}
		before_left := left; before_right := right
		for predicate in u32(32) .. 42 { for flags in [u64(0), 1]! {
			result := compared_vector(left, right, IRType{kind: .integer_t, bits: bits}, count, predicate, flags)!
			assert result.undef == 0
			for lane in 0 .. count {
				a := left.lanes[lane]; b := right.lanes[lane]
				bad_sign := ((a.value & constant_mask(bits)) >= u64(1) << (bits - 1)) != ((b.value & constant_mask(bits)) >= u64(1) << (bits - 1))
				assert result.lanes[lane].poison == (a.poison || b.poison || (flags != 0 && bad_sign))
				if !result.lanes[lane].poison { assert result.lanes[lane].value == u64(vector_integer_expected(predicate, bits, a.value, b.value)) }; checks++
			}
			frozen_vector(result, count)!
		} }
		assert left == before_left && right == before_right
	} } }
	assert checks == 2088960
	println('AIR-VECTOR-COMPARE-INTEGER: ${checks} independent lane comparisons, i1-i64, all counts 1..16, all ten predicates, samesign, masking, localized poison and immutable sources PASS')
}
fn test_vector_comparison_floating_lanes() {
	mut checks := 0
	// Ordered ranks supply an independent truth-table oracle; NaNs have rank -1.
	ranks := [5, 5, 8, 2, 10, 0, -1, -1, 6, 4]!
	for half in [false, true]! { for count in 1 .. 17 { for sample in 0 .. 10 {
		words := if half { [u64(0), 0x8000, 0x3c00, 0xbc00, 0x7c00, 0xfc00, 0x7c01, 0xfe55, 1, 0x8001]! } else { [u64(0), 0x80000000, 0x3f800000, 0xbf800000, 0x7f800000, 0xff800000, 0x7f800001, 0xffc12345, 1, 0x80000001]! }
		mut left := ScalarVectorValue{}; mut right := ScalarVectorValue{}
		for lane in 0 .. count { left.lanes[lane] = IntegerValue{value: words[(sample + lane) % 10], poison: lane % 5 == 4}; right.lanes[lane] = IntegerValue{value: words[(sample * 3 + lane) % 10], poison: lane % 5 == 3} }
		for predicate in u32(0) .. 16 {
			result := compared_vector(left, right, IRType{kind: if half { .half_t } else { .float_t }}, count, predicate, 0)!
			for lane in 0 .. count {
				a := ranks[(sample + lane) % 10]; b := ranks[(sample * 3 + lane) % 10]
				state := if a < 0 || b < 0 { 3 } else if a == b { 0 } else if a > b { 1 } else { 2 }
				poison := predicate !in [u32(0), 15]! && (left.lanes[lane].poison || right.lanes[lane].poison)
				assert result.lanes[lane].poison == poison
				if !poison { assert result.lanes[lane].value == u64(predicate & (u32(1) << u32(state)) != 0) }; checks++
			}
		}
	} } }
	assert checks == 43520
	println('AIR-VECTOR-COMPARE-FLOAT: ${checks} independent half/float truth-table comparisons, all counts/predicates, NaNs/infinities/signed zeros/subnormals and localized poison PASS')
}
fn test_vector_comparison_undef_and_guards() {
	for count in 1 .. 17 { for lane in 0 .. count {
		mut source := ScalarVectorValue{}; source.undef = u16(1) << u32(lane)
		for side in 0 .. 2 {
			left := if side == 0 { source } else { ScalarVectorValue{} }; right := if side == 1 { source } else { ScalarVectorValue{} }
			for typ in [IRType{kind: .integer_t, bits: 32}, IRType{kind: .half_t}, IRType{kind: .float_t}] {
				if _ := compared_vector(left, right, typ, count, if typ.kind == .integer_t { 32 } else { 1 }, 0) { assert false, 'undef operand lane' }
				if typ.kind != .integer_t { for pred in [u32(0), 15]! { v := compared_vector(left, right, typ, count, pred, 0)!; for i in 0 .. count { assert !v.lanes[i].poison && v.lanes[i].value == u64(pred == 15) } } }
			}
		}
	} }
	for count in [0, 17] { if _ := compared_vector(ScalarVectorValue{}, ScalarVectorValue{}, IRType{kind: .integer_t, bits: 32}, count, 32, 0) { assert false, 'count guard' } }
	for typ in [IRType{kind: .integer_t}, IRType{kind: .integer_t, bits: 65}, IRType{kind: .double_t}, IRType{kind: .pointer_t}] { if _ := compared_vector(ScalarVectorValue{}, ScalarVectorValue{}, typ, 2, 32, 0) { assert false, 'type guard' } }
	for flags in [u64(2), 3, ~u64(0)] { if _ := compared_vector(ScalarVectorValue{}, ScalarVectorValue{}, IRType{kind: .integer_t, bits: 32}, 2, 32, flags) { assert false, 'integer flag guard' } }
	if _ := compared_vector(ScalarVectorValue{}, ScalarVectorValue{}, IRType{kind: .float_t}, 2, 1, 1) { assert false, 'floating flag guard' }
	println('AIR-VECTOR-COMPARE-GUARDS: undef on either operand at every lane, constant FP predicates and count/type/flag guards PASS')
}

fn test_vector_comparison_constant_fp_reader() {
	p := IRTypedProgram{types: [IRType{kind: .integer_t, bits: 1}, IRType{kind: .half_t}, IRType{kind: .vector_t, count: 2, refs_count: 1}, IRType{kind: .vector_t, count: 2, refs_start: 1, refs_count: 1}], references: [1, 0], operands: [IRTypedOperand{number: 5, type_index: 2}, IRTypedOperand{number: 6, type_index: 2}]}
	defer { p.free() }
	mut m := IntegerMachine{p: p, binary32: true, bodies: IRFunctionBodies{scopes: [IRBodyScope{base_id: 5}]}, values: [IntegerValue{}, IntegerValue{}, IntegerValue{vector: true, value: 0}], known: [false, false, false], vectors: [ScalarVectorValue{}]}
	defer { unsafe { m.values.free(); m.known.free(); m.vectors.free(); m.bodies.scopes.free() } }
	for predicate in [u32(0), 15]! {
		m.compare_vector_value(Stream{}, IRInstruction{has_result: true, next_value: 7}, IRTypedInstruction{opcode: predicate, result_type: 3, operands_count: 2})!
		for lane in 0 .. 2 { assert !m.vectors[0].lanes[lane].poison && m.vectors[0].lanes[lane].value == u64(predicate == 15) }
	}
	if _ := m.compare_vector_value(Stream{}, IRInstruction{has_result: true, next_value: 7}, IRTypedInstruction{opcode: 1, result_type: 3, operands_count: 2}) { assert false, 'ordinary predicate read unavailable source' }
	println('AIR-VECTOR-COMPARE-CONSTANT-FP: false/true read neither source, ordinary predicates require available sources PASS')
}
