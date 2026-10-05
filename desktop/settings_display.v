// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// The two Settings categories that read a device rather than the desktop's own
// preferences: Display, which drives the panel backlight, and Battery, which
// only reports. They were a Settings application of their own before the two
// lines of work met; they are categories of the one application now, so the
// panes here are the same controls laid out relative to its pane rather than
// to the window.
//
// Opening or repainting either only reads. A brightness write happens on an
// explicit user action and nowhere else.
module main

import ui2

// Static ids/labels: the framebuffer renderer frees child arrays, not strings.
const settings_scale_100_action = 'settings.scale.100'
const settings_scale_200_action = 'settings.scale.200'
const settings_brightness_actions = [
	'settings.brightness.0',
	'settings.brightness.5',
	'settings.brightness.10',
	'settings.brightness.15',
	'settings.brightness.20',
	'settings.brightness.25',
	'settings.brightness.30',
	'settings.brightness.35',
	'settings.brightness.40',
	'settings.brightness.45',
	'settings.brightness.50',
	'settings.brightness.55',
	'settings.brightness.60',
	'settings.brightness.65',
	'settings.brightness.70',
	'settings.brightness.75',
	'settings.brightness.80',
	'settings.brightness.85',
	'settings.brightness.90',
	'settings.brightness.95',
	'settings.brightness.100',
]
const settings_brightness_labels = [
	'0%',
	'5%',
	'10%',
	'15%',
	'20%',
	'25%',
	'30%',
	'35%',
	'40%',
	'45%',
	'50%',
	'55%',
	'60%',
	'65%',
	'70%',
	'75%',
	'80%',
	'85%',
	'90%',
	'95%',
	'100%',
]

// Shared with battery.v, which draws its pane from the same two primitives.
fn settings_button(id string, text string, frame ui2.Rect, enabled bool) ui2.Element {
	return ui2.Element{
		kind: .button
		id: id
		text: text
		frame: frame
		enabled: enabled
		native_style: true
		box: ui2.BoxStyle{
			bg: if enabled { files_up } else { files_up_disabled }
			radius: 5
		}
		text_style: ui2.TextStyle{
			color: if enabled { app_on_accent } else { body_muted }
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

fn settings_scale_button(id string, text string, x int, selected bool) ui2.Element {
	return ui2.Element{
		kind:                .button
		id:                  id
		text:                text
		frame:               ui2.rect(f64(x), 40, 60, 30)
		box:                 ui2.BoxStyle{
			bg:     if selected { app_accent } else { files_up }
			radius: 5
		}
		text_style:          ui2.TextStyle{
			color: app_on_accent
			size: 13
			bold: selected
			align: .center
		}
		native_style:        true
		checked:             selected
		accessibility_role:  'radio'
		accessibility_label: text
		accessibility_value: if selected { tr('settings.choice.selected') } else { tr('settings.choice.not_selected') }
	}
}

// settings_fill_numbers is tr_fill3 for whole numbers: it puts a, b and c in
// the `{0}`, `{1}` and `{2}` of text, which tr looked up. Only the result stays
// allocated, and it belongs to the caller.
fn settings_fill_numbers(text string, a int, b int, c int) string {
	first := a.str()
	second := b.str()
	third := c.str()
	filled := tr_substitute(text, first, second, third)
	unsafe {
		first.free()
		second.free()
		third.free()
	}
	return filled
}

fn settings_same_state(a &BacklightState, b &BacklightState) bool {
	return a.requested_nits == b.requested_nits && a.actual_nits == b.actual_nits
		&& a.min_nits == b.min_nits && a.max_nits == b.max_nits && a.pending == b.pending
		&& a.online == b.online && a.writable == b.writable
}

fn (mut a SettingsApp) refresh() {
	mut next := BacklightState{}
	result := a.read_state(mut next)
	a.last_poll_ms = desktop_monotonic_ms()
	if a.initialized && result == a.read_result && settings_same_state(&a.state, &next)
		&& a.labels_language == desktop_language {
		return
	}
	a.replace_display_labels(result, next)
}

// replace_display_labels takes a readback and remakes the cached labels from
// it in the desktop's language, releasing the ones they replace.
fn (mut a SettingsApp) replace_display_labels(result BacklightResult, next BacklightState) {
	if a.initialized {
		unsafe {
			a.level_text.free()
			a.requested_text.free()
			a.actual_text.free()
			a.range_text.free()
		}
	}
	a.initialized = true
	a.labels_language = desktop_language
	a.state = next
	a.read_result = result
	if result != .ok {
		a.level_text = tr('settings.display.unavailable').clone()
		a.requested_text = tr('settings.display.requested_unknown').clone()
		a.actual_text = tr('settings.display.actual_unknown').clone()
		a.range_text = tr('settings.display.range_unavailable').clone()
		return
	}
	percent := backlight_percent(&a.state)
	a.level_text = if percent >= 0 {
		'${percent}%'
	} else {
		tr('settings.display.unknown').clone()
	}
	a.requested_text = if next.requested_nits >= 0 {
		settings_fill_numbers(tr('settings.display.requested_nits'), next.requested_nits,
			0, 0)
	} else {
		tr('settings.display.requested_unchanged').clone()
	}
	a.actual_text = if next.actual_nits >= 0 {
		settings_fill_numbers(tr('settings.display.actual_nits'), next.actual_nits, 0, 0)
	} else {
		tr('settings.display.actual_waiting').clone()
	}
	a.range_text = settings_fill_numbers(tr('settings.display.range'), next.min_nits, next.max_nits,
		0)
}

// follow_display_language remakes the cached labels when the language has
// changed since they were made. The pane draws through an immutable receiver,
// and build polls the panel only once a second, so without this a language
// chosen elsewhere would leave these labels in the old one until the next
// readback. It changes nothing but this application's own label cache.
fn (a &SettingsApp) follow_display_language() {
	if !a.initialized || a.labels_language == desktop_language {
		return
	}
	mut app := unsafe { &SettingsApp(a) }
	app.replace_display_labels(a.read_result, a.state)
}

fn (a &SettingsApp) can_change() bool {
	return a.read_result == BacklightResult.ok && a.state.online && a.state.writable
}

fn settings_error_text(result BacklightResult) string {
	return match result {
		.unavailable { tr('settings.display.error.unavailable') }
		.permission { tr('settings.display.error.permission') }
		.offline { tr('settings.display.error.offline') }
		.invalid { tr('settings.display.error.invalid') }
		else { tr('settings.display.error.io') }
	}
}

fn (a &SettingsApp) status_text() string {
	if a.read_result != .ok {
		return settings_error_text(a.read_result)
	}
	if a.write_result != .ok {
		return settings_error_text(a.write_result)
	}
	if !a.state.online {
		return settings_error_text(BacklightResult.offline)
	}
	if !a.state.writable {
		return tr('settings.display.read_only')
	}
	if a.state.pending {
		return tr('settings.display.pending')
	}
	return tr('settings.display.read_from')
}

fn (a &SettingsApp) display_pane(width int) []ui2.Element {
	x := settings_padding
	inner := width - 2 * settings_padding
	if inner < 300 {
		mut narrow := frame_elements(1)
		narrow << settings_label(tr('settings.display.enlarge'), x, settings_padding, if inner > 0 {
			inner
		} else {
			1
		}, body_text)
		return narrow
	}

	a.follow_display_language()
	active := a.can_change()
	percent := if a.read_result == .ok { backlight_percent(&a.state) } else { -1 }
	mut out := frame_elements(settings_brightness_actions.len + 16)
	out << ui2.label('', tr('settings.category.display'), ui2.rect(f64(x), 16, f64(inner), 28), ui2.TextStyle{
		color: body_heading
		size: 20
		bold: true
	})
	// The caption is wide enough for «Масштаб», the longest translation.
	out << settings_label(tr('settings.display.scale'), x, 46, 58, body_muted)
	out << settings_scale_button(settings_scale_100_action, '100%', x + 66, desktop_requested_scale() == desktop_scale_100)
	out << settings_scale_button(settings_scale_200_action, '200%', x + 132, desktop_requested_scale() == desktop_scale_200)
	out << settings_label(tr('settings.display.built_in'), x + 206, 46, inner - 206, body_muted)
	out << ui2.view('', ui2.rect(f64(x), 76, f64(inner), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])
	out << settings_label(tr('settings.display.brightness'), x, 90, inner - 100, body_heading)
	out << settings_label(a.level_text, x + inner - 100, 90, 100, body_heading)
	// A click-to-set stepped bar, not a pretend draggable slider: NativeApp
	// receives action ids, not pointer coordinates. Every step is 5%.
	for i, id in settings_brightness_actions {
		left := x + inner * i / settings_brightness_actions.len
		right := x + inner * (i + 1) / settings_brightness_actions.len
		out << ui2.Element{
			kind: .button
			id: id
			frame: ui2.rect(f64(left), 122, f64(right - left - 1), 28)
			enabled: active
			accessibility_label: settings_brightness_labels[i]
			box: ui2.BoxStyle{
				bg: if !active {
					files_up_disabled
				} else if percent >= i * 5 {
					app_accent
				} else {
					body_rule
				}
				radius: 3
			}
		}
	}
	out << settings_label(a.range_text, x, 160, inner, body_muted)
	out << settings_button('settings.decrease', '- 5%', ui2.rect(f64(x), 192, 62, 30), active
		&& percent > 0)
	out << settings_button('settings.increase', '+ 5%', ui2.rect(f64(x + 70), 192, 62, 30), active && percent >= 0 && percent < 100)
	out << settings_button('settings.refresh', tr('settings.display.refresh'), ui2.rect(f64(x + inner - 80), 192, 80, 30), true)
	out << settings_label(a.requested_text, x, 236, inner, body_text)
	out << settings_label(a.actual_text, x, 258, inner, body_text)
	out << settings_label(a.status_text(), x, 290, inner, if a.read_result != .ok
		|| a.write_result != .ok {
		files_error
	} else {
		body_muted
	})
	if a.read_result == .unavailable {
		out << settings_label(tr('settings.display.dcp_required'), x, 312, inner, body_muted)
	} else {
		out << settings_label(tr('settings.display.bar_hint'), x, 312, inner, body_muted)
	}
	return out
}

fn (a &SettingsApp) battery_pane(width int, height int) []ui2.Element {
	inner := width - 2 * settings_padding
	// Nothing offscreen is built, so nothing offscreen can become a hit target.
	if inner < 300 || height < 360 {
		mut narrow := frame_elements(1)
		narrow << settings_label(tr('settings.battery.enlarge'), settings_padding, settings_padding, if inner > 0 {
			inner
		} else {
			1
		}, body_text)
		return narrow
	}
	percent := a.battery_read(false)
	history := a.battery_history()
	return battery_settings_elements(percent, &history, settings_padding, inner)
}

// The Display and Battery actions. The sidebar has already dealt with choosing
// the category, so everything here is a control inside one of the two panes.
fn (mut a SettingsApp) handle_device(event_id string) {
	if event_id == 'settings.refresh' {
		if a.category == .battery {
			a.battery_read(true)
		} else {
			a.write_result = BacklightResult.ok
			a.refresh()
		}
		return
	}
	// Ignore stale Display hit targets while the Battery pane is selected.
	if a.category != .display {
		return
	}
	if event_id == settings_scale_100_action {
		desktop_request_scale(desktop_scale_100)
		return
	}
	if event_id == settings_scale_200_action {
		desktop_request_scale(desktop_scale_200)
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
		current := backlight_percent(&a.state)
		if current < 0 {
			return
		}
		target = current + if event_id == 'settings.increase' { 5 } else { -5 }
		if target < 0 {
			target = 0
		}
		if target > 100 {
			target = 100
		}
	}
	a.write_result = a.write_percent(target)
	// A successful write only queues work. Read actual/pending from the driver.
	a.refresh()
}
