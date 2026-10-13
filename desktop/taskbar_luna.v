// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Windows XP's taskbar, for the Windows XP theme.
//
// The bar holds what the desktop's own holds (wm.v) and is laid out by the
// same code; this is what Windows XP has differently. A window's button is
// its icon and then its title, a raised blue button nearly the height of the
// bar that is pressed in for the window in front. What stands beside the
// Start button and is not a window -- the overview, a pinned program, a
// workspace that is not on show -- is its icon or its number alone until the
// pointer is over it, as Quick Launch is. The clock is small, regular and
// white: the time alone in the middle of the bar, or over the date when the
// date is on show. luna.v paints the bar, the buttons and the round button
// that opens the hidden icons.
module main

import ui2

// A window's button, and the icon and the type in it.
const luna_task_height = 34
const luna_task_icon = 20
const luna_task_inset = 7
const luna_task_text_size = 13
// What is in Quick Launch: the slot, the square that lights under the
// pointer, and the icon in it.
const luna_quick_width = 28
const luna_quick_side = 28
const luna_quick_icon = 22
// The clock and the build stamp: a line of each, and the line under it.
const luna_clock_time_size = 13
const luna_clock_date_size = 11
const luna_clock_time_rows = 17
const luna_clock_date_rows = 15

// taskbar_luna says whether the bar is Windows XP's. A dock is not a bar.
fn (d &Desktop) taskbar_luna() bool {
	theme := d.theme()
	return theme.chrome == .luna && !theme.dock
}

// luna_task_image is the icon on a window's button: the window's own, or the
// mark its title bar has when it has none.
fn luna_task_image(icon string) string {
	return if icon.len > 0 { icon } else { 'builtin:window' }
}

// taskbar_quick_count is how many of the bar's entries are in Quick Launch:
// the pinned programs with no window open, as taskbar_entries finds them.
fn (d &Desktop) taskbar_quick_count() int {
	if !d.taskbar_luna() {
		return 0
	}
	mut count := 0
	for index in d.pinned_apps {
		if index < 0 || index >= available_apps.len || index >= taskbar_pin_actions.len {
			continue
		}
		if d.taskbar_window_for_app(index) == 0 {
			count++
		}
	}
	return count
}

// luna_quick_elements appends a pinned program that is not running as
// Windows XP keeps one in Quick Launch: its icon alone, in a raised square
// while the pointer is over it. The square is the button; the icon lies over
// it and is not what a click lands on.
fn (d &Desktop) luna_quick_elements(mut children []ui2.Element, entry TaskbarEntry, x int, y int, width int,
	height int, dragging bool) {
	theme := d.theme()
	mut side := if width < height { width } else { height }
	if side > luna_quick_side {
		side = luna_quick_side
	}
	icon := if side - 4 < luna_quick_icon { side - 4 } else { luna_quick_icon }
	children << ui2.button(entry.id, '', ui2.rect(f64(x + (width - side) / 2), f64(y + (height - side) / 2),
		f64(side), f64(side)), ui2.BoxStyle{
		bg:          theme.taskbar_item_hover
		radius:      luna_bar_button_radius
		transparent: !dragging && d.hover != entry.id
	}, ui2.TextStyle{})
	children << ui2.Element{
		...ui2.image('', entry.icon, ui2.rect(f64(x + (width - icon) / 2), f64(y + (height - icon) / 2),
			f64(icon), f64(icon)))
		text_style: ui2.TextStyle{
			color: theme.taskbar_text_active
		}
	}
}

// luna_text_box is the width a line and the line under it need in Windows
// XP's type, and no more than `limit`, the box the desktop's own bar gives
// them. A desktop with no fonts, as some tests build, takes that box.
fn (d &Desktop) luna_text_box(first string, second string, limit int) int {
	if d.fonts.len == 0 {
		return limit
	}
	upper := d.face_for(ui2.TextStyle{
		size: luna_clock_time_size
	}).text_width(first)
	lower := d.face_for(ui2.TextStyle{
		size: luna_clock_date_size
	}).text_width(second)
	widest := if upper > lower { upper } else { lower }
	return if widest < limit { widest } else { limit }
}

// luna_clock_box is the room the clock takes. Its digits are all one width,
// so it holds still as the seconds tick.
fn (d &Desktop) luna_clock_box() int {
	return d.luna_text_box(d.taskbar_clock_time, d.taskbar_clock_date, taskbar_clock_width)
}

fn (d &Desktop) luna_build_box() int {
	return d.luna_text_box(d.taskbar_build_time, d.taskbar_build_date, taskbar_build_width)
}

// luna_taskbar_texts appends the build stamp and the clock. The clock is
// white, as Windows XP's is; the build stamp, which Windows XP has not, is
// paler beside it.
fn (d &Desktop) luna_taskbar_texts(mut children []ui2.Element, build_x int, build_width int, clock_x int,
	clock_width int) {
	theme := d.theme()
	luna_taskbar_text(mut children, 'build.time', 'build.date', d.taskbar_build_time, d.taskbar_build_date,
		build_x, build_width, theme.taskbar_muted)
	luna_taskbar_text(mut children, 'clock.time', 'clock.date', d.taskbar_clock_time, d.taskbar_clock_date,
		clock_x, clock_width, theme.taskbar_text_active)
}

// luna_taskbar_text appends a line and the line under it, one over the other
// about the middle of the bar. With nothing under it the first is in the
// middle by itself, which is how Windows XP shows the time.
fn luna_taskbar_text(mut children []ui2.Element, id string, under_id string, text string, under string, x int,
	width int, color u32) {
	rows := if under.len > 0 { luna_clock_time_rows + luna_clock_date_rows } else { luna_clock_time_rows }
	top := (taskbar_height - rows) / 2
	children << ui2.label(id, text, ui2.rect(f64(x), f64(top), f64(width), luna_clock_time_rows),
		ui2.TextStyle{
		color: color
		size:  luna_clock_time_size
		align: .center
	})
	children << ui2.label(under_id, under, ui2.rect(f64(x), f64(top + luna_clock_time_rows), f64(width),
		luna_clock_date_rows), ui2.TextStyle{
		color: color
		size:  luna_clock_date_size
		align: .center
	})
}
