// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.sessioncore
import desktop.sessionipc

fn session_offer_data(kind sessioncore.DataKind, data string, sensitive bool) bool {
	return sessionipc.offer_data(kind, data, sensitive)
}

fn (d &Desktop) session_sender_has_gesture(pid int) bool {
	if monotonic_millis() - d.hub.gesture_at > 5000 { return false }
	for window in d.windows {
		if window.id != d.focus || window.app_index < 0 || window.app_index >= d.apps.len {
			continue
		}
		app := d.apps[window.app_index]
		if app is RemoteApp {
			return app.pid == d.hub.gesture_pid && !app.closed && (app.pid == pid || session_descendant(pid, app.pid))
		}
	}
	return false
}

fn (mut d Desktop) mark_session_gesture() {
	d.hub.gesture_at = monotonic_millis()
	d.hub.gesture_pid = 0
	for window in d.windows {
		if window.id != d.focus || window.app_index < 0 || window.app_index >= d.apps.len {
			continue
		}
		app := d.apps[window.app_index]
		if app is RemoteApp { d.hub.gesture_pid = app.pid }
	}
}

fn (mut d Desktop) accept_session_offer(pid int) {
	if !d.session_sender_has_gesture(pid) || !d.hub.policy.clipboard_apps { return }
	owner := pid.str()
	args := [owner]
	ok := session_call_ok('clipboard.promote', args)
	unsafe {
		owner.free()
		(&array(&args)).free()
	}
	if !ok { return }
	reply := session_call('clipboard.snapshot', []) or { return }
	defer { unsafe { reply.free() } }
	f := sessioncore.fields(reply) or { return }
	if f.count != 5 || f.values[0] != 'data' { return }
	kind := unsafe { sessioncore.DataKind(sessioncore.number(f.values[1], 0, 3) or { return }) }
	sensitive := sessioncore.number(f.values[3], 0, 1) or { return }
	owner_pid := int(sessioncore.number(f.values[4], 1, 2147483647) or { return })
	if owner_pid != pid { return }
	data := sessioncore.decode_data(f.values[2]) or { return }
	defer { unsafe { data.free() } }
	d.hub.clipboard.history_enabled = d.hub.policy.clipboard_history
	d.hub.clipboard.copy(C.getuid(), pid, kind, data, sensitive == 1) or { return }
	if kind == .text {
		d.clipboard.close_request()
		d.clipboard.set_local_text(data)
	}
	d.dirty = true
}

fn (mut d Desktop) clear_session_clipboard() {
	_ = session_call_ok('clipboard.clear', [])
	d.hub.clipboard.clear()
	d.clipboard.close_request()
	d.clipboard.local_bytes = [clipboard_max_bytes]u8{}
	d.clipboard.local_length = 0
	d.clipboard.local_available = false
	d.dirty = true
}

fn (mut d Desktop) grant_session_transfer(pid int) {
	if !d.session_sender_has_gesture(pid) || !d.hub.policy.clipboard_apps { return }
	owner := pid.str()
	args := [owner]
	reply := session_call('exchange.grant', args) or {
		unsafe {
			owner.free()
			(&array(&args)).free()
		}
		return
	}
	unsafe {
		owner.free()
		(&array(&args)).free()
		reply.free()
	}
}
