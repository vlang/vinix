// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Settings' Keyboard pane: which input sources Ctrl-Space moves between, which
// one typing uses now, and a glimpse of what that one types.
module main

import ui2

const settings_action_keyboard_enable = 'settings.keyboard.enable.'
const settings_action_keyboard_current = 'settings.keyboard.current.'

// KeyboardPreview is what one layout types, as lists of keycaps. They are made
// once; the sentences around them are the desktop's language's, and are made
// for each frame into labels that own them.
struct KeyboardPreview {
	letters string
	option  string
	accents string
}

const keyboard_previews = keyboard_build_previews()

fn keyboard_preview_rune(r rune) rune {
	if dead := dead_key_for(r) {
		return dead.spacing
	}
	return r
}

fn keyboard_build_previews() []KeyboardPreview {
	mut previews := []KeyboardPreview{cap: keyboard_layouts.len}
	for layout in keyboard_layouts {
		keymap := keymap_for(layout) or {
			previews << KeyboardPreview{
				letters: 'q w e r t y u i o p [ ]'
			}
			continue
		}
		// The top letter row, as the keycaps read.
		mut letters := []string{cap: 12}
		for index in 13 .. 25 {
			letters << keyboard_preview_rune(keymap.lower[index]).str()
		}
		mut option := []string{}
		for r in keymap.option {
			if r != 0 {
				option << keyboard_preview_rune(r).str()
			}
		}
		mut accents := []string{}
		for level in [keymap.lower, keymap.upper, keymap.option] {
			for r in level {
				if dead := dead_key_for(r) {
					accent := dead.spacing.str()
					if accent !in accents {
						accents << accent
					}
				}
			}
		}
		previews << KeyboardPreview{
			letters: letters.join(' ')
			option:  option.join(' ')
			accents: accents.join(' ')
		}
	}
	return previews
}

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

// settings_owned_note is a note whose text was made for this frame; the
// renderer frees it with the frame.
fn settings_owned_note(text string, y int, width int) ui2.Element {
	return ui2.label(frame_owned_text_id, text, ui2.rect(f64(settings_padding), f64(y), f64(width - 2 * settings_padding), 16), ui2.TextStyle{
		color: body_muted
		size:  11
	})
}

fn (a &SettingsApp) keyboard_pane(width int) []ui2.Element {
	settings := a.desktop.settings
	inner := width - 2 * settings_padding
	columns := 3
	cell := (inner - (columns - 1) * settings_row_gap) / columns

	mut out := frame_elements(2 * keyboard_layouts.len + 10)
	mut y := settings_padding

	out << settings_heading(tr('settings.keyboard.sources'), y, width)
	y += 22
	out << settings_note(tr('settings.keyboard.sources_note'), y, width)
	y += 22
	for index, layout in keyboard_layouts {
		x := settings_padding + (index % columns) * (cell + settings_row_gap)
		row_y := y + (index / columns) * (28 + settings_row_gap)
		out << settings_toggle('${settings_action_keyboard_enable}${index}', keyboard_layout_text(layout),
			x, row_y, cell, settings.keyboard_layouts & layout.bit() != 0)
	}
	y += ((keyboard_layouts.len + columns - 1) / columns) * (28 + settings_row_gap) + 14

	out << settings_heading(tr('settings.keyboard.typing'), y, width)
	y += 22
	out << settings_note(tr('settings.keyboard.typing_note'), y, width)
	y += 22
	mut shown := 0
	for index, layout in keyboard_layouts {
		if settings.keyboard_layouts & layout.bit() == 0 {
			continue
		}
		x := settings_padding + (shown % columns) * (cell + settings_row_gap)
		row_y := y + (shown / columns) * (28 + settings_row_gap)
		out << settings_choice('${settings_action_keyboard_current}${index}', keyboard_layout_text(layout),
			x, row_y, cell, settings.keyboard_layout == layout)
		shown++
	}
	y += ((shown + columns - 1) / columns) * (28 + settings_row_gap) + 6

	preview := keyboard_previews[int(settings.keyboard_layout)]
	out << settings_owned_note(tr_fill('settings.keyboard.types', preview.letters), y, width)
	y += 18
	if preview.option.len > 0 {
		out << settings_owned_note(tr_fill('settings.keyboard.option_types', preview.option), y,
			width)
		y += 18
	}
	if preview.accents.len > 0 {
		out << settings_owned_note(tr_fill('settings.keyboard.accents', preview.accents), y,
			width)
		y += 18
	}
	return out
}

// handle_keyboard acts on a Keyboard pane action and says whether it was one.
// The last enabled input source cannot be turned off, and turning off the
// current one moves typing to the first that is still on.
fn (mut a SettingsApp) handle_keyboard(event_id string) bool {
	if event_id.starts_with(settings_action_keyboard_enable) {
		index := event_id[settings_action_keyboard_enable.len..].int()
		if index < 0 || index >= keyboard_layouts.len {
			return true
		}
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
	if event_id.starts_with(settings_action_keyboard_current) {
		index := event_id[settings_action_keyboard_current.len..].int()
		if index >= 0 && index < keyboard_layouts.len
			&& a.desktop.settings.keyboard_layouts & keyboard_layouts[index].bit() != 0 {
			a.desktop.settings.keyboard_layout = keyboard_layouts[index]
		}
		return true
	}
	return false
}
