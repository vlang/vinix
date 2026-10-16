// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.sessioncore

fn session_timezone_offset(fallback i64) i64 {
	reply := session_call('time.offset', []) or { return fallback }
	defer { unsafe { reply.free() } }
	return sessioncore.number(reply, -43200, 50400) or { fallback }
}
