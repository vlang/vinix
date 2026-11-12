// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

fn test_integer_alu_bit_patterns_poison_and_undefined_inputs() {
	cases := [
		[u64(8), 0, 255, 1, 0], [u64(8), 1, 0, 1, 255], [u64(8), 2, 128, 2, 0],
		[u64(8), 3, 255, 2, 127], [u64(8), 4, 249, 2, 253], [u64(8), 4, 7, 254, 253],
		[u64(8), 5, 255, 2, 1], [u64(8), 6, 249, 2, 255], [u64(8), 6, 7, 254, 1],
		[u64(8), 7, 1, 7, 128], [u64(8), 8, 128, 7, 1], [u64(8), 9, 128, 7, 255],
		[u64(8), 10, 0xaa, 0x55, 0], [u64(8), 11, 0xaa, 0x55, 255], [u64(8), 12, 255, 0xaa, 0x55],
		[u64(64), 2, ~u64(0), 2, ~u64(1)], [u64(64), 4, u64(1) << 63, 2, u64(3) << 62],
		[u64(64), 3, ~u64(0), 2, ~u64(0) >> 1], [u64(1), 0, 1, 1, 0],
	]
	defer { unsafe { for row in cases { row.free() }; cases.free() } }
	for row in cases { value := integer_binary(u32(row[1]), u32(row[0]), IntegerValue{value: row[2]}, IntegerValue{value: row[3]})!; assert !value.poison && value.value == row[4] }
	for op in [u32(7), 8, 9] { assert integer_binary(op, 8, IntegerValue{value: 1}, IntegerValue{value: 8})!.poison }
	assert integer_binary(10, 8, IntegerValue{poison: true}, IntegerValue{})!.poison
	for op in [u32(3), 4, 5, 6] {
		if _ := integer_binary(op, 64, IntegerValue{}, IntegerValue{}) { assert false, 'zero divisor' }
		if _ := integer_binary(op, 64, IntegerValue{poison: true}, IntegerValue{value: 2}) { assert false, 'unsupported poison division' }
	}
	for op in [u32(4), 6] { if _ := integer_binary(op, 64, IntegerValue{value: u64(1) << 63}, IntegerValue{value: ~u64(0)}) { assert false, 'signed division/remainder overflow' } }
	expected := [u64(0), 1, 1, 1, 0, 0, 0, 0, 1, 1]; defer { unsafe { expected.free() } }
	for i, value in expected { assert integer_compare(u32(i + 32), 8, IntegerValue{value: 255}, IntegerValue{value: 1})!.value == value }
	assert integer_compare(32, 64, IntegerValue{poison: true}, IntegerValue{})!.poison
	println('AIR-INTEGER-ALU: 19 exact arithmetic patterns, all predicates, narrow/wide wrapping, overshift poison and undefined division guards PASS')
}
struct IntegerFixture {
mut:
	blocks []Block
	records []Record
	values []u64
	types []IRType
	refs []int
	functions []IRFunction
	scopes []IRConstantScope
	constants []IRConstant
	words []u64
	arguments []int
}
fn integer_fixture() IntegerFixture {
	mut f := IntegerFixture{
		blocks: [Block{parent: -1}, Block{id: 8, parent: 0}, Block{id: 12, parent: 1}]
		types: [IRType{kind: .integer_t, bits: 64}, IRType{kind: .integer_t, bits: 1}, IRType{kind: .function_t, refs_count: 3}]
		refs: [0, 0, 0]
		functions: [IRFunction{signature: 2, record: 0, body_block: 2, basic_blocks: 3}]
		scopes: [IRConstantScope{active: true}, IRConstantScope{active: true, base_id: 3, count: 1, arguments_count: 2}]
		constants: [IRConstant{kind: .integer, type_index: 0, bits: 64, scope: 1, number: 3, words_count: 1}]
		words: [u64(1)]
		arguments: [0, 0]
	}
	f.records.flags |= .noslices; f.values.flags |= .noslices
	f.header()
	f.add(1, [u64(3)]); f.add(2, [u64(3), 2, 0]); f.add(28, [u64(1), 2, 34]); f.add(11, [u64(1), 2, 1]); f.add(10, [u64(2)]); f.add(10, [u64(3)])
	return f
}
fn (mut f IntegerFixture) header() { f.records << Record{block: 1, code: 8, values_start: f.values.len, values_count: 10}; f.values << [u64(0), 1, 2, 0, 0, 0, 0, 0, 0, 0] }
fn (mut f IntegerFixture) add(code u64, values []u64) { f.records << Record{block: 2, code: code, values_start: f.values.len, values_count: values.len}; f.values << values }
fn (f IntegerFixture) ir() IRModule { return IRModule{types: f.types, references: f.refs, functions: f.functions} }
fn (f IntegerFixture) stream() Stream { return Stream{blocks: f.blocks, records: f.records, values: f.values} }
fn (f IntegerFixture) run(arguments []u64, limit int) !IRIntegerRun {
	declarations := [0]; defer { unsafe { declarations.free() } }
	pools := IRConstantPools{declarations: declarations, scopes: f.scopes, constants: f.constants, words: f.words, arguments: f.arguments, module_values: 1}
	ir := f.ir(); stream := f.stream(); bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }
	p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	return p.run_integer_function(ir, stream, pools, bodies, 0, arguments, limit)!
}
fn (f IntegerFixture) scalar(arguments []u64, limit int) !IRScalarRun {
	declarations := [0]; defer { unsafe { declarations.free() } }
	pools := IRConstantPools{declarations: declarations, scopes: f.scopes, constants: f.constants, words: f.words, arguments: f.arguments, module_values: 1}
	ir := f.ir(); stream := f.stream(); bodies := ir.function_bodies(stream, pools)!; defer { bodies.free() }
	p := ir.typed_operands(stream, pools, bodies)!; defer { p.free() }
	return p.run_scalar_function(ir, stream, pools, bodies, 0, arguments, limit)!
}
fn (f &IntegerFixture) free() { unsafe { f.blocks.free(); f.records.free(); f.values.free(); f.types.free(); f.refs.free(); f.functions.free(); f.scopes.free(); f.constants.free(); f.words.free(); f.arguments.free() } }
fn test_integer_function_branches_arguments_and_budgets() {
	mut f := integer_fixture(); defer { f.free() }
	a := f.run([u64(2), 3], 4)!; b := f.run([u64(0), 0], 4)!
	assert a.bits == 64 && a.value == 5 && !a.poison && a.steps == 4
	assert b.value == 1 && b.steps == 4
	for limit in [0, 3, max_integer_execution_steps + 1] { if _ := f.run([u64(2), 3], limit) { assert false, 'budget accepted' } }
	if _ := f.run([u64(1)], 10) { assert false, 'argument count' }
	f.values[6] = 1
	if _ := f.run([u64(2), 3], 10) { assert false, 'function attributes' }
	f.values[6] = 0
	f.values[f.records[2].values_start + 2] = 7
	if _ := f.run([u64(1), 64], 10) { assert false, 'poison branch' }
	f.records.clear(); f.values.clear(); f.functions[0] = IRFunction{...f.functions[0], basic_blocks: 2}
	f.header(); f.add(1, [u64(2)]); f.add(11, [u64(1)]); f.add(11, [u64(1)])
	if _ := f.run([u64(0), 0], 7) { assert false, 'infinite loop budget' }
	println('AIR-INTEGER-CONTROL: both branch paths, scoped arguments/constants, precise steps, argument/attribute/poison guards and bounded infinite loop PASS')
}
fn test_integer_select_laziness_poison_and_unsupported_instructions() {
	mut f := integer_fixture(); defer { f.free() }
	f.records.clear(); f.values.clear(); f.functions[0] = IRFunction{...f.functions[0], basic_blocks: 1}; f.refs[2] = 1; f.arguments[1] = 1
	f.constants[0] = IRConstant{...f.constants[0], kind: .undef}
	f.header(); f.add(1, [u64(1)]); f.add(29, [u64(3), 1, 2]); f.add(10, [u64(1)])
	assert f.run([u64(19), 1], 5)!.value == 19
	if _ := f.run([u64(19), 0], 5) { assert false, 'selected undef' }
	f.constants[0] = IRConstant{...f.constants[0], kind: .poison}
	assert f.run([u64(19), 0], 5)!.poison && !f.run([u64(19), 1], 5)!.poison
	f.records.clear(); f.values.clear(); f.refs[2] = 0; f.arguments[1] = 0
	f.header(); f.add(1, [u64(1)]); f.add(2, [u64(3), 2, 0, 4]); f.add(10, [u64(1)])
	if _ := f.run([u64(1), 2], 5) { assert false, 'unsupported integer flags' }
	println('AIR-INTEGER-VALUES: lazy select, undef rejection, explicit poison return and fail-closed flag handling PASS')
}
fn test_integer_narrow_argument_and_return_masks() {
	mut f := integer_fixture(); defer { f.free() }
	f.types[0] = IRType{kind: .integer_t, bits: 8}; f.constants[0] = IRConstant{...f.constants[0], bits: 8}
	a := f.run([u64(0x101), 0x102], 8)!; b := f.run([u64(255), 1], 8)!
	assert a.bits == 8 && a.value == 3 && b.bits == 8 && b.value == 1
	println('AIR-INTEGER-NARROW: incoming argument masking, narrow result slots/wrap and returned bit width PASS')
}
fn test_integer_flags_against_widened_narrow_arithmetic() {
	mut comparisons := 0
	for bits in u32(1) .. 9 {
		width := int(bits); limit := 1 << width; sign := limit / 2; mask := u64(limit - 1)
		for x in 0 .. limit {
			for y in 0 .. limit {
				sx := if x >= sign { x - limit } else { x }; sy := if y >= sign { y - limit } else { y }
				for op in [u32(0), 1, 2, 7]! {
					for flags in u64(1) .. 4 {
						actual := integer_binary_flags(op, flags, bits, IntegerValue{value: u64(x)}, IntegerValue{value: u64(y)})!
						mut poison := op == 7 && y >= width
						if !poison {
							unsigned := match op { 0 { x + y } 1 { x - y } 2 { x * y } else { x * (1 << y) } }
							signed := match op { 0 { sx + sy } 1 { sx - sy } 2 { sx * sy } else { sx * (1 << y) } }
							poison = (flags & 1 != 0 && (unsigned < 0 || unsigned >= limit)) || (flags & 2 != 0 && (signed < -sign || signed >= sign))
							if !poison { assert actual.value == u64(unsigned) & mask }
						}
						assert actual.poison == poison
						comparisons++
					}
				}
				for op in [u32(3), 4, 8, 9]! {
					if op in [u32(3), 4]! && (y == 0 || (op == 4 && sx == -sign && sy == -1)) { continue }
					actual := integer_binary_flags(op, 1, bits, IntegerValue{value: u64(x)}, IntegerValue{value: u64(y)})!
					mut poison := op in [u32(8), 9]! && y >= width
					if !poison {
						poison = match op { 3 { x % y != 0 } 4 { sx % sy != 0 } else { x % (1 << y) != 0 } }
						if !poison {
							value := match op { 3 { x / y } 4 { sx / sy } 8 { x >> y } else { sx >> y } }
							assert actual.value == u64(value) & mask
						}
					}
					assert actual.poison == poison
					comparisons++
				}
			}
		}
	}
	println('AIR-INTEGER-FLAGS-NARROW: ${comparisons} exhaustive i1..i8 NUW/NSW/EXACT comparisons against widened arithmetic PASS')
}
fn test_integer_flags_wide_limits_and_instruction_integration() {
	max := ~u64(0); sign := u64(1) << 63
	cases := [
		[u64(0), 1, max, 1, 1, 0], [u64(0), 2, max, 1, 0, 0],
		[u64(0), 2, sign - 1, 1, 1, 0], [u64(0), 3, 1, 1, 0, 2],
		[u64(1), 1, 0, 1, 1, 0], [u64(1), 2, sign, 1, 1, 0],
		[u64(1), 2, 0, 1, 0, max], [u64(1), 3, sign - 1, sign - 1, 0, 0],
		[u64(2), 1, max, 2, 1, 0], [u64(2), 2, sign, max, 1, 0],
		[u64(2), 2, sign, 1, 0, sign], [u64(2), 2, max, max, 0, 1],
		[u64(2), 2, sign >> 1, 2, 1, 0], [u64(2), 1, sign >> 1, 2, 0, sign],
		[u64(2), 3, sign, 0, 0, 0], [u64(2), 2, sign, 2, 1, 0],
		[u64(7), 1, sign, 1, 1, 0], [u64(7), 2, 1, 63, 1, 0],
		[u64(7), 2, max, 63, 0, sign], [u64(7), 3, max, 0, 0, max],
		[u64(3), 1, max, 2, 1, 0], [u64(3), 1, max - 1, 2, 0, (max - 1) / 2],
		[u64(4), 1, sign, 2, 0, u64(3) << 62], [u64(4), 1, max - 1, 2, 0, max],
		[u64(4), 1, max, 2, 1, 0], [u64(8), 1, sign, 63, 0, 1],
		[u64(9), 1, sign, 63, 0, max], [u64(9), 1, max, 1, 1, 0],
	]
	defer { unsafe { for row in cases { row.free() }; cases.free() } }
	for row in cases {
		actual := integer_binary_flags(u32(row[0]), row[1], 64, IntegerValue{value: row[2]}, IntegerValue{value: row[3]})!
		assert actual.poison == (row[4] != 0)
		if !actual.poison { assert actual.value == row[5] }
	}
	for op in u32(0) .. 13 {
		if _ := integer_binary_flags(op, u64(1) << 63, 64, IntegerValue{value: 1}, IntegerValue{value: 1}) { assert false, 'unknown flag accepted' }
		for flags in u64(0) .. 8 {
			if flags & ~integer_binary_flag_mask(op) != 0 { if _ := integer_binary_flags(op, flags, 64, IntegerValue{value: 1}, IntegerValue{value: 1}) { assert false, 'wrong-family flag accepted' } }
		}
	}
	assert integer_binary_flags(0, 3, 64, IntegerValue{poison: true}, IntegerValue{})!.poison
	mut f := integer_fixture(); defer { f.free() }
	f.records.clear(); f.values.clear(); f.functions[0] = IRFunction{...f.functions[0], basic_blocks: 1}
	f.header(); f.add(1, [u64(1)]); f.add(2, [u64(3), 2, 0, 2]); f.add(10, [u64(1)])
	assert f.run([u64(1), 2], 2)!.value == 3
	assert f.run([sign - 1, u64(1)], 2)!.poison
	if _ := f.run([u64(1), 2], 1) { assert false, 'flagged instruction budget' }
	println('AIR-INTEGER-FLAGS-WIDE: 28 i64 limits, unknown/wrong-family masks, poison propagation and decoded-instruction/budget integration PASS')
}
fn integer_switch_fixture() IntegerFixture {
	mut f := integer_fixture()
	f.constants.flags |= .noslices; f.words.flags |= .noslices
	f.constants << IRConstant{kind: .integer, type_index: 0, bits: 64, scope: 1, number: 4, words_start: 1, words_count: 1}
	f.constants << IRConstant{kind: .zero, type_index: 0, bits: 64, scope: 1, number: 5}
	f.words << ~u64(0)
	f.scopes[1] = IRConstantScope{...f.scopes[1], count: 3}
	f.functions[0] = IRFunction{...f.functions[0], basic_blocks: 4}
	f.records.clear(); f.values.clear(); f.header(); f.add(1, [u64(4)])
	// Argument %1 is relative; case IDs %3/%4/%5 are absolute. Shared targets.
	f.add(12, [u64(0), 5, 3, 3, 1, 4, 2, 5, 2])
	f.add(10, [u64(4)]); f.add(10, [u64(3)]); f.add(10, [u64(5)])
	return f
}
fn test_integer_switch_cases_default_and_precise_budget() {
	f := integer_switch_fixture(); defer { f.free() }
	first := f.run([u64(1), 99], 3)!; second := f.run([~u64(0), 99], 4)!
	third := f.run([u64(0), 99], 5)!; fallback := f.run([u64(2), 99], 5)!
	assert first.value == 99 && first.steps == 3 && second.value == 1 && second.steps == 4
	assert third.value == 1 && third.steps == 5 && fallback.value == 2 && fallback.steps == 5
	if _ := f.run([u64(1), 99], 2) { assert false, 'switch budget must include return' }
	if _ := f.run([u64(0), 99], 4) { assert false, 'switch budget must include comparisons' }
	if _ := f.run([u64(2), 99], 4) { assert false, 'default scan budget' }
	println('AIR-INTEGER-SWITCH: first/middle/last/zero/high-bit cases, shared destinations, default and precise comparison/return budgets PASS')
}
fn test_integer_switch_empty_poison_undef_and_loop_guards() {
	mut f := integer_switch_fixture(); defer { f.free() }
	f.records.clear(); f.values.clear(); f.header(); f.add(1, [u64(4)])
	f.add(12, [u64(0), 5, 3]); f.add(10, [u64(4)]); f.add(10, [u64(3)]); f.add(10, [u64(5)])
	result := f.run([u64(123), 99], 2)!
	assert result.value == 123 && result.steps == 2
	// Even an empty table must evaluate its condition rather than jump blindly.
	f.values[f.records[2].values_start + 1] = 3
	for kind in [IRConstantKind.poison, .undef]! {
		f.constants[0] = IRConstant{...f.constants[0], kind: kind}
		if _ := f.run([u64(1), 2], 8) { assert false, 'invalid switch condition accepted' }
	}
	f.constants[0] = IRConstant{...f.constants[0], kind: .integer}
	f.functions[0] = IRFunction{...f.functions[0], basic_blocks: 1}
	f.records.clear(); f.values.clear(); f.header(); f.add(1, [u64(1)]); f.add(12, [u64(0), 5, 0, 3, 0])
	if _ := f.run([u64(1), 2], 63) { assert false, 'matched switch loop budget' }
	if _ := f.run([u64(7), 2], 64) { assert false, 'default switch loop budget' }
	println('AIR-INTEGER-SWITCH-GUARDS: empty-table condition evaluation, poison/undef rejection and bounded matched/default self-loops PASS')
}
fn test_scalar_binary32_arguments_constants_poison_and_profile() {
	mut f := integer_fixture(); defer { f.free() }
	f.types[0] = IRType{kind: .float_t}; f.constants[0] = IRConstant{...f.constants[0], kind: .floating, bits: 32}; f.words[0] = 0x3f800000
	f.functions[0] = IRFunction{...f.functions[0], basic_blocks: 1}
	f.records.clear(); f.values.clear(); f.header(); f.add(1, [u64(1)]); f.add(2, [u64(3), 2, 0]); f.add(10, [u64(1)])
	run := f.scalar([u64(0x3f800000), 0x40000000], 2)!
	assert run.kind == .binary32 && run.bits == 32 && run.value == 0x40400000 && !run.poison && run.steps == 2
	if _ := f.run([u64(0x3f800000), 0x40000000], 2) { assert false, 'integer entry point accepted floating types' }
	if _ := f.scalar([u64(0x3f800000), 0x40000000], 1) { assert false, 'binary32 budget' }
	f.values[f.records[2].values_start] = 1 // Read the floating constant rather than the first argument.
	assert f.scalar([u64(0), 0x40000000], 2)!.value == 0x40400000
	f.constants[0] = IRConstant{...f.constants[0], kind: .poison}
	assert f.scalar([u64(0), 0x40000000], 2)!.poison
	f.constants[0] = IRConstant{...f.constants[0], kind: .undef}
	if _ := f.scalar([u64(0), 0x40000000], 2) { assert false, 'selected undef' }
	f.records.clear(); f.values.clear(); f.header(); f.add(1, [u64(1)]); f.add(56, [u64(3), 0]); f.add(10, [u64(1)])
	assert f.scalar([u64(0x7f800123), 0], 2)!.value == 0xff800123
	f.records.clear(); f.values.clear(); f.header(); f.add(1, [u64(1)]); f.add(2, [u64(3), 2, 0, 2]); f.add(10, [u64(1)])
	if _ := f.scalar([u64(0), 0], 4) { assert false, 'fast math flags' }
	f.refs[0] = 1
	for predicate in [u64(0), 15]! {
		f.records.clear(); f.values.clear(); f.header(); f.add(1, [u64(1)]); f.add(28, [u64(3), 1, predicate]); f.add(10, [u64(1)])
		for kind in [IRConstantKind.poison, .undef]! {
			f.constants[0] = IRConstant{...f.constants[0], kind: kind}
			comparison := f.scalar([u64(0), 0], 2)!
			assert comparison.kind == .integer && comparison.bits == 1 && !comparison.poison && comparison.value == u64(predicate == 15)
		}
	}
	println('AIR-SCALAR-BINARY32: float arguments/constants/returns, integer API isolation, exact fneg bits, poison/undef, constant predicates, FMF rejection and budgets PASS')
}
fn test_scalar_binary32_numeric_conversion_instructions() {
	mut f := integer_fixture(); defer { f.free() }
	f.types.flags |= .noslices; f.types[0] = IRType{kind: .float_t}; f.types << IRType{kind: .integer_t, bits: 64}
	f.refs[0] = 3; f.constants[0] = IRConstant{...f.constants[0], kind: .floating, bits: 32}
	f.functions[0] = IRFunction{...f.functions[0], basic_blocks: 1}
	f.records.clear(); f.values.clear(); f.header(); f.add(1, [u64(1)]); f.add(3, [u64(3), 3, 4]); f.add(10, [u64(1)])
	integer := f.scalar([u64(0xbfc00000), 0], 2)!
	assert integer.kind == .integer && integer.bits == 64 && integer.value == ~u64(0) && !integer.poison && integer.steps == 2
	assert f.scalar([u64(0x7f800000), 0], 2)!.poison
	f.refs[0] = 0; f.refs[1] = 3; f.arguments[0] = 3
	f.records.clear(); f.values.clear(); f.header(); f.add(1, [u64(1)]); f.add(3, [u64(3), 0, 6]); f.add(10, [u64(1)])
	floating := f.scalar([u64(1) << 63, 0], 2)!
	assert floating.kind == .binary32 && floating.bits == 32 && floating.value == 0xdf000000 && !floating.poison
	f.constants[0] = IRConstant{...f.constants[0], kind: .poison, type_index: 3, bits: 64}
	f.values[f.records[2].values_start] = 1
	assert f.scalar([u64(0), 0], 2)!.poison
	f.constants[0] = IRConstant{...f.constants[0], kind: .undef}
	if _ := f.scalar([u64(0), 0], 2) { assert false, 'conversion read undef' }
	f.records.clear(); f.values.clear(); f.header(); f.add(1, [u64(1)]); f.add(3, [u64(3), 0, 5, 1]); f.add(10, [u64(1)])
	if _ := f.scalar([u64(1), 0], 3) { assert false, 'conversion nneg flags' }
	println('AIR-SCALAR-CASTS: decoded numeric conversions, result kinds/widths, range/operand poison, undef and nonzero flag rejection PASS')
}
fn test_scalar_binary32_remainder_instruction_and_guards() {
	mut f := integer_fixture(); defer { f.free() }
	f.types[0] = IRType{kind: .float_t}; f.constants[0] = IRConstant{...f.constants[0], kind: .floating, bits: 32}; f.words[0] = 0x40000000
	f.functions[0] = IRFunction{...f.functions[0], basic_blocks: 1}
	f.records.clear(); f.values.clear(); f.header(); f.add(1, [u64(1)]); f.add(2, [u64(3), 2, 6]); f.add(10, [u64(1)])
	run := f.scalar([u64(0x1c0e00000), 0x240800000], 2)!
	assert run.kind == .binary32 && run.bits == 32 && run.value == 0xc0400000 && !run.poison && run.steps == 2
	assert f.scalar([u64(0xc0800000), 0x40000000], 2)!.value == 0x80000000
	invalid := f.scalar([u64(0x3f800000), 0], 2)!
	assert !invalid.poison && invalid.value == binary32_nan
	if _ := f.scalar([u64(0), 0], 1) { assert false, 'remainder budget' }
	if _ := f.run([u64(0), 0], 2) { assert false, 'integer profile accepted float remainder' }
	for operand in 0 .. 2 {
		f.values[f.records[2].values_start + operand] = 1
		f.constants[0] = IRConstant{...f.constants[0], kind: .poison}
		assert f.scalar([u64(0), 0], 2)!.poison
		f.constants[0] = IRConstant{...f.constants[0], kind: .undef}
		if _ := f.scalar([u64(0), 0], 2) { assert false, 'remainder read undef' }
		f.constants[0] = IRConstant{...f.constants[0], kind: .floating}
		assert f.scalar([u64(0x40e00000), 0x40800000], 2)!.value == if operand == 0 { u64(0x40000000) } else { u64(0x3f800000) }
		f.values[f.records[2].values_start + operand] = u64(3 - operand)
	}
	f.records.clear(); f.values.clear(); f.header(); f.add(1, [u64(1)]); f.add(2, [u64(3), 2, 6, 2]); f.add(10, [u64(1)])
	if _ := f.scalar([u64(0), 0], 2) { assert false, 'remainder fast math flags' }
	println('AIR-SCALAR-REMAINDER: decoded frem, masking, kinds/widths/steps, signed zero, invalid NaN, both operand poison/undef/constants, FMF and budget guards PASS')
}
