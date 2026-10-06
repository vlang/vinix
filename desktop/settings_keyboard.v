// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Settings' Keyboard pane: which input sources Ctrl-Space and the taskbar's
// input menu move between.
module main

import ui2

const settings_action_keyboard_enable = 'settings.keyboard.enable.'
const settings_keyboard_actions = ['settings.keyboard.enable.0', 'settings.keyboard.enable.1',
	'settings.keyboard.enable.2', 'settings.keyboard.enable.3', 'settings.keyboard.enable.4',
	'settings.keyboard.enable.5']!

// A toggle looks like a choice but can be on beside others.
fn settings_toggle(id string, label string, x int, y int, width int, on bool) ui2.Element {
	return ui2.Element{
		kind:                .button
		id:                  id
		text:                label
		frame:               ui2.rect(f64(x), f64(y), f64(width), 28)
		box:                 ui2.BoxStyle{
			bg:     if on { app_accent } else { settings_choice_bg }
			radius: 6
		}
		text_style:          ui2.TextStyle{
			color: if on { app_on_accent } else { body_text }
			size:  12
			align: .center
		}
		native_style:        true
		checked:             on
		accessibility_role:  'checkbox'
		accessibility_label: label
		accessibility_value: if on { tr('settings.keyboard.on') } else { tr('settings.keyboard.off') }
	}
}

// keyboard_layout_text is how a layout is named on screen. KeyboardLayout's
// own title stays English, beside the model it describes.
fn keyboard_layout_text(layout KeyboardLayout) string {
	return match layout {
		.us { tr('settings.keyboard.layout.us') }
		.russian { tr('settings.keyboard.layout.russian') }
		.spanish { tr('settings.keyboard.layout.spanish') }
		.french { tr('settings.keyboard.layout.french') }
		.german { tr('settings.keyboard.layout.german') }
		.portuguese { tr('settings.keyboard.layout.portuguese') }
	}
}

fn (a &SettingsApp) keyboard_pane(width int) []ui2.Element {
	settings := a.desktop.settings
	inner := width - 2 * settings_padding
	columns := 3
	cell := (inner - (columns - 1) * settings_row_gap) / columns

	mut out := frame_elements(keyboard_layouts.len + 2)
	mut y := settings_padding

	out << settings_heading(tr('settings.keyboard.sources'), y, width)
	y += 22
	out << settings_note(tr('settings.keyboard.sources_note'), y, width)
	y += 22
	for index, layout in keyboard_layouts {
		x := settings_padding + (index % columns) * (cell + settings_row_gap)
		row_y := y + (index / columns) * (28 + settings_row_gap)
		out << settings_toggle(settings_keyboard_actions[index], keyboard_layout_text(layout),
			x, row_y, cell, settings.keyboard_layouts & layout.bit() != 0)
	}
	return out
}

// handle_keyboard acts on a Keyboard pane action and says whether it was one.
// The last enabled input source cannot be turned off, and turning off the
// current one moves typing to the first that is still on.
fn (mut a SettingsApp) handle_keyboard(event_id string) bool {
	if event_id.starts_with(settings_action_keyboard_enable) {
		mut index := -1
		for candidate, action in settings_keyboard_actions {
			if event_id == action { index = candidate; break }
		}
		if index < 0 { return true }
		layout := keyboard_layouts[index]
		mask := a.desktop.settings.keyboard_layouts
		if mask & layout.bit() == 0 {
			a.desktop.settings.keyboard_layouts = mask | layout.bit()
		} else if keyboard_layout_count(mask) > 1 {
			a.desktop.settings.keyboard_layouts = mask & ~layout.bit()
			if a.desktop.settings.keyboard_layout == layout {
				a.desktop.settings.keyboard_layout = keyboard_first_layout(a.desktop.settings.keyboard_layouts)
			}
		}
		return true
	}
	return false
}
