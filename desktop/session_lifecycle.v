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

fn session_limit_service_log(home string, name string) {
	path := '${home}/.vinix-service-logs/${name}.log'
	defer { unsafe { path.free() } }
	mut info := C.stat{}
	if C.lstat(&char(path.str), &info) != 0 || u32(info.st_mode) & C.S_IFMT != C.S_IFREG || info.st_size <= 1024 * 1024 {
		return
	}
	fd := C.open(&char(path.str), C.O_WRONLY | C.O_TRUNC | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
	if fd < 0 { return }
	defer { desktop_close(fd) }
	message := 'vinix-session: log exceeded 1 MiB; older output discarded\n'
	C.write(fd, message.str, usize(message.len))
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
