// SPDX-License-Identifier: GPL-2.0-or-later
module hwhost

fn test_clean_line_removes_what_a_terminal_acts_on() {
	// What OVMF writes before its first words, as it is in a serial log.
	firmware := '\x1b[2J\x1b[01;01H\x1b[=3h\x1b[2J\x1b[01;01HBdsDxe: loading Boot0001\r'
	assert clean_line(firmware) == 'BdsDxe: loading Boot0001'
	assert clean_line('HWTEST \x1b[1;32mPASS\x1b[0m devices\r') == 'HWTEST PASS devices'
	// A window title, ended either way it can be.
	assert clean_line('\x1b]0;title\x07HWTEST START a') == 'HWTEST START a'
	assert clean_line('\x1b]0;title\x1b\\HWTEST START a') == 'HWTEST START a'
	assert clean_line('\x1bcHWTEST START a') == 'HWTEST START a'
	assert clean_line('a\tb\x00\x07\x08c\x7f') == 'a\tbc'
	// An escape the log ends in the middle of does not run past the end.
	assert clean_line('abc\x1b') == 'abc'
	assert clean_line('abc\x1b[12') == 'abc'
	assert clean_line('') == ''
}

fn test_lines_are_whole_before_they_are_seen() {
	mut serial := SerialLines{}
	assert serial.feed('HWTEST ST'.bytes()) == []string{}
	assert serial.feed('ART devices\r\nHWTEST P'.bytes()) == ['HWTEST START devices']
	assert serial.feed('ASS devices\r\n\r\nrest'.bytes()) == ['HWTEST PASS devices', '']
	assert serial.lines == ['HWTEST START devices', 'HWTEST PASS devices', '']
	// What the machine wrote last without ending the line.
	assert serial.finish() == ['rest']
	assert serial.finish() == []string{}
	assert serial.lines.len == 4
}

fn test_an_escape_split_between_two_reads_is_still_removed() {
	mut serial := SerialLines{}
	assert serial.feed('\x1b[01;'.bytes()) == []string{}
	assert serial.feed('01HHWTEST START a\n'.bytes()) == ['HWTEST START a']
}

fn test_tail_is_the_last_lines() {
	mut serial := SerialLines{}
	serial.feed('1\n2\n3\n'.bytes())
	assert serial.tail(2) == ['2', '3']
	assert serial.tail(40) == ['1', '2', '3']
}

fn test_required_markers_are_substrings_of_lines() {
	mut watch := new_marker_watch(['HWTEST START devices', 'HWTEST PASS devices'], always_forbidden)
	assert watch.missing() == ['HWTEST START devices', 'HWTEST PASS devices']
	watch.line('[  1.2] HWTEST START devices')
	assert watch.missing() == ['HWTEST PASS devices']
	assert !watch.complete()
	// Another scenario's verdict is not this one's.
	watch.line('HWTEST PASS device')
	assert !watch.complete()
	watch.line('HWTEST PASS devices')
	assert watch.complete()
	assert !watch.failed()
}

fn test_a_marker_is_not_matched_in_half_a_line() {
	mut serial := SerialLines{}
	mut watch := new_marker_watch(['HWTEST PASS a'], []string{})
	for line in serial.feed('HWTEST PASS a'.bytes()) {
		watch.line(line)
	}
	// "HWTEST PASS a" may yet turn out to be "HWTEST PASS ahci".
	assert !watch.complete()
	for line in serial.feed('\n'.bytes()) {
		watch.line(line)
	}
	assert watch.complete()
}

fn test_a_marker_the_terminal_codes_split_is_matched() {
	mut watch := new_marker_watch(['HWTEST PASS a'], []string{})
	watch.line(clean_line('HWTEST \x1b[0mPASS a\r'))
	assert watch.complete()
}

fn test_the_first_forbidden_marker_is_kept() {
	mut watch := new_marker_watch(['HWTEST PASS a'], ['KERNEL PANIC', 'HWTEST FAIL'])
	watch.line('fine')
	assert !watch.failed()
	watch.line('HWTEST FAIL a: state after unbind is "bound"')
	watch.line('  *** Vinix KERNEL PANIC on CPU 0 ***')
	assert watch.failed()
	assert watch.forbidden_marker == 'HWTEST FAIL'
	assert watch.forbidden_line == 'HWTEST FAIL a: state after unbind is "bound"'
}

fn test_actions_run_in_order_each_after_its_own_marker() {
	mut cursor := new_action_cursor([
		Action{
			after: 'STEP one'
			qmp:   '{"execute":"stop"}'
		},
		Action{
			after:    'STEP two'
			qmp:      '{"execute":"cont"}'
			delay_ms: 500
		},
	])
	assert !cursor.done()
	assert cursor.waiting_for() == 'STEP one'
	// The second action's marker before the first's triggers nothing.
	cursor.line('HWTEST STEP two', 0)
	if _ := cursor.take_due(0) {
		assert false, 'an action ran before its marker'
	}
	cursor.line('HWTEST STEP one', 100)
	first := cursor.take_due(100) or { panic('the first action is due') }
	assert first.qmp == '{"execute":"stop"}'
	if _ := cursor.take_due(100) {
		assert false, 'an action ran twice'
	}
	assert cursor.waiting_for() == 'STEP two'
	cursor.line('HWTEST STEP two', 200)
	assert cursor.waiting_for() == ''
	// Not before its delay has passed.
	if _ := cursor.take_due(699) {
		assert false, 'an action ran before its delay'
	}
	second := cursor.take_due(700) or { panic('the second action is due') }
	assert second.qmp == '{"execute":"cont"}'
	assert cursor.done()
}

fn test_a_marker_printed_during_a_delay_counts_for_the_next_action() {
	mut cursor := new_action_cursor([
		Action{
			after:    'STEP'
			qmp:      '{"execute":"stop"}'
			delay_ms: 1000
		},
		Action{
			after: 'STEP'
			qmp:   '{"execute":"cont"}'
		},
	])
	cursor.line('HWTEST STEP', 0)
	// The same words again, while the first command is still to be sent.
	cursor.line('HWTEST STEP', 10)
	first := cursor.take_due(1000) or { panic('the first action is due') }
	assert first.qmp == '{"execute":"stop"}'
	second := cursor.take_due(1000) or { panic('the second action is due') }
	assert second.qmp == '{"execute":"cont"}'
	assert cursor.done()
}

fn test_one_line_triggers_one_action() {
	mut cursor := new_action_cursor([
		Action{
			after: 'STEP'
			qmp:   '{"execute":"stop"}'
		},
		Action{
			after: 'STEP'
			qmp:   '{"execute":"cont"}'
		},
	])
	cursor.line('HWTEST STEP', 0)
	cursor.take_due(0) or { panic('the first action is due') }
	if _ := cursor.take_due(0) {
		assert false, 'one line triggered two actions'
	}
	assert !cursor.done()
}

fn test_an_action_can_wait_for_an_event_as_well_as_its_marker() {
	mut cursor := new_action_cursor([
		Action{
			after:          'STEP asleep'
			qmp:            '{"execute":"system_wakeup"}'
			event:          'SUSPEND'
			event_count:    2
			event_delay_ms: 500
		},
	])
	// An earlier sleep of the same machine: the event has arrived once.
	mut events := EventLog{}
	events.note('SUSPEND')
	events.note('WAKEUP')
	// No event is enough before the marker has been seen.
	if _ := cursor.take_ready(0, &events) {
		assert false, 'an action ran before its marker'
	}
	cursor.line('HWTEST STEP asleep', 100)
	assert cursor.waiting_for() == ''
	assert cursor.waiting_for_event() == 'SUSPEND (number 2)'
	// The marker alone is not enough either: the machine has suspended once.
	if _ := cursor.take_ready(5000, &events) {
		assert false, 'an action ran before its event'
	}
	events.note('SUSPEND')
	// The event has come; its delay starts when that is noticed.
	if _ := cursor.take_ready(6000, &events) {
		assert false, 'an action ran before the delay after its event'
	}
	assert cursor.waiting_for_event() == ''
	if _ := cursor.take_ready(6499, &events) {
		assert false, 'an action ran before the delay after its event had passed'
	}
	action := cursor.take_ready(6500, &events) or { panic('the action is ready') }
	assert action.qmp == '{"execute":"system_wakeup"}'
	assert cursor.done()
}

fn test_an_action_without_an_event_is_ready_when_it_is_due() {
	mut cursor := new_action_cursor([
		Action{
			after:    'STEP'
			qmp:      '{"execute":"stop"}'
			delay_ms: 50
		},
	])
	cursor.line('HWTEST STEP', 0)
	nothing := EventLog{}
	if _ := cursor.take_ready(49, &nothing) {
		assert false, 'an action ran before its delay'
	}
	cursor.take_ready(50, &nothing) or { panic('the action is ready') }
	assert cursor.done()
}
