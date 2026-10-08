module g17expr

import os
import traceanalysis as j
import math.big

// Independent instruction and mocked-image fixtures originate in the 30
// frozen pre-port test bodies, not the recovery code or its proof tables.
fn fixture_rows(name string) []j.Value {
	records := j.object(j.decode(os.read_file(os.join_path(os.dir(@FILE), 'fixtures/original-expressions.json')) or { panic(err) }) or { panic(err) }) or { panic(err) }
	return j.value(records, name).arr()
}

fn verify_original_fixture(name string) {
	for row_value in fixture_rows(name) {
		row := row_value.as_map()
		request := j.value(row, 'request').as_map()
		before := j.encode(j.Value(request), false)
		actual := query([]u8{}, j.string_value(j.value(request, 'operation')), request) or {
			assert 'error' in row
			category := j.string_value(j.value(row, 'class'))
			prefix := if category == 'IndexError' || category == 'KeyError' {
				category + ': '
			} else {
				''
			}
			assert err.msg() == prefix + j.string_value(j.value(row, 'error'))
			assert j.encode(j.Value(request), false) == before
			continue
		}
		assert 'result' in row
		assert j.decode(j.encode(actual, false)) or { panic(err) } == j.value(row, 'result')
		assert j.encode(j.Value(request), false) == before
	}
}

fn test_recovers_g17_register_selectors() {
	verify_original_fixture('test_recovers_g17_register_selectors')
}

fn test_classifies_g17_register_value_source() {
	verify_original_fixture('test_classifies_g17_register_value_source')
}

fn test_does_not_trace_g17_register_copy_across_join() {
	verify_original_fixture('test_does_not_trace_g17_register_copy_across_join')
}

fn test_recovers_g17_single_conditional_branch_merge() {
	verify_original_fixture('test_recovers_g17_single_conditional_branch_merge')
}

fn test_recovers_g17_test_bit_branch_merge() {
	verify_original_fixture('test_recovers_g17_test_bit_branch_merge')
}

fn test_recovers_g17_test_bit_branch_diamond() {
	verify_original_fixture('test_recovers_g17_test_bit_branch_diamond')
}

fn test_recovers_g17_compare_zero_branch_merge() {
	verify_original_fixture('test_recovers_g17_compare_zero_branch_merge')
}

fn test_recovers_g17_four_way_compare_merge() {
	verify_original_fixture('test_recovers_g17_four_way_compare_merge')
}

fn test_recovers_g17_nested_optional_bit_set() {
	verify_original_fixture('test_recovers_g17_nested_optional_bit_set')
}

fn test_recovers_g17_cl_table_or_fallback_base() {
	verify_original_fixture('test_recovers_g17_cl_table_or_fallback_base')
}

fn test_recovers_g17_cl_mode_selected_low_bit() {
	verify_original_fixture('test_recovers_g17_cl_mode_selected_low_bit')
}

fn test_rejects_g17_ambiguous_conditional_branch_merge() {
	verify_original_fixture('test_rejects_g17_ambiguous_conditional_branch_merge')
}

fn test_g17_prologue_definition_dominates_loop_backedge() {
	verify_original_fixture('test_g17_prologue_definition_dominates_loop_backedge')
}

fn test_recovers_g17_register_value_expression() {
	verify_original_fixture('test_recovers_g17_register_value_expression')
}

fn test_recovers_g17_movk_over_expression() {
	verify_original_fixture('test_recovers_g17_movk_over_expression')
}

fn test_recovers_bounded_deep_g17_value_expression() {
	verify_original_fixture('test_recovers_bounded_deep_g17_value_expression')
}

fn test_recovers_g17_dup_count_virtual_call_expression() {
	verify_original_fixture('test_recovers_g17_dup_count_virtual_call_expression')
}

fn test_explicit_g17_x0_writer_overrides_constant_call() {
	verify_original_fixture('test_explicit_g17_x0_writer_overrides_constant_call')
}

fn test_recovers_g17_memory_map_virtual_address_expression() {
	verify_original_fixture('test_recovers_g17_memory_map_virtual_address_expression')
}

fn test_rejects_untyped_g17_memory_map_slot_call() {
	verify_original_fixture('test_rejects_untyped_g17_memory_map_slot_call')
}

fn test_g17_bitfield_insert_expression_keeps_old_destination() {
	verify_original_fixture('test_g17_bitfield_insert_expression_keeps_old_destination')
}

fn test_recovers_g17_register_add_expression() {
	verify_original_fixture('test_recovers_g17_register_add_expression')
}

fn test_recovers_g17_conditional_value_and_predicate() {
	verify_original_fixture('test_recovers_g17_conditional_value_and_predicate')
}

fn test_recovers_g17_argument_rooted_object_load() {
	verify_original_fixture('test_recovers_g17_argument_rooted_object_load')
}

fn test_recovers_g17_argument_through_stack_spill() {
	verify_original_fixture('test_recovers_g17_argument_through_stack_spill')
}

fn test_does_not_trace_g17_stack_spill_across_join() {
	verify_original_fixture('test_does_not_trace_g17_stack_spill_across_join')
}

fn test_recovers_g17_paired_object_and_stack_loads() {
	verify_original_fixture('test_recovers_g17_paired_object_and_stack_loads')
}

fn test_recovers_g17_expression_through_value_copy() {
	verify_original_fixture('test_recovers_g17_expression_through_value_copy')
}

fn test_recovers_g17_inline_register_records() {
	verify_original_fixture('test_recovers_g17_inline_register_records')
}

fn test_rejects_g17_selector_sample_matching_emission_count() {
	verify_original_fixture('test_rejects_g17_selector_sample_matching_emission_count')
}

fn test_host_loop_width_and_exact_instruction_offsets() {
	assert sizeof(int) == 8
	wide := big.integer_from_string('1267650600228229401496703205376') or { panic(err) }
	instructions := [Instruction{ offset: wide, word: 0xd2800024 },
		Instruction{ offset: wide + big.integer_from_int(4), word: 0xd503201f }]
	result := value_expression(instructions, 1, 4, 0, []Visit{}) or { panic('missing constant') }
	assert j.string_value(j.value(result, 'producer_offset')) == wide.str()
	assert j.value(result, 'value').u64() == 1
	assert instructions[0].offset == wide
}

fn test_spill_byte_ranges_do_not_overflow_and_inputs_remain_owned() {
	wide := big.integer_from_string('1267650600228229401496703205376') or { panic(err) }
	instructions := [Instruction{ offset: big.zero_int, word: 0xf90003e0 },
		Instruction{ offset: big.integer_from_int(4), word: 0xd503201f }]
	if _ := stack_load(instructions, 1, wide, wide, 0, []Visit{}) {
		assert false
	}
	result := stack_load(instructions, 1, big.zero_int, big.integer_from_int(8), 0, []Visit{}) or { panic('missing spill') }
	assert j.string_value(j.value(result, 'kind')) == 'stack_reload'
	assert instructions[0].word == 0xf90003e0
}

fn test_wide_offsets_branch_order_and_index_diagnostics() {
	verify_original_fixture('test_wide_offsets_branch_order_and_index_diagnostics')
}
