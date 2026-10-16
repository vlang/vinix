// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.sessioncore
import time

fn session_shutdown() {
	if !session_call_ok('shutdown', []) { return }
	deadline := monotonic_millis() + 31000
	for monotonic_millis() < deadline {
		if !session_call_ok('ping', []) { return }
		time.sleep(100 * time.millisecond)
	}
	eprintln('vinix-desktop: session shutdown exceeded its deadline')
}

// A hosted application's portal requests come from its real process, below
// the native wrapper. Establish ancestry from kernel process records.
fn session_descendant(pid int, ancestor int) bool {
	if pid <= 0 || ancestor <= 0 { return false }
	mut current := pid
	for _ in 0 .. 32 {
		if current == ancestor { return true }
		path := '/proc/${current}/stat'
		record := sessioncore.load(path, 4096) or {
			unsafe { path.free() }
			return false
		}
		unsafe { path.free() }
		end := record.last_index(') ') or {
			unsafe { record.free() }
			return false
		}
		tail := unsafe { tos(&record.str[end + 2], record.len - end - 2) }
		parts := tail.split(' ')
		parent := if parts.len > 1 {
			int(sessioncore.number(parts[1], 1, 2147483647) or { 0 })
		} else {
			0
		}
		unsafe {
			for part in parts { part.free() }
			(&array(&parts)).free()
			record.free()
		}
		if parent <= 0 || parent == current { return false }
		current = parent
	}
	return false
}
