module t6050power

import os
import traceanalysis as j

fn check_transport_family(name string) ! {
	controls := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'testdata/transport.json'))!)!.arr()
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

fn test_original_initial_publication_precedes_pmp_readiness() {
	check_transport_family('recover_pmp_readiness_handshake')!
}

fn test_original_patchbay_u32_write_and_volatile_writeback() {
	check_transport_family('recover_rtbuddy_patchbay_write_contract')!
}

fn test_original_ascwrap_v6_iorvbar_lock_and_cpu_run_sequence() {
	check_transport_family('recover_apple_ascwrap_v6_code_contract')!
}

fn test_pc_proofs_preserve_address_arithmetic_and_missing_symbol_errors() {
	assert pc_targets(Function{j.Value(j.Number{'1.0'}), encoded_words([u32(0xd503201f)])})! == []u64{}
	mut rejected := false
	pc_targets(Function{j.Value(j.Number{'1.0'}), encoded_words([u32(0x90000000)])}) or {
		assert err.msg() == "TypeError: unsupported operand type(s) for &: 'float' and 'int'"
		rejected = true
	}
	assert rejected
	rejected = false
	symbol(map[string]j.Value{}, 'required') or {
		assert err.msg() == 'KeyError: required'
		rejected = true
	}
	assert rejected
}

fn test_vtable_equality_checks_every_exact_key_and_numeric_value() {
	expected := {
		'2416': j.Value(0)
		'2584': j.Value(u64(0xffffffffffffffff))
	}
	assert integer_maps_equal({
		'2416': j.Value(false)
		'2584': j.Value(u64(0xffffffffffffffff))
	}, expected)
	assert !integer_maps_equal({
		'2416': j.Value(false)
	}, expected)
	assert !integer_maps_equal({
		'2416': j.Value(false)
		'2584': j.Value('18446744073709551615')
	}, expected)
}
