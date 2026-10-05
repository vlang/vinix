// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn test_release_tags_are_ordered_by_date_then_same_day_number() {
	assert release_order('iso-2026-09-29') > 0
	assert release_order('iso-2026-09-24') < release_order('iso-2026-09-29')
	assert release_order('iso-2026-09-29') < release_order('iso-2026-09-29-2')
	// Not string order: the tenth release of a day follows the second.
	assert release_order('iso-2026-09-29-2') < release_order('iso-2026-09-29-10')
	assert release_order('iso-2026-09-29-10') < release_order('iso-2026-09-30')
	assert release_order('iso-2026-12-31-99') < release_order('iso-2027-01-01')
}

fn test_anything_but_a_release_tag_ranks_nowhere() {
	for tag in ['', 'unknown', 'nightly-2026-09-07', 'm1-installer-latest', 'iso-2026-9-29',
		'iso-2026-09-29-', 'iso-2026-09-29x', 'iso-2026-09-29-2a', 'iso-2026/09/29',
		'<html>'] {
		assert release_order(tag) == 0, tag
	}
}

fn test_only_an_older_release_is_out_of_date() {
	assert release_is_older('iso-2026-09-24', 'iso-2026-09-29-2')
	assert release_is_older('iso-2026-09-29', 'iso-2026-09-29-2')
	assert !release_is_older('iso-2026-09-29-2', 'iso-2026-09-29-2')
	// Newer than the site says: a release the site does not name yet.
	assert !release_is_older('iso-2026-09-30', 'iso-2026-09-29-2')
	// A development image, or an answer that is not a tag, says nothing.
	assert !release_is_older('', 'iso-2026-09-29')
	assert !release_is_older('iso-2026-09-24', 'unknown')
}

fn outdated_desktop() Desktop {
	mut desktop := Desktop{
		canvas: new_canvas(1024, 768)
		fonts:  load_fonts()
	}
	desktop.version_check.installed = 'iso-2026-09-24'
	desktop.version_check.latest = 'iso-2026-09-29-2'
	return desktop
}

fn outdated_texts(el ui2.Element, mut out []string) {
	if el.text.len > 0 {
		out << el.text
	}
	for child in el.children {
		outdated_texts(child, mut out)
	}
}

fn outdated_assert_fits(desktop &Desktop, el ui2.Element, context string) {
	if el.text.len > 0 && el.kind == .label {
		face := desktop.face_for(el.text_style)
		width := face.text_width(el.text)
		assert width <= int(el.frame.width), '${context}: «${el.text}» is ${width}px in ${int(el.frame.width)}px'
	}
	for child in el.children {
		outdated_assert_fits(desktop, child, context)
	}
}

fn test_outdated_window_says_what_to_do_and_names_both_releases() {
	mut desktop := outdated_desktop()
	desktop.open_outdated_window()
	assert desktop.windows.len == 1
	window := desktop.windows[0]
	assert window.page == .outdated
	assert desktop.focus == window.id
	assert app_title_text(window.title) == 'Vinix Update'
	// Centred across, and wholly on screen.
	assert window.x + window.width / 2 == desktop.canvas.width / 2
	assert window.y >= 0 && window.y + window.height <= desktop.canvas.height

	mut texts := []string{}
	outdated_texts(ui2.screen(0, window.content(window.width, window.height, &desktop)), mut
		texts)
	assert 'Your Vinix is out of date' in texts
	assert 'Please go to vinix-os.org and download the latest ISO.' in texts
	assert 'Installed: iso-2026-09-24    Latest: iso-2026-09-29-2' in texts
}

fn test_outdated_window_fits_in_every_language() {
	mut desktop := outdated_desktop()
	defer {
		set_desktop_language(.en)
	}
	for language in desktop_languages {
		set_desktop_language(language)
		for width in [outdated_window_width, 440] {
			root := ui2.screen(0, outdated_page(width, &desktop))
			outdated_assert_fits(&desktop, root, '${language} at ${width}px')
		}
	}
}

fn test_a_small_screen_still_gets_the_whole_window() {
	mut desktop := Desktop{
		canvas: new_canvas(520, 400)
		fonts:  load_fonts()
	}
	desktop.open_outdated_window()
	window := desktop.windows[0]
	assert window.x >= 0 && window.x + window.width <= desktop.canvas.width
	assert window.y >= 0 && window.y + window.height <= desktop.canvas.height
}
