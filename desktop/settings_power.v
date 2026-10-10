// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// The Power category of Settings: when the display turns off and the machine
// sleeps for want of input, what closing the lid does, and the CPU
// performance profile.
//
// The two timeouts are desktop preferences like any other. The lid action and
// the profile belong to the kernel: the pane shows what /sys says now, writes
// a choice there when one is made, and keeps the choice in the preferences
// only so that the desktop can put it back after a restart. A control the
// machine has no use for is left out, and one the kernel refuses is shown
// disabled with the reason, rather than offered and then failing.
module main

import ui2

// Static ids: the framebuffer renderer frees child arrays, not strings.
const settings_power_display_actions = ['settings.power.display.0', 'settings.power.display.1',
	'settings.power.display.2', 'settings.power.display.3', 'settings.power.display.4',
	'settings.power.display.5', 'settings.power.display.6', 'settings.power.display.7']!
const settings_power_sleep_actions = ['settings.power.sleep.0', 'settings.power.sleep.1',
	'settings.power.sleep.2', 'settings.power.sleep.3', 'settings.power.sleep.4',
	'settings.power.sleep.5', 'settings.power.sleep.6', 'settings.power.sleep.7']!
const settings_power_lid_actions = ['settings.power.lid.0', 'settings.power.lid.1']!
const settings_power_profile_actions = ['settings.power.profile.0', 'settings.power.profile.1',
	'settings.power.profile.2', 'settings.power.profile.3']!

// The timeouts' labels, "5 min" and the rest, made once per language: the
// pane is rebuilt every frame, and its labels are text the renderer does not
// free. The first choice is Never, which needs no filling.
struct PowerMinuteLabels {
mut:
	language DesktopLanguage
	labels   [8]string
}

__global power_minute_labels = PowerMinuteLabels{}

fn power_timeout_text(index int) string {
	if index <= 0 || index >= idle_timeout_choices.len {
		return tr('settings.power.never')
	}
	if power_minute_labels.language != desktop_language {
		for i in 0 .. power_minute_labels.labels.len {
			if power_minute_labels.labels[i].len > 0 {
				unsafe { power_minute_labels.labels[i].free() }
				power_minute_labels.labels[i] = ''
			}
		}
		power_minute_labels.language = desktop_language
	}
	if power_minute_labels.labels[index].len == 0 {
		minutes := idle_timeout_choices[index].str()
		power_minute_labels.labels[index] = tr_fill('settings.power.minutes', minutes)
		unsafe { minutes.free() }
	}
	return power_minute_labels.labels[index]
}

fn power_profile_text(profile PowerProfile) string {
	return match profile {
		.automatic { tr('settings.power.profile.automatic') }
		.performance { tr('settings.power.profile.performance') }
		.balanced { tr('settings.power.profile.balanced') }
		.power_saver { tr('settings.power.profile.power_saver') }
	}
}

// refresh_power rereads what the kernel says. Nothing is written.
fn (mut a SettingsApp) refresh_power() {
	mut next := PowerControls{}
	a.power_read(mut next)
	a.power = next
	a.power_last_poll_ms = desktop_monotonic_ms()
	a.power_initialized = true
}

// Whether a profile can be chosen: the kernel's file can be written, and the
// kernel has not refused one since this page was opened. Every virtual
// machine fails the first test, having no frequency driver.
fn (a &SettingsApp) power_profile_settable() bool {
	return a.power.profile_known && a.power.profile_settable && !a.power_profile_refused
}

// A choice that can be switched off: one the machine cannot take is drawn,
// so that what is in force can be seen, and takes no click.
fn settings_power_choice(id string, label string, x int, y int, width int, selected bool, enabled bool) ui2.Element {
	if enabled {
		return settings_choice(id, label, x, y, width, selected)
	}
	return ui2.Element{
		kind:                .button
		id:                  id
		text:                label
		frame:               ui2.rect(f64(x), f64(y), f64(width), 28)
		enabled:             false
		box:                 ui2.BoxStyle{
			bg:     if selected { body_rule } else { files_up_disabled }
			radius: 6
		}
		text_style:          ui2.TextStyle{
			color: body_muted
			size:  12
			align: .center
		}
		native_style:        true
		checked:             selected
		accessibility_role:  'radio'
		accessibility_label: label
		accessibility_value: if selected { tr('settings.choice.selected') } else { tr('settings.choice.not_selected') }
	}
}

// One row of the eight timeouts. Never is twice the width of the others,
// which have only a number and a unit to hold.
fn power_timeout_row(mut out []ui2.Element, actions [8]string, minutes int, y int, inner int, enabled bool) {
	gap := 6
	unit := (inner - (idle_timeout_choices.len - 1) * gap) / (idle_timeout_choices.len + 1)
	mut x := settings_padding
	for index, choice in idle_timeout_choices {
		width := if index == 0 { 2 * unit } else { unit }
		out << settings_power_choice(actions[index], power_timeout_text(index), x, y, width,
			choice == minutes, enabled)
		x += width + gap
	}
}

fn (a &SettingsApp) power_pane(width int) []ui2.Element {
	inner := width - 2 * settings_padding
	if inner < 300 {
		mut narrow := frame_elements(1)
		narrow << settings_label(tr('settings.display.enlarge'), settings_padding, settings_padding, if inner > 0 {
			inner
		} else {
			1
		}, body_text)
		return narrow
	}
	// The timeouts are the desktop's. Without one behind this window they
	// are shown as they would start out and take no click.
	has_desktop := a.desktop != unsafe { nil }
	settings := if has_desktop { a.desktop.settings } else { Settings{} }
	mut out := frame_elements(2 * idle_timeout_choices.len + power_profiles.len + 12)
	mut y := settings_padding

	out << settings_heading(tr('settings.power.display_off'), y, width)
	y += 22
	power_timeout_row(mut out, settings_power_display_actions, settings.display_off_minutes, y,
		inner, has_desktop)
	y += 28 + 14

	out << settings_heading(tr('settings.power.sleep'), y, width)
	y += 22
	power_timeout_row(mut out, settings_power_sleep_actions, settings.sleep_minutes, y, inner,
		has_desktop && a.power.sleep)
	y += 28 + 6
	out << ui2.label('settings.power.idle_note', if a.power.sleep {
		tr('settings.power.idle_note')
	} else {
		tr('settings.power.no_sleep')
	}, ui2.rect(f64(settings_padding), f64(y), f64(inner), 16), ui2.TextStyle{
		color: body_muted
		size:  11
	})
	y += 16
	out << settings_note(tr('settings.power.video_note'), y, width)
	y += 16 + 14

	// A machine with no lid, or one whose kernel does not say, has no lid to
	// make a choice about.
	if a.power.lid {
		half := (inner - settings_row_gap) / 2
		out << settings_heading(tr('settings.power.lid'), y, width)
		y += 22
		out << settings_choice(settings_power_lid_actions[0], tr('settings.power.lid.sleep'),
			settings_padding, y, half, a.power.lid_action == .suspend)
		out << settings_choice(settings_power_lid_actions[1], tr('settings.power.lid.nothing'),
			settings_padding + half + settings_row_gap, y, half, a.power.lid_action == .ignore)
		y += 28 + 14
	}

	if a.power.profile_known {
		columns := power_profiles.len
		cell := (inner - (columns - 1) * settings_row_gap) / columns
		settable := a.power_profile_settable()
		out << settings_heading(tr('settings.power.performance'), y, width)
		y += 22
		for index, profile in power_profiles {
			out << settings_power_choice(settings_power_profile_actions[index], power_profile_text(profile),
				settings_padding + index * (cell + settings_row_gap), y, cell, a.power.profile == profile,
				settable)
		}
		y += 28 + 6
		out << ui2.label('settings.power.profile_note', if settable {
			tr('settings.power.profile_note')
		} else {
			tr('settings.power.profile_refused')
		}, ui2.rect(f64(settings_padding), f64(y), f64(inner), 16), ui2.TextStyle{
			color: body_muted
			size:  11
		})
		y += 16
	}
	// How the last write to the kernel went, when it did not go and the
	// line above does not already say why.
	if a.power_result != .ok && !a.power_profile_refused {
		out << ui2.label('settings.power.error', tr('settings.power.write_failed'), ui2.rect(f64(settings_padding), f64(y + 4), f64(inner), 16), ui2.TextStyle{
			color: files_error
			size:  11
		})
	}
	return out
}

// handle_power acts on a Power pane action. Each one rereads the kernel
// first, so a button left over from a frame ago cannot write to a control
// that has since gone or been refused.
fn (mut a SettingsApp) handle_power(event_id string) {
	for index, action in settings_power_display_actions {
		if event_id == action {
			if a.desktop != unsafe { nil } {
				a.desktop.settings.set_display_off_minutes(idle_timeout_choices[index])
			}
			return
		}
	}
	for index, action in settings_power_sleep_actions {
		if event_id == action {
			a.refresh_power()
			if a.desktop != unsafe { nil } && a.power.sleep {
				a.desktop.settings.set_sleep_minutes(idle_timeout_choices[index])
			}
			return
		}
	}
	for index, action in settings_power_lid_actions {
		if event_id == action {
			a.refresh_power()
			if !a.power.lid {
				return
			}
			wanted := if index == 1 { LidAction.ignore } else { LidAction.suspend }
			a.power_result = a.power_set_lid(wanted)
			// What the kernel now says is what is shown, and what is kept.
			a.refresh_power()
			if a.power_result == .ok && a.power.lid && a.desktop != unsafe { nil } {
				a.desktop.settings.lid_action = a.power.lid_action
			}
			return
		}
	}
	for index, action in settings_power_profile_actions {
		if event_id == action {
			a.refresh_power()
			if !a.power_profile_settable() {
				return
			}
			a.power_result = a.power_set_profile(power_profiles[index])
			if a.power_result == .permission {
				a.power_profile_refused = true
			}
			a.refresh_power()
			if a.power_result == .ok && a.power.profile_known && a.desktop != unsafe { nil } {
				a.desktop.settings.power_profile = a.power.profile
			}
			return
		}
	}
}
