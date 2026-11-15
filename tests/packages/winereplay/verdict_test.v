// SPDX-License-Identifier: GPL-2.0-or-later
module winereplay

fn test_success_requires_each_complete_line_once_before_deadline() {
	serial := markers[..].join('\n')
	assert assess(serial, limit - 1, true).passed
	assert assess(serial.replace('\n', '\r\n') + '\r\n', 1, true).passed
	assert !assess(serial, limit, true).passed
	assert assess(serial, limit, true).reason.contains('900-second')
	assert !assess(serial, limit + 1, true).passed
	assert assess('', 0, true) == Decision{}
	assert assess('', 0, false).reason == 'guest stopped before acceptance'
	for missing in 0 .. markers.len {
		mut partial := []string{}
		for index, marker in markers { if index != missing { partial << marker } }
		text := partial.join('\n')
		assert !assess(text, 0, true).finished
		assert !assess(text, 0, false).passed
		assert !assess(text + '\nquoted: ' + markers[missing], 0, true).finished
		assert !assess(text + '\n' + markers[missing] + ' extra', 0, true).finished
	}
	for marker in markers {
		duplicate := assess(serial + '\n' + marker, 0, true)
		assert duplicate.finished && !duplicate.passed && duplicate.reason.contains('duplicate')
	}
	for forbidden in ['HWTEST FAIL', 'Kernel panic', 'KERNEL PANIC', 'FATAL EXCEPTION'] {
		decision := assess(serial + '\n' + forbidden, 0, true)
		assert decision.finished && !decision.passed && decision.reason == 'forbidden guest output'
	}
}
