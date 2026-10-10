// SPDX-License-Identifier: GPL-2.0-or-later
module hwhost

fn test_a_command_is_one_line() {
	assert qmp_frame('{"execute":"system_powerdown"}')! == '{"execute":"system_powerdown"}\n'
	// Written over several lines in a scenario, sent as one.
	assert qmp_frame('{"execute": "device_del",\n  "arguments": {"id": "hwn0"}}\n')! == '{"execute": "device_del",   "arguments": {"id": "hwn0"}}\n'
	assert qmp_frame('  {"execute":"cont"}  ')!.count('\n') == 1
}

fn refused(command string) string {
	qmp_frame(command) or { return err.msg() }
	return ''
}

fn test_what_is_not_a_command_is_refused() {
	assert refused('{"execute":"stop"}') == ''
	assert refused('{"execute":"stop"').contains('not JSON')
	assert refused('system_powerdown').contains('not JSON')
	assert refused('["execute"]').contains('not a JSON object')
	assert refused('{"exec":"stop"}').contains('no "execute"')
	assert refused('{"execute":5}').contains('no "execute" name')
	assert refused('{"execute":""}').contains('no "execute" name')
}

fn test_messages_are_told_apart() {
	greeting := qmp_parse('{"QMP": {"version": {"qemu": {"micro": 1, "minor": 1, "major": 11}, "package": ""}, "capabilities": ["oob"]}}')
	assert greeting.kind == .greeting
	assert qmp_parse('{"return": {}}\r').kind == .reply
	failure := qmp_parse('{"error": {"class": "DeviceNotFound", "desc": "Device \'hwn9\' not found"}}')
	assert failure.kind == .failure
	assert failure.detail == "Device 'hwn9' not found"
	button := qmp_parse('{"timestamp": {"seconds": 1791632418, "microseconds": 278480}, "event": "POWERDOWN"}')
	assert button.kind == .event
	assert button.event == 'POWERDOWN'
	assert button.reason == ''
	assert qmp_parse('not json').kind == .unknown
	assert qmp_parse('[1, 2]').kind == .unknown
	assert qmp_parse('{"id": 1}').kind == .unknown
	assert qmp_parse('').kind == .unknown
}

fn test_shutdown_says_who_ended_the_machine() {
	guest := qmp_parse('{"timestamp": {"seconds": 1, "microseconds": 2}, "event": "SHUTDOWN", "data": {"guest": true, "reason": "guest-shutdown"}}')
	assert guest.event == 'SHUTDOWN'
	assert guest.reason == 'guest-shutdown'
	host := qmp_parse('{"timestamp": {"seconds": 1, "microseconds": 2}, "event": "SHUTDOWN", "data": {"guest": false, "reason": "host-signal"}}')
	assert host.reason == 'host-signal'
}

fn test_messages_are_framed_by_newlines_wherever_reads_end() {
	// An event and a reply as QEMU sends them, cut at arbitrary places.
	wire := '{"timestamp": {"seconds": 1, "microseconds": 2}, "event": "POWERDOWN"}\r\n{"return": {}}\r\n'
	for cut in [1, 17, 70, 71, 72, wire.len - 1] {
		mut splitter := LineSplitter{}
		mut kinds := []QmpKind{}
		for part in [wire[..cut], wire[cut..]] {
			for line in splitter.feed(part.bytes()) {
				kinds << qmp_parse(line).kind
			}
		}
		assert kinds == [QmpKind.event, .reply], 'cut at ${cut}'
		if _ := splitter.rest() {
			assert false, 'bytes left over with the cut at ${cut}'
		}
	}
}

fn test_half_a_message_is_not_a_message() {
	mut splitter := LineSplitter{}
	assert splitter.feed('{"return": '.bytes()) == []string{}
	assert splitter.feed('{}}'.bytes()) == []string{}
	assert splitter.feed('\r\n'.bytes()) == ['{"return": {}}\r']
}
