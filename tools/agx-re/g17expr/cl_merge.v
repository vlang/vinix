module g17expr

import traceanalysis as j
import math.big

fn merge_load(instructions []Instruction, start int, relative int, reject_zero bool, depth int, seen []Visit) ?map[string]j.Value {
	index := start + relative
	load := fields('decode_integer_load_unsigned', instructions[index].word, big.zero_int) or { return none }
	if reject_zero && load[0].int() == 31 { return none }
	base := load[1].int()
	if base == 19 { return descriptor_load(instructions[index].offset, load[2], load[3], false) }
	return object_load(instructions, index, base, load[2], load[3], false, depth, seen)
}

pub fn cl_base_merge(instructions []Instruction, use_index int, register int, depth int, seen []Visit) ?map[string]j.Value {
	index := last_write(instructions, use_index, register) or { return none }
	if index < 28 { return none }
	start := index - 28
	block := instruction_block(instructions, start, index + 2)
	if block.len != 30 { return none }
	join := block[29].offset
	outer := decoded_object_at('decode_test_bit_branch', block[1]) or { return none }
	if text(outer, 'condition') != 'bit_clear' || !value_is_target(at(outer, 'target'), block[16].offset) || !conditional_is(block[5], block[20].offset, 'hi') || !target_is('decode_b_target', block[15], block[23].offset) || !target_is('decode_b_target', block[19], join) {
		return none
	}
	packed := decoded_object('decode_logical_shifted_register', block[24].word) or { return none }
	masked := decoded_object('decode_logical_shifted_register', block[28].word) or { return none }
	if text(packed, 'operation') != 'orr' || number(packed, 'destination_register') != 10 || number(packed, 'first_register') != 10 || number(packed, 'second_register') != 11 || text(packed, 'shift') != 'lsl' || number(packed, 'amount') != 17 || text(masked, 'operation') != 'and' || number(masked, 'destination_register') != register || number(masked, 'first_register') != 10 || number(masked, 'second_register') != 11 || number(masked, 'amount') != 0 {
		return none
	}
	flag := merge_load(instructions, start, 0, false, depth, seen) or { return none }
	predicate := condition_expression(instructions, start + 5, depth + 1, seen) or { return none }
	table := value_expression(instructions, start + 15, 10, depth + 1, seen) or { return none }
	bits := merge_load(instructions, start, 23, false, depth, seen) or { return none }
	base := static_x_register(instructions, start + 19, register, 0) or { return none }
	fallback := static_x_register(instructions, start + 23, 10, 0) or { return none }
	mask := static_x_register(instructions, start + 28, 11, 0) or { return none }
	selected := branch_select(block[5].offset, j.Value('hi'), scalar(block[20].offset), predicate, map[string]j.Value{
		'kind':            j.Value('constant')
		'producer_offset': scalar(block[22].offset)
		'value':           j.Value(fallback)
	}, table)
	packed_value := map[string]j.Value{
		'kind':            j.Value('expression')
		'producer_offset': scalar(block[24].offset)
		'operation':       j.Value('orr')
		'bytes':           j.Value(8)
		'shift':           j.Value('lsl')
		'amount':          j.Value(17)
		'first':           expr(selected)
		'second':          expr(bits)
	}
	dynamic := map[string]j.Value{
		'kind':            j.Value('expression')
		'producer_offset': scalar(block[28].offset)
		'operation':       j.Value('and')
		'bytes':           j.Value(8)
		'first':           expr(packed_value)
		'second':          expr(map[string]j.Value{
			'kind':            j.Value('constant')
			'producer_offset': scalar(block[27].offset)
			'value':           j.Value(mask)
		})
	}
	return branch_select(block[1].offset, j.Value('bit_clear'), scalar(block[16].offset), test_bit_predicate(block[1].offset, outer, flag), map[string]j.Value{
		'kind':            j.Value('constant')
		'producer_offset': scalar(block[18].offset)
		'value':           j.Value(base)
	}, dynamic)
}

fn immediate_compare(instruction Instruction, register int, immediate int) bool {
	decoded := decoded_object('decode_add_sub_immediate_value', instruction.word) or { return false }
	return text(decoded, 'operation') == 'sub' && number(decoded, 'destination_register') == 31 && number(decoded, 'source_register') == register && number(decoded, 'immediate') == immediate && number(decoded, 'bytes') == 4 && instruction.word & (u32(1) << 29) != 0
}

fn same_tuple(left []j.Value, right []j.Value) bool {
	if left.len != right.len { return false }
	for index, value in left {
		if j.string_value(value) != j.string_value(right[index]) { return false }
	}
	return true
}

pub fn cl_mode_bit_merge(instructions []Instruction, use_index int, register int, depth int, seen []Visit) ?map[string]j.Value {
	index := last_write(instructions, use_index, register) or { return none }
	if index < 32 { return none }
	start := index - 32
	block := instruction_block(instructions, start, index + 2)
	if block.len != 34 { return none }
	join := block[33].offset
	if !immediate_compare(block[1], register, 2) || !immediate_compare(block[3], register, 1) || !conditional_is(block[2], block[18].offset, 'eq') || !conditional_is(block[4], block[12].offset, 'eq') {
		return none
	}
	default_branch := decoded_object_at('decode_compare_zero_branch', block[5]) or { return none }
	if text(default_branch, 'condition') != 'nonzero' || number(default_branch, 'register') != register || !value_is_target(at(default_branch, 'target'), block[23].offset) {
		return none
	}
	for relative, target in {
		11: join
		17: block[25].offset
		22: join
		23: join
		31: join
	} {
		if !target_is('decode_b_target', block[relative], target) { return none }
	}
	zero_flag := decoded_object_at('decode_test_bit_branch', block[7]) or { return none }
	one_flag := decoded_object_at('decode_test_bit_branch', block[13]) or { return none }
	if !value_is_target(at(zero_flag, 'target'), block[32].offset) || !value_is_target(at(one_flag, 'target'), block[24].offset) {
		return none
	}
	random_mask := array_decode('decode_logical_immediate_w', block[19].word, big.zero_int)
	load := fields('decode_integer_load_unsigned', block[26].word, big.zero_int) or { return none }
	increment := decoded_object('decode_add_sub_immediate_value', block[27].word) or { return none }
	store := fields('decode_str_unsigned', block[28].word, big.zero_int) or { return none }
	addition := decoded_object('decode_add_sub_register_value', block[29].word) or { return none }
	mask := array_decode('decode_logical_immediate_w', block[30].word, big.zero_int)
	if block[18].offset != big.integer_from_int(random_call_offset) || !block[18].exact_word || block[18].word != random_call_word || !same_tuple(random_mask, [
		j.Value('and'),
		j.Value(register),
		j.Value(0),
		j.Value(1),
	]) || text(increment, 'operation') != 'add' || number(increment, 'source_register') != load[0].int() || number(increment, 'immediate') != 1 || number(increment, 'bytes') != 4 || store[0].int() != number(increment, 'destination_register') || !same_tuple(store[1..], load[1..]) || text(addition, 'operation') != 'add' || number(addition, 'destination_register') != register || number(addition, 'first_register') != register || number(addition, 'second_register') != load[0].int() || number(addition, 'amount') != 0 || !same_tuple(mask, [
		j.Value('and'),
		j.Value(register),
		j.Value(register),
		j.Value(1),
	]) {
		return none
	}
	selector := merge_load(instructions, start, 0, true, depth, seen) or { return none }
	zero_source := merge_load(instructions, start, 6, true, depth, seen) or { return none }
	zero_fallthrough := value_expression(instructions, start + 11, register, depth + 1, seen) or { return none }
	zero_taken := merge_load(instructions, start, 32, true, depth, seen) or { return none }
	one_source := merge_load(instructions, start, 12, true, depth, seen) or { return none }
	one_fallthrough := value_expression(instructions, start + 17, register, depth + 1, seen) or { return none }
	one_taken := merge_load(instructions, start, 24, true, depth, seen) or { return none }
	random := value_expression(instructions, start + 20, register, depth + 1, seen) or { return none }
	counter := merge_load(instructions, start, 26, true, depth, seen) or { return none }
	if number(addition, 'second_register') == 31 { return none }
	mode_zero := branch_select(block[7].offset, at(zero_flag, 'condition'), scalar(block[32].offset), test_bit_predicate(block[7].offset, zero_flag, zero_source), zero_taken, zero_fallthrough)
	selected := branch_select(block[13].offset, at(one_flag, 'condition'), scalar(block[24].offset), test_bit_predicate(block[13].offset, one_flag, one_source), one_taken, one_fallthrough)
	mut updated := counter.clone()
	updated['update'] = j.Value('postincrement')
	updated['update_offset'] = scalar(block[28].offset)
	added := map[string]j.Value{
		'kind':            j.Value('expression')
		'producer_offset': scalar(block[29].offset)
		'operation':       j.Value('add')
		'bytes':           j.Value(4)
		'modifier':        modifier(addition)
		'amount':          at(addition, 'amount')
		'first':           expr(selected)
		'second':          expr(updated)
	}
	mode_one := map[string]j.Value{
		'kind':            j.Value('expression')
		'producer_offset': scalar(block[30].offset)
		'operation':       j.Value('and')
		'bytes':           j.Value(4)
		'immediate':       j.Value(1)
		'source':          expr(added)
	}
	cases := [j.Value(map[string]j.Value{
		'equals': j.Value(2)
		'value':  expr(random)
	}), j.Value(map[string]j.Value{
		'equals': j.Value(1)
		'value':  expr(mode_one)
	}), j.Value(map[string]j.Value{
		'equals': j.Value(0)
		'value':  expr(mode_zero)
	})]
	return map[string]j.Value{
		'kind':            j.Value('expression')
		'producer_offset': scalar(block[1].offset)
		'operation':       j.Value('multiway_select')
		'selector':        expr(selector)
		'cases':           j.Value(cases)
		'default':         expr(selector)
		'join_offset':     scalar(join)
	}
}
