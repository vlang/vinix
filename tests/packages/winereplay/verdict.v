// SPDX-License-Identifier: GPL-2.0-or-later
module winereplay

import time

pub const limit = 900 * time.second
pub const markers = [
	'HWTEST INFO Wine ordinary-caller-SIGKILL outer-status137 holder-alive PASS',
	'HWTEST INFO Wine manager-SIGKILL adopted-server foreign-refusal126 lease-busy PASS',
	'HWTEST INFO Wine migration stale-generation refusal all-targets-unchanged PASS',
	'HWTEST INFO Wine rollback stale-generation refusal all-targets-unchanged PASS',
	'HWTEST INFO Wine rollback prefix migrated and real Win64 relaunched status37 PASS',
	'HWTEST INFO Wine rolled-back prefix relaunch status37 private-data lease-free collected PASS',
	'HWTEST PASS packaged-Wine',
]!

pub struct Decision {
pub:
	finished bool
	passed bool
	reason string
}

fn line_equals(serial string, start int, end int, wanted string) bool {
	if end - start != wanted.len { return false }
	for index, byte in wanted { if serial[start + index] != byte { return false } }
	return true
}

// Exact lines, each once. No allocations on the repeated observation path.
// A late success, forbidden output or duplicate can never produce acceptance.
pub fn assess(serial string, elapsed i64, alive bool) Decision {
	if serial.contains('HWTEST FAIL') || serial.contains('Kernel panic')
		|| serial.contains('KERNEL PANIC') || serial.contains('FATAL EXCEPTION') {
		return Decision{finished: true, reason: 'forbidden guest output'}
	}
	if elapsed >= limit { return Decision{finished: true, reason: 'guest exceeded unchanged 900-second rollback bound'} }
	mut counts := [7]u8{}
	mut start := 0
	for end in 0 .. serial.len + 1 {
		if end < serial.len && serial[end] != `\n` { continue }
		mut stop := end
		if stop > start && serial[stop - 1] == `\r` { stop-- }
		for index, marker in markers {
			if line_equals(serial, start, stop, marker) {
				counts[index]++
				if counts[index] > 1 { return Decision{finished: true, reason: 'duplicate guest acceptance marker'} }
			}
		}
		start = end + 1
	}
	mut complete := true
	for count in counts { if count != 1 { complete = false } }
	if complete { return Decision{finished: true, passed: true} }
	if !alive { return Decision{finished: true, reason: 'guest stopped before acceptance'} }
	return Decision{}
}
