// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.sessioncore
import net.urllib
import os
import ui2

const session_hub_tabs = ['Workspaces', 'Notifications', 'Clipboard', 'Services', 'Help']!
const session_hub_tab_ids = ['session.tab.0', 'session.tab.1', 'session.tab.2', 'session.tab.3',
	'session.tab.4']!
const session_layout_ids = ['session.layout.0', 'session.layout.1', 'session.layout.2',
	'session.layout.3', 'session.layout.4']!
const session_layout_titles = ['Floating', 'Columns', 'Rows', 'Grid', 'Main + stack']!
const session_key_center = '\x1b[110;9u'

struct ShellHub {
mut:
	notifications       sessioncore.Notifications
	clipboard           &sessioncore.Exchange = unsafe { nil }
	associations        sessioncore.Associations
	association_overrides sessioncore.Associations
	attached            bool
	available           bool
	initialized         bool
	polled_at           i64
	tab                 int
	page                int
	notice_actions      [64]string
	notice_open_actions [64]string
	clip_actions        [16]string
	service_actions     [32]string
	service_remove_actions [32]string
	service_names       [32]sessioncore.Text
	service_states      [32]sessioncore.Text
	service_enabled     [32]bool
	service_count       int
	service_import      bool
	service_status      sessioncore.Text
	banner_id           i64
	banner_until        i64
	seen_notice_id      i64
	history_loaded      bool
	show_alarms         bool
	alarm_actions       [64]string
	workspace_edit      bool
	workspace_name      sessioncore.Text
	policy              sessioncore.Policy
	shortcut_capture    sessioncore.Text
	shortcut_bytes      sessioncore.Text
	corner              int = -1
	corner_since        i64
	corner_fired        bool
	gesture             bool
	gesture_x           int
	gesture_y           int
	dialog              ShellDialog
	gesture_at          i64
	gesture_pid         int
	open_path           sessioncore.Text
	open_default        bool
	open_page           int
	open_actions        [64]string
	drop_path           sessioncore.Text
	drop_pid            int
	drop_active         bool
	file_press          sessioncore.Text
	file_press_window   int
	file_press_x        int
	file_press_y        int
	file_dragging       bool
	drop_released       bool
	drop_release_x      int
	drop_release_y      int
}

fn (mut d Desktop) initialize_shell_hub() {
	if d.hub.initialized { return }
	d.hub.initialized = true
	d.hub.clipboard = &sessioncore.Exchange{}
	for i in 0 .. d.hub.notice_actions.len { d.hub.notice_actions[i] = 'session.notice.${i}' }
	for i in 0 .. d.hub.notice_open_actions.len {
		d.hub.notice_open_actions[i] = 'session.notice.open.${i}'
	}
	for i in 0 .. d.hub.alarm_actions.len { d.hub.alarm_actions[i] = 'session.alarm.${i}' }
	for i in 0 .. d.hub.clip_actions.len { d.hub.clip_actions[i] = 'session.clip.${i}' }
	for i in 0 .. d.hub.service_actions.len { d.hub.service_actions[i] = 'session.service.${i}' }
	for i in 0 .. d.hub.service_remove_actions.len { d.hub.service_remove_actions[i] = 'session.service.remove.${i}' }
	for i in 0 .. d.hub.open_actions.len { d.hub.open_actions[i] = 'session.open.app.${i}' }
	d.hub.associations.set('text/plain', 'vinix-editor', false) or {}
	d.hub.associations.set('image/png', 'vinix-preview', false) or {}
	d.hub.associations.set('image/jpeg', 'vinix-preview', false) or {}
	d.hub.associations.set('application/pdf', 'vinix-preview', false) or {}
	d.hub.associations.set('text/calendar', 'vinix-calendar', false) or {}
	d.hub.associations.set('http', 'vinix-firefox', true) or {}
	d.hub.associations.set('https', 'vinix-firefox', true) or {}
	d.hub.associations.set('file', 'vinix-files', true) or {}
	d.load_associations()
}

fn (mut d Desktop) record_session_copy(text string, pid int, sensitive bool) {
	d.initialize_shell_hub()
	if !d.hub.policy.clipboard_apps { return }
	d.hub.clipboard.history_enabled = d.hub.policy.clipboard_history
	d.hub.clipboard.copy(C.getuid(), pid, .text, text, sensitive) or { return }
	_ = session_offer_data(.text, text, sensitive)
	d.dirty = true
}

fn (mut d Desktop) open_session_hub(tab int) {
	d.initialize_shell_hub()
	d.hub.tab = if tab >= 0 && tab < 5 { tab } else { 0 }
	d.hub.page = 0
	for window in d.windows {
		if window.page == .session {
			d.activate(window.id)
			return
		}
	}
	d.spawn('Desktop & Session', .session, 100, 60, 760, 510)
}

fn (mut d Desktop) poll_shell_services() {
	d.initialize_shell_hub()
	now := monotonic_millis()
	d.poll_hot_corner(now)
	if d.hub.banner_until > 0 && now >= d.hub.banner_until {
		d.hub.banner_until = 0
		d.dirty = true
	}
	if now - d.hub.polled_at < 1000 { return }
	d.hub.polled_at = now
	if d.hub.clipboard.current.sensitive && C.kill(d.hub.clipboard.current.owner_pid, 0) != 0 {
		d.hub.clipboard.revoke(d.hub.clipboard.current.owner_pid)
		d.clipboard.close_request()
		d.clipboard.local_bytes = [clipboard_max_bytes]u8{}
		d.clipboard.local_length = 0
		d.clipboard.local_available = false
		d.dirty = true
	}
	if !d.hub.attached {
		d.hub.attached = session_call_ok('attach', [])
		if !d.hub.attached {
			_ = session_start(d.home)
			return
		}
	}
	d.refresh_shell_policy()
	if d.hub.service_import {
		if path := session_dialog_take('linux-service') {
			d.hub.service_import = false
			defer { unsafe { path.free() } }
			if path.len == 0 {
				d.hub.service_status.set('Service import cancelled.') or {}
			} else {
				name := os.file_name(path)
				args := [name, path, '0']
				defer { unsafe { name.free(); (&array(&args)).free() } }
				if session_call_ok('service.import', args) {
					d.hub.service_status.set('Service installed. Select Start to run it.') or {}
				} else {
					d.hub.service_status.set('Service could not be installed. Check its directives and the session log.') or {}
				}
				d.refresh_service_status()
			}
			d.dirty = true
		}
	}
	history := session_call('history', []) or {
		d.hub.attached = false
		d.hub.available = false
		return
	}
	defer { unsafe { history.free() } }
	notifications := sessioncore.decode_notifications(history) or { return }
	d.hub.available = true
	if notifications != d.hub.notifications {
		d.hub.notifications = notifications
		epoch, _ := desktop_realtime()
		for i := notifications.count - 1; i >= 0; i-- {
			n := notifications.items[i]
			if n.id <= d.hub.seen_notice_id { break }
			if !d.hub.history_loaded && epoch - n.created > 15 { continue }
			if notifications.show_banner(n, epoch) {
				d.hub.banner_id = n.id
				d.hub.banner_until = now + 7000
				break
			}
		}
		d.hub.seen_notice_id = notifications.next_id - 1
		d.hub.history_loaded = true
		d.dirty = true
	}
	for _ in 0 .. 8 {
		queued := session_call('take', []) or { break }
		if queued == 'empty' {
			unsafe { queued.free() }
			break
		}
		f := sessioncore.fields(queued) or {
			unsafe { queued.free() }
			break
		}
		if f.count >= 3 && f.values[0] == 'action' {
			mut m := SessionMessage{ pid: int(sessioncore.number(f.values[1], 1, 2147483647) or { 0 }), count: f.count - 2 }
			for i in 2 .. f.count {
				m.fields[i - 2] = sessioncore.unfield(f.values[i]) or { sessioncore.Text{} }
			}
			d.perform_session_action(m)
		}
		unsafe { queued.free() }
	}
	if d.hub.tab == 3 {
		for w in d.windows {
			if w.page == .session && !w.minimized && w.workspace == d.current_workspace {
				d.refresh_service_status()
				break
			}
		}
	}
}

fn (mut d Desktop) refresh_service_status() {
	record := session_call('services', []) or { return }
	defer { unsafe { record.free() } }
	old_names := d.hub.service_names
	old_states := d.hub.service_states
	old_enabled := d.hub.service_enabled
	old_count := d.hub.service_count
	mut start := 0
	d.hub.service_count = 0
	for end in 0 .. record.len + 1 {
		if end < record.len && record[end] != `\n` { continue }
		if end == start {
			start = end + 1
			continue
		}
		f := sessioncore.fields(unsafe { tos(&record.str[start], end - start) }) or { break }
		start = end + 1
		if f.count != 8 || f.values[0] != 'service' { continue }
		i := int(sessioncore.number(f.values[1], 0, 31) or { continue })
		d.hub.service_names[i] = sessioncore.unfield(f.values[2]) or { continue }
		state := int(sessioncore.number(f.values[3], 0, 5) or { continue })
		title := match state {
			0 { 'Stopped' }
			1 { 'Starting' }
			2 { 'Running' }
			3 { 'Stopping' }
			4 { 'Restart pending' }
			else { 'Failed' }
		}
		d.hub.service_states[i].set(title) or {}
		d.hub.service_enabled[i] = f.values[6] == '1'
		if i + 1 > d.hub.service_count { d.hub.service_count = i + 1 }
	}
	if old_names != d.hub.service_names || old_states != d.hub.service_states || old_enabled != d.hub.service_enabled || old_count != d.hub.service_count {
		d.dirty = true
	}
}

fn (mut d Desktop) perform_session_action(m SessionMessage) {
	if m.count == 0 { return }
	action := m.fields[0].str()
	// External callers may show help or request a user-confirmed dialog.
	// Changes to another window or the session require recent focused input.
	if m.pid > 0 && action !in ['shell', 'notifications', 'services', 'help', 'dialog',
		'clipboard.offer', 'clipboard.request', 'settings', first_run_release_review_action] && !d.session_sender_has_gesture(m.pid) {
		return
	}
	match action {
		first_run_release_review_action {
			// The broker admits only this account. Recheck the fixed declaration;
			// callers cannot supply another path, package, approval or apply action.
			if first_run_release_review_requested(m, FirstRunReleaseRoute{}) or { unsafe { err.free() }; false } {
				d.open_first_run_release_review()
			}
		}
		'shell' { d.open_session_hub(0) }
		'notifications' { d.open_session_hub(1) }
		'clipboard' { d.open_session_hub(2) }
		'services' { d.open_session_hub(3) }
		'help' { d.open_session_hub(4) }
		'overview' { d.toggle_window_overview() }
		'show-desktop' { d.toggle_show_desktop() }
		'close' {
			if d.focus > 0 { d.close_window(d.focus) }
		}
		'minimize' { d.minimize(d.focus) }
		'settings' { d.perform_settings_action(m) }
		'dialog' { d.open_shell_dialog(m) }
		'clipboard.offer' { d.accept_session_offer(m.pid) }
		'clipboard.request' { d.grant_session_transfer(m.pid) }
		'drag.begin' { d.begin_session_drop(m) }
		'open.with' {
			if m.count == 2 { d.open_with(m.fields[1].str()) }
		}
		'associate' {
			if m.count == 4 && d.session_sender_has_gesture(m.pid) && shortcut_app_index_named(m.fields[2].str()) >= 0 {
				d.hub.associations.set(m.fields[1].str(), m.fields[2].str(), m.fields[3].str() == 'uri') or { return }
				d.hub.association_overrides.set(m.fields[1].str(), m.fields[2].str(), m.fields[3].str() == 'uri') or { return }
				d.save_associations()
			}
		}
		'workspace.count' {
			if m.count == 2 {
				_ = d.configure_workspaces(int(sessioncore.number(m.fields[1].str(), 1, 16) or { return }))
			}
		}
		'workspace.switch' {
			if m.count == 2 {
				d.switch_workspace(int(sessioncore.number(m.fields[1].str(), 0, d.workspace_total() - 1) or { return }))
			}
		}
		'workspace.rename' {
			if m.count == 3 {
				d.session.state.rename(int(sessioncore.number(m.fields[1].str(), 0, d.workspace_total() - 1) or { return }), m.fields[2].str()) or {}
				d.dirty = true
			}
		}
		'workspace.layout' {
			if m.count == 2 {
				d.arrange_workspace(unsafe { sessioncore.Layout(sessioncore.number(m.fields[1].str(), 0, 4) or { return }) })
			}
		}
		'focus' {
			if m.count == 3 {
				args := [m.fields[1].str(), m.fields[2].str()]
				_ = session_call_ok('quiet', args)
				unsafe { (&array(&args)).free() }
			}
		}
		'launch' {
			if m.count == 2 {
				index := shortcut_app_index_named(m.fields[1].str())
				if index >= 0 { d.launch_index(index) }
			}
		}
		'open' {
			if m.count >= 2 {
				d.open_associated_path(m.fields[1].str(), if m.count == 3 {
					m.fields[2].str()
				} else {
					''
				})
			}
		}
		'uri' {
			if m.count == 2 { d.open_session_uri(m.fields[1].str()) }
		}
		else {}
	}
}

fn (mut d Desktop) refresh_shell_policy() {
	record := session_call('policy', []) or { return }
	defer { unsafe { record.free() } }
	policy := sessioncore.decode_policy(record) or { return }
	if d.hub.policy == policy { return }
	if !policy.clipboard_history && d.hub.clipboard != unsafe { nil } {
		d.hub.clipboard.history = [sessioncore.clipboard_history_limit]sessioncore.Clip{}
		d.hub.clipboard.count = 0
	}
	if !policy.clipboard_apps {
		d.hub.clipboard.clear()
		d.clipboard.close_request()
		d.clipboard.local_bytes = [clipboard_max_bytes]u8{}
		d.clipboard.local_length = 0
		d.clipboard.local_available = false
	}
	if !policy.allow_capture { d.capture_close() }
	d.hub.policy = policy
	d.tz_offset_seconds = policy.timezone_minutes * 60
	d.taskbar_clock_sampled = false
	d.dirty = true
}

fn (mut d Desktop) perform_settings_action(m SessionMessage) {
	// An app cannot impersonate Settings in a request body. Match the sender
	// against the process the compositor itself launched from the catalog.
	mut trusted := false
	for window in d.windows {
		if window.factory_index < 0 || window.factory_index >= available_apps.len || available_apps[window.factory_index].process_name != 'vinix-settings' || window.app_index < 0 || window.app_index >= d.apps.len {
			continue
		}
		app := d.apps[window.app_index]
		if app is RemoteApp {
			if app.pid == m.pid && !app.closed {
				trusted = true
				break
			}
		}
	}
	if !trusted || m.count < 2 { return }
	action := m.fields[1].str()
	value := if m.count > 2 { m.fields[2].str() } else { '' }
	match action {
		'session.shell' { d.open_session_hub(0) }
		'session.startup' {
			index := shortcut_app_index_named('vinix-activity')
			if index >= 0 { d.launch_index(index) }
		}
		'session.logs' {
			path := '${d.home}/.vinix-service-logs'
			d.open_associated_path(path, 'vinix-files')
			unsafe { path.free() }
		}
		'privacy.clear' {
			d.clear_session_clipboard()
		}
		'users.home' { d.open_associated_path(desktop_user_home, 'vinix-files') }
		'users.password' {
			id := d.launch_index_window(shortcut_app_index_named('vinix-terminal'))
			if wi := d.window_index(id) {
				ai := d.windows[wi].app_index
				if ai >= 0 && ai < d.apps.len {
					mut app := d.apps[ai]
					if mut app is KeyboardApp {
						mut keyboard := KeyboardApp(app)
						keyboard.key_input('/usr/bin/passwd\r')
					}
				}
			}
		}
		'storage.disks' {
			index := shortcut_app_index_named('vinix-disk-utility')
			if index >= 0 { d.launch_index(index) }
		}
		'storage.usage' {
			index := shortcut_app_index_named('vinix-disk-usage')
			if index >= 0 { d.launch_index(index) }
		}
		'storage.mounts' { d.open_associated_path('/proc/mounts', 'vinix-editor') }
		else {
			if action.starts_with('accessibility.') {
				percent := int(sessioncore.number(action['accessibility.'.len..], 100, 200) or { return })
				if percent in [100, 200] { desktop_request_scale(percent / 100) }
			} else if action == 'shortcut.reset' {
				args := [action,value]
				_ = session_call_ok('settings.set',args)
				unsafe { (&array(&args)).free() }
				d.refresh_shell_policy()
			} else if action.starts_with('shortcut.') {
				d.hub.shortcut_capture.set(action['shortcut.'.len..]) or {}
				d.hub.shortcut_bytes = sessioncore.Text{}
				d.open_session_hub(4)
			} else {
				args := [action, value]
				_ = session_call_ok('settings.set', args)
				unsafe { (&array(&args)).free() }
				d.refresh_shell_policy()
			}
		}
	}
	d.dirty = true
}

fn (d &Desktop) session_shortcut_prefix(input string, at int) bool {
	if match_at(input, at, session_key_center) == seq_partial { return true }
	for i in 0 .. d.hub.policy.count {
		if match_at(input, at, d.hub.policy.bindings[i].key.str()) == seq_partial { return true }
	}
	return false
}

fn (d &Desktop) session_shortcut_sequence(input string) bool {
	if input == session_key_center { return true }
	for i in 0 .. d.hub.policy.count {
		if input == d.hub.policy.bindings[i].key.str() { return true }
	}
	return false
}

fn (mut d Desktop) take_session_chord(input string, at int) int {
	for i in 0 .. d.hub.policy.count {
		b := d.hub.policy.bindings[i]
		matched := match_at(input, at, b.key.str())
		if matched > seq_none {
			mut m := SessionMessage{ count: 1 }
			m.fields[0] = b.action
			d.perform_session_action(m)
			return matched
		}
	}
	matched := match_at(input, at, session_key_center)
	if matched > seq_none && !d.session_binding_exists('shell') {
		d.open_session_hub(0)
		return matched
	}
	return 0
}

fn (d &Desktop) session_binding_exists(action string) bool {
	for i in 0 .. d.hub.policy.count {
		if d.hub.policy.bindings[i].action.str() == action { return true }
	}
	return false
}

fn (mut d Desktop) capture_session_shortcut(input string) bool {
	if d.hub.shortcut_capture.len == 0 { return false }
	if input == '\x1b' {
		d.hub.shortcut_capture = sessioncore.Text{}
		d.hub.shortcut_bytes = sessioncore.Text{}
		d.dirty = true
		return true
	}
	if input.len == 0 { return true }
	for byte in input {
		if d.hub.shortcut_bytes.len == 32 {
			d.hub.shortcut_bytes = sessioncore.Text{}
			break
		}
		d.hub.shortcut_bytes.bytes[d.hub.shortcut_bytes.len] = byte
		d.hub.shortcut_bytes.len++
	}
	key := d.hub.shortcut_bytes.str()
	if key.len < 3 || key[0] != 27 || (key[key.len - 1] != `u` && key[key.len - 1] !in [
		`A`,
		`B`,
		`C`,
		`D`,
		`~`,
	]) {
		return true
	}
	args := ['shortcut.bind', key, d.hub.shortcut_capture.str()]
	if session_call_ok('settings.set', args) {
		d.hub.shortcut_capture = sessioncore.Text{}
		d.refresh_shell_policy()
	}
	unsafe { (&array(&args)).free() }
	d.hub.shortcut_bytes = sessioncore.Text{}
	d.dirty = true
	return true
}

fn (mut d Desktop) session_workspace_keys(input string) bool {
	if !d.hub.workspace_edit { return false }
	for w in d.windows {
		if w.id == d.focus && w.page == .session {
			for byte in input {
				if byte == 27 {
					d.hub.workspace_edit = false
					break
				}
				if byte in [u8(10), 13] {
					d.session.state.rename(d.current_workspace, d.hub.workspace_name.str()) or {}
					d.hub.workspace_edit = false
					break
				}
				if byte == 8 || byte == 127 {
					if d.hub.workspace_name.len > 0 {
						d.hub.workspace_name.len--
						d.hub.workspace_name.bytes[d.hub.workspace_name.len] = 0
					}
				} else if byte >= 32 && byte < 127 && d.hub.workspace_name.len < 48 {
					d.hub.workspace_name.bytes[d.hub.workspace_name.len] = byte
					d.hub.workspace_name.len++
					d.hub.workspace_name.bytes[d.hub.workspace_name.len] = 0
				}
			}
			d.dirty = true
			return true
		}
	}
	return false
}

fn (mut d Desktop) poll_hot_corner(now i64) {
	if d.buttons != 0 || d.drag.kind != .none_ || !d.pointer_present {
		d.hub.corner = -1
		return
	}
	mut corner := -1
	if d.pointer_x <= 2 && d.pointer_y <= 2 {
		corner = 0
	} else if d.pointer_x >= d.canvas.width - 3 && d.pointer_y <= 2 {
		corner = 1
	} else if d.pointer_x <= 2 && d.pointer_y >= d.canvas.height - 3 {
		corner = 2
	} else if d.pointer_x >= d.canvas.width - 3 && d.pointer_y >= d.canvas.height - 3 {
		corner = 3
	}
	if corner != d.hub.corner {
		d.hub.corner = corner
		d.hub.corner_since = now
		d.hub.corner_fired = false
	}
	if corner < 0 || d.hub.corner_fired || now - d.hub.corner_since < 600 { return }
	d.hub.corner_fired = true
	if d.hub.policy.corners[corner].len > 0 {
		mut m := SessionMessage{ count: 1 }
		m.fields[0] = d.hub.policy.corners[corner]
		d.perform_session_action(m)
	}
}

fn (mut d Desktop) session_gesture(packet PointerPacket, x int, y int) bool {
	if !d.hub.policy.gestures { return false }
	if packet.pressed & button_middle != 0 {
		d.hub.gesture = true
		d.hub.gesture_x = x
		d.hub.gesture_y = y
		return true
	}
	if !d.hub.gesture { return false }
	if packet.released & button_middle != 0 {
		d.hub.gesture = false
		dx := x - d.hub.gesture_x
		dy := y - d.hub.gesture_y
		if dx > 120 {
			d.switch_workspace((d.current_workspace + 1) % d.workspace_total())
		} else if dx < -120 {
			d.switch_workspace((d.current_workspace + d.workspace_total() - 1) % d.workspace_total())
		} else if dy < -100 {
			d.open_window_overview()
		} else {
			d.on_app_pointer_button(x, y, .down, .middle)
			d.on_app_pointer_button(x, y, .up, .middle)
		}
	}
	return true
}

fn (mut d Desktop) open_associated_path(path string, selected_app string) {
	if path.len == 0 || path.contains('\x00') || !path.starts_with('/') { return }
	name := if selected_app.len > 0 {
		selected_app
	} else {
		d.session_document_app(path, d.hub.associations.resolve(sessioncore.mime_for_path(path), false) or { 'vinix-files' })
	}
	d.open_document_in_handler(name, path)
}

fn (mut d Desktop) open_session_uri(uri string) {
	colon := uri.index(':') or { return }
	if !sessioncore.uri_scheme(uri[..colon]) { return }
	name := d.hub.associations.resolve(uri[..colon], true) or { return }
	if uri.starts_with('file:') {
		path := session_file_uri_path(uri) or { return }
		defer { unsafe { path.free() } }
		d.open_associated_path(path, '')
		return
	}
	index := shortcut_app_index_named(name)
	if index >= 0 { d.open_path_in_app(index, uri) }
}

fn session_file_uri_path(uri string) ?string {
	start := if uri.starts_with('file:///') { 7 } else if uri.starts_with('file://localhost/') {
		16
	} else if uri.starts_with('file:/') && !uri.starts_with('file://') { 5 } else { return none }
	mut end := uri.len
	for i in start .. uri.len {
		if uri[i] in [`?`, `#`] { end = i; break }
	}
	path := urllib.path_unescape(uri[start..end]) or { return none }
	if !path.starts_with('/') || path.contains('\x00') {
		unsafe { path.free() }
		return none
	}
	return path
}

fn (mut d Desktop) handle_session_hub_action(action string) bool {
	if !action.starts_with('session.') { return false }
	if action == 'session.open.default' {
		d.hub.open_default = !d.hub.open_default
		d.dirty = true
		return true
	}
	if action == 'session.openwith.context' {
		path := create_context_menu.item_path.clone()
		d.close_create_context_menu()
		d.open_with(path)
		unsafe { path.free() }
		return true
	}
	if action.starts_with('session.open.app.') {
		d.select_open_with(int(sessioncore.number(action['session.open.app.'.len..], 0, available_apps.len - 1) or { return true }))
		return true
	}
	if action.starts_with('session.open.package.') {
		d.select_package_open_with(unsafe { tos(action.str + 'session.open.package.'.len, action.len - 'session.open.package.'.len) })
		return true
	}
	if action == 'session.open.previous' || action == 'session.open.next' {
		count := d.open_with_count()
		pages := (count + 4) / 5
		if action == 'session.open.previous' && d.hub.open_page > 0 { d.hub.open_page-- }
		if action == 'session.open.next' && d.hub.open_page + 1 < pages { d.hub.open_page++ }
		d.dirty = true
		return true
	}
	if action == 'session.center' {
		d.open_session_hub(1)
		return true
	}
	if action == 'session.workspace.rename' {
		d.hub.workspace_name = d.session.state.workspaces[d.current_workspace].name
		d.hub.workspace_edit = true
		d.dirty = true
		return true
	}
	if action == 'session.alarms' {
		d.hub.show_alarms = !d.hub.show_alarms
		d.hub.page = 0
		d.dirty = true
		return true
	}
	if action.starts_with('session.alarm.') {
		index := action['session.alarm.'.len..]
		args := [index]
		_ = session_call_ok('alarm.remove', args)
		unsafe { (&array(&args)).free() }
		d.hub.polled_at = 0
		return true
	}
	if action.starts_with('session.tab.') {
		d.hub.tab = action['session.tab.'.len..].int()
		d.hub.page = 0
		d.dirty = true
		return true
	}
	if action == 'session.previous' {
		if d.hub.page > 0 { d.hub.page-- }
		d.dirty = true
		return true
	}
	if action == 'session.next' {
		if d.hub.page < 7 { d.hub.page++ }
		d.dirty = true
		return true
	}
	if action.starts_with('session.layout.') {
		d.arrange_workspace(unsafe { sessioncore.Layout(action['session.layout.'.len..].int()) })
		return true
	}
	if action == 'session.workspace.previous' {
		d.switch_workspace(if d.current_workspace < 4 {
			d.workspace_total() - 1
		} else {
			(d.current_workspace / 4) * 4 - 1
		})
		return true
	}
	if action == 'session.workspace.next' {
		next := (d.current_workspace / 4 + 1) * 4
		d.switch_workspace(if next >= d.workspace_total() { 0 } else { next })
		return true
	}
	if action == 'session.workspaces.less' {
		_ = d.configure_workspaces(d.workspace_total() - 1)
		return true
	}
	if action == 'session.workspaces.more' {
		_ = d.configure_workspaces(d.workspace_total() + 1)
		return true
	}
	if action == 'session.display.return' {
		d.session.state.return_to_display = !d.session.state.return_to_display
		d.save_shell_session(true)
		d.dirty = true
		return true
	}
	if action == 'session.restore.toggle' {
		d.session.state.restore_session = !d.session.state.restore_session
		d.dirty = true
		return true
	}
	if action == 'session.group' {
		group := d.current_workspace + 1
		for i in 0 .. d.windows.len {
			if d.windows[i].workspace == d.current_workspace && d.windows[i].page != .session {
				d.windows[i].group = if d.windows[i].group == group { 0 } else { group }
			}
		}
		d.dirty = true
		return true
	}
	if action.starts_with('session.mode.') {
		mode := action['session.mode.'.len..]
		args := [mode, if mode == '2' { '3600' } else { '0' }]
		_ = session_call_ok('quiet', args)
		unsafe { (&array(&args)).free() }
		d.hub.polled_at = 0
		return true
	}
	if action.starts_with('session.notice.open.') {
		i := action['session.notice.open.'.len..].int()
		if i >= 0 && i < d.hub.notifications.count {
			target := d.hub.notifications.items[i].action.str()
			if target.starts_with('launch:') {
				index := shortcut_app_index_named(target['launch:'.len..])
				if index >= 0 { d.launch_index(index) }
			} else if target.starts_with('uri:') {
				d.open_session_uri(target['uri:'.len..])
			} else if target.starts_with('open:') {
				d.open_associated_path(target['open:'.len..], '')
			}
		}
		return true
	}
	if action.starts_with('session.notice.') {
		i := action['session.notice.'.len..].int()
		if i >= 0 && i < d.hub.notifications.count {
			id := d.hub.notifications.items[i].id.str()
			args := [id]
			_ = session_call_ok('dismiss', args)
			unsafe {
				(&array(&args)).free()
				id.free()
			}
			d.hub.polled_at = 0
		}
		return true
	}
	if action == 'session.clip.clear' {
		d.clear_session_clipboard()
		return true
	}
	if action.starts_with('session.clip.') {
		i := action['session.clip.'.len..].int()
		d.hub.clipboard.select_history(i, C.getuid()) or { return true }
		_ = session_offer_data(d.hub.clipboard.current.kind, d.hub.clipboard.current.data(), false)
		if d.hub.clipboard.current.kind == .text {
			_ = d.clipboard.set_local_text(d.hub.clipboard.current.data())
		}
		d.dirty = true
		return true
	}
	if action == 'session.service.import' {
		if !d.hub.service_import {
			d.hub.service_import = session_dialog_open('linux-service', 0, 'Import a Linux service unit', d.home, '', 'application/x-systemd-unit')
			if !d.hub.service_import { d.hub.service_status.set('Service file chooser unavailable.') or {} }
		}
		d.dirty = true
		return true
	}
	if action.starts_with('session.service.remove.') {
		i := action['session.service.remove.'.len..].int()
		if i >= 0 && i < d.hub.service_count {
			args := [d.hub.service_names[i].str()]
			if session_call_ok('service.remove', args) {
				d.hub.service_status.set('Service removed.') or {}
			} else {
				d.hub.service_status.set('Stop the service and its dependents before removing it.') or {}
			}
			unsafe { (&array(&args)).free() }
			d.refresh_service_status()
			d.dirty = true
		}
		return true
	}
	if action.starts_with('session.service.') {
		i := action['session.service.'.len..].int()
		if i >= 0 && i < d.hub.service_count {
			index := i.str()
			args := [index, if d.hub.service_enabled[i] { '0' } else { '1' }]
			_ = session_call_ok('service.enable', args)
			unsafe {
				(&array(&args)).free()
				index.free()
			}
			d.refresh_service_status()
		}
		return true
	}
	return false
}

fn (d &Desktop) session_hub_contents(width int, height int) []ui2.Element {
	mut out := frame_elements(32)
	inner := width - 32
	for i, title in session_hub_tabs {
		out << settings_choice(session_hub_tab_ids[i], title, 16 + i * (inner / 5), 12, inner / 5 - 4, d.hub.tab == i)
	}
	mut y := 58
	match d.hub.tab {
		0 {
			out << owned_body_line('${d.workspace_total()} workspaces. Current: ${d.current_workspace + 1}', 16, y, inner)
			y += 30
			out << settings_choice('session.workspaces.less', 'Remove last workspace', 16, y, 210, false)
			out << settings_choice('session.workspaces.more', 'Add workspace', 234, y, 180, false)
			y += 44
			out << body_line('Arrange every window on this workspace:', 16, y, inner)
			y += 28
			for i, title in session_layout_titles {
				out << settings_choice(session_layout_ids[i], title, 16 + i * (inner / 5), y, inner / 5 - 4, int(d.session.state.workspaces[d.current_workspace].layout) == i)
			}
			y += 46
			out << settings_choice('session.group', 'Group / ungroup workspace apps', 16, y, 290, false)
			y += 44
			out << settings_choice('session.restore.toggle', 'Restore windows on login', 16, y, 290, d.session.state.restore_session)
			out << settings_choice('session.display.return', 'Return apps to reconnected display', 320, y, inner - 304, d.session.state.return_to_display)
			y += 44
			out << body_line('Grouped windows move together between workspaces.', 16, y, inner)
			y += 24
			out << settings_choice('session.workspace.rename', if d.hub.workspace_edit {
				d.hub.workspace_name.str()
			} else {
				'Rename current workspace'
			}, 16, y, 290, false)
			y += 38
			out << body_line(d.session.state.workspaces[d.current_workspace].name.str(), 16, y, inner)
			y += 24
			out << body_line('Super+1..4 switches; Super+Shift+1..4 moves a group.', 16, y, inner)
		}
		1 {
			out << body_line(if d.hub.available {
				'Notification history and focus'
			} else {
				'Session services unavailable'
			}, 16, y, inner)
			y += 28
			for i, title in ['Normal', 'Quiet', 'Focus for one hour']! {
				id := match i {
					0 { 'session.mode.0' }
					1 { 'session.mode.1' }
					else { 'session.mode.2' }
				}
				out << settings_choice(id, title, 16 + i * (inner / 3), y, inner / 3 - 6, int(d.hub.notifications.mode) == i)
			}
			y += 42
			for slot in 0 .. 8 {
				i := d.hub.notifications.count - 1 - d.hub.page * 8 - slot
				if d.hub.show_alarms {
					ai := d.hub.page * 8 + slot
					if ai >= d.hub.notifications.alarm_count { break }
					alarm := d.hub.notifications.alarms[ai]
					out << body_line(alarm.title.str(), 16, y, inner - 110)
					out << settings_choice(d.hub.alarm_actions[ai], if alarm.active {
						'Cancel'
					} else {
						'Finished'
					}, width - 116, y, 100, !alarm.active)
					y += 36
					continue
				}
				if i < 0 { break }
				n := d.hub.notifications.items[i]
				out << body_line(n.title.str(), 16, y, inner - 220)
				out << muted_line(n.body.str(), 16, y + 18, inner - 220)
				if n.progress >= 0 {
					out << owned_body_line('${n.progress}%', width - 270, y + 18, 50)
				}
				if n.action.str().starts_with('launch:') || n.action.str().starts_with('uri:') || n.action.str().starts_with('open:') {
					out << settings_choice(d.hub.notice_open_actions[i], 'Open', width - 216, y, 94, false)
				}
				out << settings_choice(d.hub.notice_actions[i], if n.dismissed {
					'Dismissed'
				} else {
					'Dismiss'
				}, width - 116, y, 100, n.dismissed)
				y += 42
			}
		}
		2 {
			out << body_line('Clipboard history stays in this session.', 16, y, inner)
			y += 30
			out << settings_choice('session.clip.clear', 'Clear clipboard & history', 16, y, 250, false)
			y += 44
			if d.hub.clipboard != unsafe { nil } {
				for slot in 0 .. 8 {
					i := d.hub.page * 8 + slot
					if i >= d.hub.clipboard.count { break }
					clip := &d.hub.clipboard.history[i]
					out << settings_choice(d.hub.clip_actions[i], clip.kind.mime(), 16, y, 180, false)
					if clip.kind in [.text, .html, .uri_list] {
						out << muted_line(unsafe {
							tos(&clip.bytes[0], if clip.len > 72 {
								72
							} else {
								clip.len
							})
						}, 208, y + 6, inner - 192)
					}
					y += 36
				}
			}
		}
		3 {
			out << body_line('Services start after their dependencies and stop before them.', 16, y, inner)
			y += 26
			out << settings_choice('session.service.import', 'Import Linux service…', 16, y, 210, false)
			out << muted_line(d.hub.service_status.str(), 238, y + 6, inner - 222)
			y += 38
			if d.hub.service_count == 0 {
				out << body_line('No configured services.', 16, y, inner)
			}
			for slot in 0 .. 8 {
				i := d.hub.page * 8 + slot
				if i >= d.hub.service_count { break }
				out << body_line(d.hub.service_names[i].str(), 16, y, inner - 360)
				out << muted_line(d.hub.service_states[i].str(), width - 350, y, 110)
				out << settings_choice(d.hub.service_remove_actions[i], 'Remove', width - 236, y - 4, 98, false)
				out << settings_choice(d.hub.service_actions[i], if d.hub.service_enabled[i] {
					'Stop'
				} else {
					'Start'
				}, width - 130, y - 4, 110, false)
				y += 36
			}
		}
		else {
			if d.hub.shortcut_capture.len > 0 {
				out << body_line('Press a modified shortcut; Escape cancels.', 16, y, inner)
				y += 30
			}
			for line in ['Super+N: Desktop & Session',
				'Ctrl+Super+Up: overview; Super+Z: window layouts',
				'Super+arrows: tile or restore; Alt+Space: window actions',
				'Ctrl+V: paste; Ctrl+Shift+V: host clipboard',
				'Workspaces and window positions are saved in your profile.',
				'Clock timers continue after Clock closes.',
				'Focus keeps notices in history; critical alarms may still appear.',
				'Service logs are under .vinix-service-logs in your profile.',
				'Settings reports devices and services this machine supports.']! {
				out << body_line(line, 16, y, inner)
				y += 28
			}
		}
	}
	if d.hub.tab in [1, 2, 3] {
		if d.hub.tab == 1 {
			out << settings_choice('session.alarms', if d.hub.show_alarms {
				'History'
			} else {
				'Alarms'
			}, width - 126, height - 40, 110, false)
		}
		out << settings_choice('session.previous', 'Previous', 16, height - 40, 110, false)
		out << settings_choice('session.next', 'Next', 134, height - 40, 110, false)
	}
	return out
}

fn (d &Desktop) session_banner() ?ui2.Element {
	if d.hub.banner_until == 0 { return none }
	for i in 0 .. d.hub.notifications.count {
		n := d.hub.notifications.items[i]
		if n.id != d.hub.banner_id || n.dismissed { continue }
		width := if d.canvas.width < 380 { d.canvas.width - 24 } else { 356 }
		mut children := frame_elements(2)
		children << body_line(n.title.str(), 12, 10, width - 24)
		children << muted_line(n.body.str(), 12, 32, width - 24)
		return ui2.clickable_view('session.center', ui2.rect(f64(d.canvas.width - width - 12), 12, f64(width), 66), ui2.BoxStyle{ bg: app_surface, radius: 8 }, children)
	}
	return none
}
