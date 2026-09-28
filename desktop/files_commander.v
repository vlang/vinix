// SPDX-License-Identifier: GPL-2.0-or-later
// Two independent directory panes for Files' commander view.
module main

import ui2

fn files_commander_pane_x(window_width int, pane int) int {
	left := files_content_left(window_width)
	return if pane == 0 { left } else { left + (window_width - left) / 2 }
}

fn files_commander_pane_width(window_width int, pane int) int {
	left := files_content_left(window_width)
	return if pane == 0 {
		(window_width - left) / 2
	} else {
		window_width - files_commander_pane_x(window_width,
			pane)
	}
}

fn files_commander_pane_at(x int, window_width int) int {
	left := files_content_left(window_width)
	if x < left || x >= window_width {
		return -1
	}
	return if x < files_commander_pane_x(window_width, 1) { 0 } else { 1 }
}

fn files_commander_pane(mut children []ui2.Element, browser &FileBrowser, settings &FilesSettings,
	pane int, active_pane int, x int, width int, rows_top int, rows_height int, visible_rows int) {
	if width <= 0 {
		return
	}
	action := if pane == 0 { files_action_pane_left } else { files_action_pane_right }
	selected := pane == active_pane
	mut header := frame_elements(1)
	header << ui2.label('', browser.path, ui2.rect(files_padding, 3, f64(width - 2 * files_padding),
		files_pane_header_height - 6), ui2.TextStyle{
		color: if selected { app_on_accent } else { body_heading }
		size:  12
		bold:  selected
	})
	children << ui2.Element{
		...ui2.clickable_view(action, ui2.rect(f64(x), files_header_height, f64(width),
			files_pane_header_height), ui2.BoxStyle{
			bg: if selected { files_up } else { body_panel }
		}, header)
		tooltip: browser.path
	}
	files_zebra_background(mut children, x, rows_top, width, rows_height, browser.scroll)
	children << ui2.clickable_view(action, ui2.rect(f64(x), f64(rows_top), f64(width),
		f64(rows_height)), ui2.BoxStyle{ transparent: true }, [])
	if browser.error != '' {
		children << ui2.label('', browser.error, ui2.rect(f64(x + files_padding), f64(rows_top + 8),
			f64(width - 2 * files_padding), 32), ui2.TextStyle{
			color: files_error
			size:  12
			lines: 2
		})
		return
	}
	if browser.entries.len == 0 {
		children << ui2.label('', 'This directory is empty.', ui2.rect(f64(x + files_padding),
			f64(rows_top + 8), f64(width - 2 * files_padding), 20), ui2.TextStyle{
			color: body_muted
			size:  12
		})
		return
	}
	size_width := if width >= 250 { 52 } else { 0 }
	mut name_width := width - 2 * files_padding - 24 - size_width - 10
	if name_width < 12 {
		name_width = 12
	}
	mut slot := 0
	for index := browser.scroll; index < browser.entries.len && slot < visible_rows; index++ {
		entry := &browser.entries[index]
		entry_path := join_path(browser.path, entry.name)
		tag_color := settings.first_color(entry_path)
		mut row := frame_elements(3)
		row << ui2.button_with_image('', '', if entry.is_dir {
			'builtin:folder'
		} else {
			'builtin:file'
		},
			ui2.rect(files_padding, 4, 16, 16), ui2.BoxStyle{ transparent: true }, ui2.TextStyle{
				color: if entry.is_dir && settings.tint_folders && tag_color != 0 {
					tag_color
				} else if entry.is_dir {
					files_folder_icon
				} else {
					files_file_icon
				}
			})
		row << ui2.label('', entry.name, ui2.rect(files_padding + 24, 0, f64(name_width),
			files_row_height), ui2.TextStyle{
			color: if entry.is_dir { body_heading } else { body_text }
			size:  12
		})
		if size_width > 0 {
			row << ui2.label('', if entry.is_dir { '' } else { entry.size_text },
				ui2.rect(f64(width - files_padding - size_width), 0, f64(size_width), files_row_height),
				ui2.TextStyle{ color: body_muted, size: 11, align: .right })
		}
		if tag_color != 0 {
			row << ui2.view('', ui2.rect(f64(width - files_padding - size_width - 9), 9, 7,
				7), ui2.BoxStyle{ bg: tag_color, radius: 4 }, [])
		}
		children << ui2.clickable_view(entry.row_action, ui2.rect(f64(x),
			f64(rows_top + slot * files_row_height), f64(width), files_row_height), ui2.BoxStyle{
			bg:          files_row_hover
			transparent: browser.hover_row != index && browser.selected_row != index
		}, row)
		unsafe { entry_path.free() }
		slot++
	}
	if browser.entries.len > visible_rows {
		children << files_vertical_scrollbar(x + width - files_scrollbar_width - 2, rows_top,
			rows_height, visible_rows, browser.entries.len, browser.scroll)
	}
}

fn (mut a FileBrowserApp) clamp_commander_scroll() {
	a.dual_left.scroll = files_clamp(a.dual_left.scroll, if a.dual_left.entries.len > a.visible_rows {
		a.dual_left.entries.len - a.visible_rows
	} else {
		0
	})
	a.dual_right.scroll = files_clamp(a.dual_right.scroll, if a.dual_right.entries.len > a.visible_rows {
		a.dual_right.entries.len - a.visible_rows
	} else {
		0
	})
}

fn files_commander_focus_path(mut browser FileBrowser, parent string, name string, visible_rows int) {
	if browser.path != parent {
		return
	}
	index := files_context_entry_index(browser.entries, name)
	if index < 0 {
		return
	}
	if index < browser.scroll {
		browser.scroll = index
	} else if index >= browser.scroll + visible_rows {
		browser.scroll = index - visible_rows + 1
	}
}

fn files_commander_next_selection(mut browser FileBrowser, delta int) string {
	if browser.entries.len == 0 {
		return ''
	}
	next := files_clamp(browser.selected_row + delta, browser.entries.len - 1)
	browser.selected_row = next
	return join_path(browser.path, browser.entries[next].name)
}

fn (mut a FileBrowserApp) build_commander(width int, height int, mut children []ui2.Element) !ui2.Element {
	a.clamp_commander_scroll()
	left_x := files_commander_pane_x(width, 0)
	left_width := files_commander_pane_width(width, 0)
	right_x := files_commander_pane_x(width, 1)
	right_width := files_commander_pane_width(width, 1)
	files_commander_pane(mut children, &a.dual_left, &a.settings, 0, a.active_pane, left_x,
		left_width, a.rows_top, a.rows_height, a.visible_rows)
	files_commander_pane(mut children, &a.dual_right, &a.settings, 1, a.active_pane, right_x,
		right_width, a.rows_top, a.rows_height, a.visible_rows)
	children << ui2.view('', ui2.rect(f64(right_x), files_header_height, 1,
		f64(height - files_header_height)), ui2.BoxStyle{ bg: body_rule }, [])
	return a.screen_with_sidebar(width, height, mut children)
}

fn (mut a FileBrowserApp) commander_scroll(pane int, steps int) {
	if pane == 0 {
		a.dual_left.scroll = files_clamp(a.dual_left.scroll - steps * 2,
			if a.dual_left.entries.len > a.visible_rows {
				a.dual_left.entries.len - a.visible_rows
			} else {
				0
			})
	} else {
		a.dual_right.scroll = files_clamp(a.dual_right.scroll - steps * 2,
			if a.dual_right.entries.len > a.visible_rows {
				a.dual_right.entries.len - a.visible_rows
			} else {
				0
			})
	}
}

fn (mut a FileBrowserApp) commander_begin_drag(pane int, y int) {
	mut total := a.dual_left.entries.len
	mut current := a.dual_left.scroll
	if pane == 1 {
		total = a.dual_right.entries.len
		current = a.dual_right.scroll
	}
	a.vertical_drag_id = if pane == 0 { -3 } else { -4 }
	a.vertical_drag_y = y
	a.vertical_drag_scroll = current
	position, thumb := files_scroll_thumb(a.rows_height, a.visible_rows, total, current)
	if y < a.rows_top + position || y >= a.rows_top + position + thumb {
		travel := a.rows_height - thumb
		maximum := total - a.visible_rows
		if travel > 0 && maximum > 0 {
			next := files_clamp((y - a.rows_top - thumb / 2) * maximum / travel, maximum)
			a.vertical_drag_scroll = next
			if pane == 0 { a.dual_left.scroll = next } else { a.dual_right.scroll = next }
		}
	}
}

fn (mut a FileBrowserApp) commander_pointer_event(phase AppPointerPhase, button AppPointerButton,
	scroll int, x int, y int, width int) {
	if phase == .up {
		a.vertical_drag_id = -2
		return
	}
	if phase == .move && (a.vertical_drag_id == -3 || a.vertical_drag_id == -4) {
		pane := if a.vertical_drag_id == -3 { 0 } else { 1 }
		total := if pane == 0 { a.dual_left.entries.len } else { a.dual_right.entries.len }
		_, thumb := files_scroll_thumb(a.rows_height, a.visible_rows, total,
			a.vertical_drag_scroll)
		travel := a.rows_height - thumb
		maximum := total - a.visible_rows
		if travel > 0 && maximum > 0 {
			next := files_clamp(a.vertical_drag_scroll +
				(y - a.vertical_drag_y) * maximum / travel, maximum)
			if pane == 0 { a.dual_left.scroll = next } else { a.dual_right.scroll = next }
		}
		return
	}
	pane := files_commander_pane_at(x, width)
	if phase == .scroll {
		if pane < 0 {
			a.scroll_at(x, y, scroll, width)
		} else if y >= a.rows_top && y < a.rows_top + a.rows_height {
			a.commander_scroll(pane, scroll)
		}
		return
	}
	if phase != .down || button != .left || pane < 0 {
		return
	}
	a.active_pane = pane
	if y < a.rows_top || y >= a.rows_top + a.rows_height {
		return
	}
	pane_right := files_commander_pane_x(width, pane) + files_commander_pane_width(width, pane)
	total := if pane == 0 { a.dual_left.entries.len } else { a.dual_right.entries.len }
	if total > a.visible_rows && x >= pane_right - files_scrollbar_width - 4 {
		a.commander_begin_drag(pane, y)
	}
}
