module t6050power

import os
import math.big
import traceanalysis as j

fn contracts() ![]j.Value {
	return j.decode(os.read_file(os.join_path(os.dir(@FILE), 'testdata/contracts.json'))!)!.arr()
}

fn check_family(name string) ! {
	mut checked := 0
	for value in contracts()! {
		record := value.as_map()
		if j.string_value(j.value(record, 'function')) != name { continue }
		arguments := j.value(record, 'arguments').as_map()
		actual := query(name, arguments) or {
			assert err.msg() == j.string_value(j.value(record, 'error'))
			assert j.value(record, 'kind') == j.Value('ValueError')
			checked++
			continue
		}
		assert 'result' in record
		assert j.encode(actual, false) == j.encode(j.value(record, 'result'), false)
		checked++
	}
	assert checked > 0
}

fn test_original_apple_ptd_read_and_write_windows() {
	check_family('recover_apple_ptd_code_contract')!
}

fn test_original_rtbuddy_segment_flag_inversion_and_writability() {
	check_family('recover_rtbuddy_segment_flag_contract')!
}

fn test_original_iodart_direction_lookup_and_per_page_insertion() {
	check_family('recover_iodart_family_code_contract')!
}

fn test_original_apple_t8110_protected_iommu_mapping_and_count() {
	check_family('recover_apple_t8110_dart_code_contract')!
}

fn test_original_t8110_kernel_page_table_mask_and_shift_ownership() {
	check_family('recover_t8110_kernel_code_contract')!
}

fn test_wide_signed_and_float_integer_comparisons_are_exact() {
	wide := big.one_int.left_shift(200)
	assert integer_equal(j.Value(j.Number{wide.str()}), j.Value(j.Number{wide.str() + '.0'}))
	assert integer_equal(j.Value(j.Number{(big.zero_int - wide).str()}), j.Value(j.Number{(big.zero_int - wide).str() + '.0'}))
	assert integer_equal(j.Value(false), j.Value(0))
	assert integer_equal(j.Value(true), j.Value(j.Number{'1.0'}))
	assert !integer_equal(j.Value('1'), j.Value(1))
	assert !integer_equal(j.Value(u64(0xffffffffffffffff)), j.Value(j.Number{'18446744073709551616.0'}))
	assert !integer_equal(j.Value(j.Number{'1.25'}), j.Value(1))
}

fn test_tuple_diagnostics_quote_strings_and_keep_singleton_comma() {
	assert tuple_repr([j.Value('1'), j.Value(true)]) == "('1', True)"
	assert tuple_repr([j.Value(1)]) == '(1,)'
}

fn test_malformed_addresses_fail_only_when_a_direct_branch_is_decoded() {
	addresses := [j.Value('string'), j.Value([]j.Value{}), j.Value(map[string]j.Value{}),
		j.Value(j.Number{'1.0'}), j.Value(j.Number{'1.25'})]
	messages := ['can only concatenate str (not "int") to str',
		'can only concatenate list (not "int") to list',
		"unsupported operand type(s) for +: 'dict' and 'int'",
		"unsupported operand type(s) for &: 'float' and 'int'",
		"unsupported operand type(s) for &: 'float' and 'int'"]
	for index, address in addresses {
		assert branch_count(Function{address, encoded_words([u32(0xd503201f)])}, j.Value(0))! == 0
		branch_count(Function{address, encoded_words([u32(0x94000000)])}, j.Value(0)) or {
			assert err.msg() == 'TypeError: ' + messages[index]
			continue
		}
		assert false
	}
	assert branch_count(Function{j.Value(true), encoded_words([u32(0x94000000)])}, j.Value(1))! == 1
	assert branch_count(Function{j.Value(j.Number{big.one_int.left_shift(200).str()}), encoded_words([u32(0x94000000)])}, j.Value(0))! == 1
}

fn test_proof_returns_a_copied_direction_lookup() {
	mut values := [j.Value(0), j.Value(2), j.Value(1), j.Value(3)]
	for record in contracts()! {
		fields := record.as_map()
		if j.string_value(j.value(fields, 'function')) != 'recover_iodart_family_code_contract' || 'result' !in fields {
			continue
		}
		arguments := j.value(fields, 'arguments').as_map()
		functions := functions_from_json(j.value(arguments, 'functions'))!
		result := recover_iodart_family_code_contract(functions, j.value(arguments, 'vtable_targets').as_map(), values)!
		values[0] = j.Value(99)
		assert j.value(j.value(result, 'mapper').as_map(), 'direction_lookup').arr()[0] == j.Value(0)
		return
	}
	assert false
}

fn test_branch_target_set_membership_keeps_unhashable_target_errors() {
	for target in [j.Value(map[string]j.Value{}), j.Value([]j.Value{})] {
		branch_target_exists(Function{j.Value(0), []u8{}}, target) or {
			assert err.msg() == "TypeError: unhashable type: '" +
				if target is map[string]j.Value { 'dict' } else { 'list' } + "'"
			continue
		}
		assert false
	}
}
