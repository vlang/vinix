// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.sessioncore
import ui2

fn (c SettingsCategory) service_name() string {
	return match c {
		.sound { 'sound' }
		.bluetooth { 'bluetooth' }
		.printers { 'printers' }
		.users { 'users' }
		.network { 'network' }
		.privacy { 'privacy' }
		.storage { 'storage' }
		.updates { 'updates' }
		.accessibility { 'accessibility' }
		.clock { 'clock' }
		.session { 'session' }
		.shortcuts { 'shortcuts' }
		.gestures { 'gestures' }
		else { '' }
	}
}

fn (mut a SettingsApp) refresh_session_settings(force bool) bool {
	now := monotonic_millis()
	if !force && now - a.service_poll_ms < 1000 { return false }
	a.service_poll_ms = now
	args := [a.category.service_name()]
	record := session_call('settings.status', args) or {
		unsafe { (&array(&args)).free() }
		a.service_status = sessioncore.SettingsStatus{}
		a.service_status.line('Session services are unavailable.')
		return true
	}
	defer {
		unsafe {
			record.free()
			(&array(&args)).free()
		}
	}
	status := sessioncore.decode_settings_status(record) or { return false }
	changed := a.service_status != status
	a.service_status = status
	for i in 0 .. 8 {
		if a.service_actions[i].len == 0 { a.service_actions[i] = 'settings.session.control.${i}' }
	}
	return changed
}

fn (a &SettingsApp) session_settings_pane(width int, height int) []ui2.Element {
	mut out := frame_elements(24)
	inner := width - 32
	out << settings_heading(a.category.title(), 16, width)
	mut y := 46
	for i in 0 .. a.service_status.count {
		out << body_line(a.service_status.lines[i].str(), 16, y, inner)
		y += 24
	}
	for i in 0 .. a.service_status.control_count {
		c := a.service_status.controls[i]
		out << ui2.Element{ ...settings_toggle(a.service_actions[i], c.label.str(), 16 + (i % 2) * (inner / 2), y + (i / 2) * 36, inner / 2 - 6, c.checked), enabled: c.enabled }
	}
	if a.category in [.bluetooth, .printers, .users, .network, .clock] {
		field_y := height - 75
		out << ui2.clickable_view('settings.session.value', ui2.rect(16, f64(field_y), f64(inner), 30), ui2.BoxStyle{ bg: body_panel, radius: 5 }, [ui2.text_field('', 'Address, queue, account, interface or time', a.service_value.str(), ui2.rect(8, 0, f64(inner - 16), 30), ui2.BoxStyle{ transparent: true }, ui2.TextStyle{ color: body_text, size: 12 }, 0)])
	}
	out << settings_choice('settings.session.refresh', 'Refresh', 16, height - 38, 110, false)
	out << settings_choice('settings.session.logs', 'Operation logs', 134, height - 38, 140, false)
	return out
}

fn (mut a SettingsApp) handle_session_settings(event_id string) bool {
	if !event_id.starts_with('settings.session.') { return false }
	if event_id == 'settings.session.value' {
		a.service_edit = true
		return true
	}
	a.service_edit = false
	if event_id == 'settings.session.refresh' {
		a.refresh_session_settings(true)
		return true
	}
	mut operation := ''
	if event_id == 'settings.session.logs' { operation = 'session.logs' }
	for i in 0 .. a.service_status.control_count {
		if event_id == a.service_actions[i] && a.service_status.controls[i].enabled {
			operation = a.service_status.controls[i].action.str()
		}
	}
	if operation.len == 0 { return true }
	args := ['settings', operation, a.service_value.str()]
	_ = session_call_ok('action', args)
	unsafe { (&array(&args)).free() }
	a.service_poll_ms = 0
	return true
}

fn (mut a SettingsApp) session_settings_key(input string) bool {
	if !a.service_edit { return false }
	for byte in input {
		if byte == 27 || byte == 13 || byte == 10 {
			a.service_edit = false
			return true
		}
		if byte == 8 || byte == 127 {
			if a.service_value.len > 0 {
				a.service_value.len--
				a.service_value.bytes[a.service_value.len] = 0
			}
			continue
		}
		if byte >= 32 && byte < 127 && a.service_value.len < 128 {
			a.service_value.bytes[a.service_value.len] = byte
			a.service_value.len++
			a.service_value.bytes[a.service_value.len] = 0
		}
	}
	return true
}
