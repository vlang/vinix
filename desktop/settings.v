// SPDX-License-Identifier: GPL-2.0-or-later
// Settings is a hosted desktop application. Opening/repainting it only reads
// the device; a brightness write requires an explicit, enabled user action.
module main

import ui2

#flag -I @VMODROOT
#include "backlight_client.h"

@[typedef]
struct C.VdBlState {
mut:
	requested_nits int
	actual_nits    int
	min_nits       int
	max_nits       int
	pending        int
	online         int
	writable       int
}

fn C.vd_bl_read_state(state &C.VdBlState) int
fn C.vd_bl_set_percent(percent int) int
fn C.vd_bl_percent(state &C.VdBlState) int
fn C.vd_bl_now_ms() u64

// These values belong to backlight_client.h's private result enum, not errno.
const settings_bl_ok = 0
const settings_bl_unavailable = 1
const settings_bl_permission = 2
const settings_bl_offline = 3
const settings_bl_invalid = 4

// Static ids/labels: the framebuffer renderer frees child arrays, not strings.
const settings_brightness_actions = [
	'settings.brightness.0', 'settings.brightness.5', 'settings.brightness.10',
	'settings.brightness.15', 'settings.brightness.20', 'settings.brightness.25',
	'settings.brightness.30', 'settings.brightness.35', 'settings.brightness.40',
	'settings.brightness.45', 'settings.brightness.50', 'settings.brightness.55',
	'settings.brightness.60', 'settings.brightness.65', 'settings.brightness.70',
	'settings.brightness.75', 'settings.brightness.80', 'settings.brightness.85',
	'settings.brightness.90', 'settings.brightness.95', 'settings.brightness.100',
]
const settings_brightness_labels = [
	'0%', '5%', '10%', '15%', '20%', '25%', '30%', '35%', '40%', '45%', '50%',
	'55%', '60%', '65%', '70%', '75%', '80%', '85%', '90%', '95%', '100%',
]

fn settings_read_state(state &C.VdBlState) int {
	return C.vd_bl_read_state(state)
}

fn settings_write_percent(percent int) int {
	return C.vd_bl_set_percent(percent)
}

struct SettingsApp {
mut:
	state        C.VdBlState
	read_result  int = settings_bl_unavailable
	write_result int
	last_poll_ms u64
	initialized  bool
	// Injectable for host tests; production always uses the fixed device path.
	read_state   fn (&C.VdBlState) int = settings_read_state
	write_percent fn (int) int = settings_write_percent
	// Owned, cached labels. Replace only when readback changes, never per frame.
	level_text     string
	requested_text string
	actual_text    string
	range_text     string
}

fn open_settings() !HostedApp {
	mut app := &SettingsApp{}
	app.refresh()
	// An absent device is a normal, visible state, not a failure to open Settings.
	return app
}

fn settings_same_state(a &C.VdBlState, b &C.VdBlState) bool {
	return a.requested_nits == b.requested_nits && a.actual_nits == b.actual_nits
		&& a.min_nits == b.min_nits && a.max_nits == b.max_nits && a.pending == b.pending
		&& a.online == b.online && a.writable == b.writable
}

fn (mut a SettingsApp) refresh() {
	mut next := C.VdBlState{}
	result := a.read_state(&next)
	a.last_poll_ms = C.vd_bl_now_ms()
	if a.initialized && result == a.read_result && settings_same_state(&a.state, &next) {
		return
	}
	if a.initialized {
		unsafe {
			a.level_text.free()
			a.requested_text.free()
			a.actual_text.free()
			a.range_text.free()
		}
	}
	a.initialized = true
	a.state = next
	a.read_result = result
	if result != settings_bl_ok {
		a.level_text = 'Unavailable'.clone()
		a.requested_text = 'Requested: unknown'.clone()
		a.actual_text = 'Actual: unknown'.clone()
		a.range_text = 'Panel brightness range is unavailable.'.clone()
		return
	}
	percent := C.vd_bl_percent(&a.state)
	a.level_text = if percent >= 0 { '${percent}%' } else { 'Unknown'.clone() }
	a.requested_text = if next.requested_nits >= 0 {
		'Requested: ${next.requested_nits} nits'
	} else {
		'Requested: unchanged since boot'.clone()
	}
	a.actual_text = if next.actual_nits >= 0 {
		'Actual: ${next.actual_nits} nits (driver report)'
	} else {
		'Actual: waiting for a driver report'.clone()
	}
	a.range_text = '${next.min_nits} - ${next.max_nits} nits; 0% keeps the display on.'
}

fn (a &SettingsApp) can_change() bool {
	return a.read_result == settings_bl_ok && a.state.online != 0 && a.state.writable != 0
}

fn settings_error_text(result int) string {
	return match result {
		settings_bl_unavailable { 'Brightness driver not available.' }
		settings_bl_permission { 'Permission denied. Brightness control requires write access.' }
		settings_bl_offline { 'Display brightness device is offline.' }
		settings_bl_invalid { 'Invalid brightness response.' }
		else { 'Brightness I/O failed. Refresh to try again.' }
	}
}

fn (a &SettingsApp) status_text() string {
	if a.read_result != settings_bl_ok {
		return settings_error_text(a.read_result)
	}
	if a.write_result != settings_bl_ok {
		return settings_error_text(a.write_result)
	}
	if a.state.online == 0 {
		return settings_error_text(settings_bl_offline)
	}
	if a.state.writable == 0 {
		return 'Read-only access; brightness controls are disabled.'
	}
	if a.state.pending != 0 {
		return 'Brightness request pending in the display driver.'
	}
	return 'Brightness read from /dev/apple-panel-bl.'
}

fn settings_button(id string, text string, frame ui2.Rect, enabled bool) ui2.Element {
	return ui2.Element{
		kind: .button
		id: id
		text: text
		frame: frame
		enabled: enabled
		box: ui2.BoxStyle{
			bg: if enabled { files_up } else { files_up_disabled }
			radius: 5
		}
		text_style: ui2.TextStyle{
			color: if enabled { taskbar_text_active } else { body_muted }
			size: 13
			align: .center
		}
	}
}

fn settings_label(text string, x int, y int, width int, color u32) ui2.Element {
	return ui2.label('', text, ui2.rect(f64(x), f64(y), f64(width), 22), ui2.TextStyle{
		color: color
		size: 13
	})
}

fn (mut a SettingsApp) build(size ui2.Rect) !ui2.Element {
	// The desktop already redraws for its clock once a second. Poll at most
	// that often, including pending changes made by another Settings window.
	now := C.vd_bl_now_ms()
	if !a.initialized || (now != 0 && (now < a.last_poll_ms || now - a.last_poll_ms >= 1000)) {
		a.refresh()
	}
	width := int(size.width)
	height := int(size.height)
	if width < 460 || height < 338 {
		return ui2.screen(window_body, [
			settings_label('Enlarge Settings to show Display controls.', 12, 12, width - 24, body_text),
		])
	}
	x := 136
	inner := width - x - 18
	active := a.can_change()
	percent := if a.read_result == settings_bl_ok { C.vd_bl_percent(&a.state) } else { -1 }
	mut children := [
		ui2.view('', ui2.rect(0, 0, 118, f64(height)), ui2.BoxStyle{bg: body_panel}, []),
		settings_label('Categories', 12, 14, 100, body_muted),
		settings_button('settings.display', 'Display', ui2.rect(10, 46, 98, 30), true),
		ui2.label('', 'Display', ui2.rect(f64(x), 16, f64(inner), 28), ui2.TextStyle{
			color: body_heading
			size: 20
			bold: true
		}),
		settings_label('Built-in display', x, 46, inner, body_muted),
		ui2.view('', ui2.rect(f64(x), 76, f64(inner), 1), ui2.BoxStyle{bg: body_rule}, []),
		settings_label('Brightness', x, 90, inner - 100, body_heading),
		settings_label(a.level_text, x + inner - 100, 90, 100, body_heading),
	]
	// A click-to-set stepped bar, not a pretend draggable slider: HostedApp
	// receives action ids, not pointer coordinates. Every step is 5%.
	for i, id in settings_brightness_actions {
		left := x + inner * i / settings_brightness_actions.len
		right := x + inner * (i + 1) / settings_brightness_actions.len
		children << ui2.Element{
			kind: .button
			id: id
			frame: ui2.rect(f64(left), 122, f64(right - left - 1), 28)
			enabled: active
			accessibility_label: settings_brightness_labels[i]
			box: ui2.BoxStyle{
				bg: if !active { files_up_disabled } else if percent >= i * 5 { accent } else { body_rule }
				radius: 3
			}
		}
	}
	children << settings_label(a.range_text, x, 160, inner, body_muted)
	children << settings_button('settings.decrease', '- 5%', ui2.rect(f64(x), 192, 62, 30),
		active && percent > 0)
	children << settings_button('settings.increase', '+ 5%', ui2.rect(f64(x + 70), 192, 62, 30),
		active && percent >= 0 && percent < 100)
	children << settings_button('settings.refresh', 'Refresh', ui2.rect(f64(x + inner - 80), 192, 80, 30), true)
	children << settings_label(a.requested_text, x, 236, inner, body_text)
	children << settings_label(a.actual_text, x, 258, inner, body_text)
	children << settings_label(a.status_text(), x, 290, inner,
		if a.read_result != 0 || a.write_result != 0 { files_error } else { body_muted })
	if a.read_result == settings_bl_unavailable {
		children << settings_label('DCP backend integration is still required.', x, 312, inner, body_muted)
	} else {
		children << settings_label('Click the bar to set brightness in 5% steps.', x, 312, inner, body_muted)
	}
	return ui2.screen(window_body, children)
}

fn (mut a SettingsApp) handle(event_id string) ! {
	if event_id == 'settings.refresh' || event_id == 'settings.display' {
		a.write_result = settings_bl_ok
		a.refresh()
		return
	}
	mut target := -1
	for i, id in settings_brightness_actions {
		if event_id == id {
			target = i * 5
			break
		}
	}
	step := event_id == 'settings.decrease' || event_id == 'settings.increase'
	if target < 0 && !step {
		return
	}
	// Defend even against stale hit targets: never write after the device has
	// disappeared, gone offline, or become read-only since the last frame.
	a.refresh()
	if !a.can_change() {
		return
	}
	if step {
		current := C.vd_bl_percent(&a.state)
		if current < 0 {
			return
		}
		target = current + if event_id == 'settings.increase' { 5 } else { -5 }
		if target < 0 { target = 0 }
		if target > 100 { target = 100 }
	}
	a.write_result = a.write_percent(target)
	// A successful write only queues work. Read actual/pending from the driver.
	a.refresh()
}
