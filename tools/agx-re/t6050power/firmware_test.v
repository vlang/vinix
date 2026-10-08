module t6050power

import os
import traceanalysis as j

fn check_firmware_family(name string) ! {
	controls := j.decode(os.read_file(os.join_path(os.dir(@FILE), 'testdata/firmware.json'))!)!.arr()
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

fn test_original_apple_pmp_attachment_mailbox_and_ping_completion() {
	check_firmware_family('recover_apple_pmp_code_contract')!
}

fn test_original_pmp_firmware_mandatory_patches_and_rtbuddy_fixup_order() {
	check_firmware_family('recover_apple_pmp_firmware_code_contract')!
}

fn test_original_rtkit_cpu_start_hello_and_endpoint_roll_call() {
	check_firmware_family('recover_rtbuddy_boot_handshake_code_contract')!
}

fn test_branch_call_cardinality_and_original_negative_unpack_offset() {
	body := Function{j.Value(0x1000), encoded_words([u32(0x94000004), u32(0xd503201f), u32(0x94000002)])}
	assert call_offsets(body, j.Value(0x1010))! == [0, 8]
	assert python_word_at(body.code, -4) == u32(0x94000002)
	assert python_word_at(body.code, 0) == u32(0x94000004)
	mut rejected := false
	unique_call_offset(body, j.Value(0x1010), 'must be exactly one') or {
		assert err.msg() == 'must be exactly one'
		rejected = true
	}
	assert rejected
}

fn test_readiness_dictionary_keeps_exact_keys_and_python_numeric_equality() {
	mut fields := map[string]j.Value{
		'target':    j.Value(j.Number{'4096.0'})
		'condition': j.Value('bit_clear')
		'register':  j.Value(j.Number{'8e0'})
		'bit':       j.Value(false)
		'bytes':     j.Value(j.Number{'4.0'})
	}
	assert ready_clear_branch(j.Value(fields), j.Value(4096))
	fields['bit'] = j.Value(true)
	assert !ready_clear_branch(j.Value(fields), j.Value(4096))
	fields['bit'] = j.Value(false)
	fields['extra'] = j.Value(0)
	assert !ready_clear_branch(j.Value(fields), j.Value(4096))
	fields.delete('extra')
	fields['register'] = j.Value('8')
	assert !ready_clear_branch(j.Value(fields), j.Value(4096))
}
