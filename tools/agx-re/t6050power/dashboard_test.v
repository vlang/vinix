module t6050power

import os
import math.big
import traceanalysis as j

fn check_dashboard_family(name string) ! {
	controls := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'testdata/dashboard.json'))!)!.arr()
	mut checked := 0
	for item in controls {
		control := item.as_map()
		if j.string_value(j.value(control, 'function')) != name { continue }
		actual := query(name, j.value(control, 'arguments').as_map()) or {
			assert err.msg() == j.string_value(j.value(control, 'error'))
			assert j.value(control, 'kind') == j.Value('ValueError')
			checked++
			continue
		}
		assert 'result' in control
		assert j.encode(actual, false) == j.encode(j.value(control, 'result'), false)
		checked++
	}
	assert checked != 0
}

fn test_original_pmp_dashboard_request_status_acknowledgement_and_readiness() {
	check_dashboard_family('recover_pmp_code_contract')!
}

fn test_original_t6050_pmgr_sixty_regmap_calls_and_resume_republication() {
	check_dashboard_family('recover_t6050_pmgr_code_contract')!
}

fn test_byte_search_count_and_slice_keep_python_byte_offsets() {
	code := [u8(0), 1, 0, 1, 0]
	assert bytes_find(code, [u8(0), 1], 0) == 0
	assert bytes_find(code, [u8(0), 1], 1) == 2
	assert bytes_find(code, [u8(0), 1], -3) == 2
	assert bytes_find(code, []u8{}, code.len + 1) == -1
	assert bytes_count([u8(1), 1, 1, 1, 1], [u8(1), 1]) == 2
	assert bytes_count(code, []u8{}) == code.len + 1
	assert bytes_slice(code, -3, 100) == [u8(0), 1, 0]
	assert bytes_slice(code, 3, 1) == []u8{}
}

fn test_movz_decoder_preserves_wide_words_and_exact_operand_errors() {
	assert query('_decode_movz_w', {
		'word':     j.Value(j.Number{(big.one_int.left_shift(200) + big.integer_from_int(0x52800001)).str()})
		'register': j.Value(1)
	})! == j.Value(u32(0))
	assert query('_decode_movz_w', {
		'word':     j.Value(u32(0x52800001))
		'register': j.Value(u64(0x100000001))
	})! == j.value(map[string]j.Value{}, 'missing')
	mut rejected := false
	query('_decode_movz_w', {
		'word':     j.Value(j.Number{'1.0'})
		'register': j.Value(1)
	}) or {
		assert err.msg() == "TypeError: unsupported operand type(s) for &: 'float' and 'int'"
		rejected = true
	}
	assert rejected
}

fn test_vtable_diagnostics_preserve_signed_width_and_format_errors() {
	assert format_hex(j.Value(j.Number{'1606938044258990275541962092341162602522202993782792835301376'}))! == '0x100000000000000000000000000000000000000000000000000'
	assert format_hex(j.Value(-1))! == '-0x1'
	mut rejected := false
	format_hex(j.Value(j.Number{'1.0'})) or {
		assert err.msg() == "Unknown format code 'x' for object of type 'float'"
		rejected = true
	}
	assert rejected
}
