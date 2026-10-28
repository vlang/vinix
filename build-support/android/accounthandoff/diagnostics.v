// SPDX-License-Identifier: GPL-2.0-or-later
// Finite public account-handoff schema shared by producer and receipt parser.
module accounthandoff

pub enum Stage {
	admitted = 1
	dispatch_queued
	interaction_received
	interaction_delivered
	redeemed
	ui_begin
	ui_ready
	launch_queued
	terminal
	ui_begin_failed
	ui_request_ended
	ui_tick_failed
	ui_closed
}

// Stable numeric fields, with no per-request correlation key. Operations are
// addAccount=2, redeem=3, getAuthToken=4; terminal events are result=1/failure=2.
pub struct HandoffDiagnostic {
pub:
	stage     int
	operation int
	event     int
	code      int
}

pub fn valid_handoff(record HandoffDiagnostic) bool {
	if record.stage < 1 || record.stage > 13 || record.operation !in [2, 3, 4] {
		return false
	}
	if record.stage == int(Stage.terminal) {
		return (record.event == 1 && record.code == 0)
			|| (record.event == 2 && (record.code == -1 || (record.code >= 1 && record.code <= 9)))
	}
	return record.event == 0 && record.code == 0
		&& (record.stage == int(Stage.admitted) || record.operation != 3)
}

// Accept exactly one canonical record without a newline. Callers retain the
// numbers, never the original log line. Unknown/extra fields fail shut.
pub fn parse_handoff_diagnostic(line string) !HandoffDiagnostic {
	if line.len > 96 { return error('invalid account handoff diagnostic') }
	names := ['ANDROID-ACCOUNT-HANDOFF stage=', ' operation=', ' event=', ' code=']!
	mut numbers := [4]int{}
	mut cursor := 0
	for index, name in names {
		if cursor + name.len >= line.len { return error('invalid account handoff diagnostic') }
		for offset in 0 .. name.len {
			if line[cursor + offset] != name[offset] { return error('invalid account handoff diagnostic') }
		}
		value, end := handoff_number(line, cursor + name.len)!
		numbers[index] = value
		cursor = end
	}
	if cursor != line.len { return error('invalid account handoff diagnostic') }
	record := HandoffDiagnostic{numbers[0], numbers[1], numbers[2], numbers[3]}
	if !valid_handoff(record) { return error('invalid account handoff diagnostic') }
	return record
}

// Direct byte scanning keeps successful log polling allocation-free even in
// the controller's -gc none build. No substring or formatted integer escapes.
fn handoff_number(line string, start int) !(int, int) {
	mut cursor := start
	negative := line[cursor] == `-`
	if negative { cursor++ }
	first := cursor
	mut number := 0
	for cursor < line.len && line[cursor] >= `0` && line[cursor] <= `9` {
		number = number * 10 + int(line[cursor] - `0`)
		if number > 13 { return error('invalid account handoff diagnostic') }
		cursor++
	}
	if cursor == first || (cursor - first > 1 && line[first] == `0`)
		|| (negative && number != 1) { return error('invalid account handoff diagnostic') }
	return if negative { -number } else { number }, cursor
}
