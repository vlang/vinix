module g17expr

import encoding.hex
import g17decode as arm
import math.big
import traceanalysis as j

fn transport_contract(operation string, request map[string]j.Value) !map[string]j.Value {
	pairs := match operation {
		'recover_g17_boot_transport' {
			[['notify_code', 'G17 firmware-start notification'],
				['receive_code', 'G17 AKF message handling'],
				['boot_code', 'G17 dual-role firmware boot']]
		}
		'recover_g17_rtbuddy_endpoints' {
			[['matched_code', 'G17 RTBuddy endpoint matching'],
				['read_code', 'G17 RTBuddy message receive'], ['send_code', 'G17 RTBuddy message send'],
				['enable_code', 'G17 RTBuddy endpoint enable'],
				['received_code', 'G17 RTBuddy receive forwarding']]
		}
		else { return error('unknown transport ' + operation) }
	}
	for pair in pairs { command_check(hex.decode(text(request, pair[0]))!, pair[1])! }
	return command_metadata(operation)
}

fn handoff_contract(code []u8) !map[string]j.Value {
	if arm.find_materialized_constant(code, j.Value(u64(command_number('INTERFACE_MAGIC')))).len > 0 {
		return error('UAT handoff unexpectedly contains the firmware interface magic')
	}
	materialized := arm.find_materialized_constant(code, j.Value(u64(0x4b1d000000000002)))
	if materialized.len != 1 {
		return error('expected one uPPL magic sequence, found ${materialized.len}')
	}
	triple := materialized[0].arr()
	start := triple[0].int()
	end := triple[1].int()
	register := triple[2].int()
	mut stores := map[string]bool{}
	for instruction in instructions_from_code(code[end..]) {
		if store := fields('decode_str_unsigned', instruction.word, instruction.offset) {
			stores[j.encode(j.Value(store), false)] = true
		}
	}
	expected := [[register, 0, 0, 8], [31, 0, 0x10, 1], [31, 0, 0x11, 1], [31, 0, 0x14, 4],
		[9, 0, 0x18, 4], [8, 0, 0x638, 1], [31, 0, 0x640, 8]]
	mut missing := []j.Value{}
	for store in expected {
		value := j.Value(store.map(j.Value(it)))
		if j.encode(value, false) !in stores { missing << value }
	}
	if missing.len > 0 {
		// Original diagnostics show tuples inside the list.
		mut items := []string{}
		for entry in missing {
			values := entry.arr()
			items << '(' + values.map(j.string_value(it)).join(', ') + ')'
		}
		return error('missing G17 handoff stores: [' + items.join(', ') + ']')
	}
	clear := hex.decode('290880521f011fb81f811ff81f8501f8290500f181ffff54')!
	mut found := false
	for offset := start; offset <= code.len - clear.len; offset++ {
		if code[offset..offset + clear.len] == clear {
			found = true
			break
		}
	}
	if !found { return error('G17 handoff does not contain the 65-record clear loop') }
	return command_metadata('recover_g17_handoff')
}
