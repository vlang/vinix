// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

const files_trash_messages = ['files.trash.unsafe', 'files.trash.unavailable', 'files.trash.busy',
	'files.trash.damaged', 'files.trash.changed', 'files.trash.failed', 'files.trash.cross_device',
	'files.trash.conflict', 'files.trash.parent_missing', 'files.trash.nonempty', 'files.trash.partial',
	'files.trash.unsynced', 'files.trash.changed_moved']!

fn files_trash_message(key string) string {
	for message in files_trash_messages { if key == message { return message } }
	return ''
}

fn (mut trash FilesTrash) clamp_page() {
	if trash.visible_rows < 1 { trash.visible_rows = 1 }
	last := if trash.entries.len > 0 { (trash.entries.len - 1) / trash.visible_rows } else { 0 }
	if trash.page < 0 { trash.page = 0 }
	if trash.page > last { trash.page = last }
}

fn (mut trash FilesTrash) action(event string) {
	if event.starts_with(files_trash_row_prefix) {
		if index := notes_number(unsafe { tos(event.str + files_trash_row_prefix.len, event.len - files_trash_row_prefix.len) }) {
			if index < u64(trash.entries.len) {
				trash.selected = int(index)
				trash.confirming = false
			}
		}
		return
	}
	match event {
		'files.trash.refresh' { trash.reload() }
		'files.trash.restore' { trash.restore() }
		'files.trash.empty' { trash.confirming = true }
		'files.trash.confirm' { trash.empty_confirmed() }
		'files.trash.cancel' { trash.confirming = false }
		'files.trash.previous' {
			trash.page--
			trash.confirming = false
			trash.clamp_page()
		}
		'files.trash.next' {
			trash.page++
			trash.confirming = false
			trash.clamp_page()
		}
		else {
			message := files_trash_message(event)
			if message.len > 0 { trash.status = message }
		}
	}
}

fn (mut trash FilesTrash) key(input string) {
	if input == '\x1b[5~' { trash.action('files.trash.previous') }
	if input == '\x1b[6~' { trash.action('files.trash.next') }
	if input == '\x1b' { trash.confirming = false }
}

fn (mut trash FilesTrash) build(size ui2.Rect) ui2.Element {
	width := int(size.width)
	height := int(size.height)
	inner := if width > 16 { width - 16 } else { 1 }
	available := height - 246
	trash.visible_rows = if available >= 48 { available / 48 } else { 1 }
	if trash.visible_rows > files_trash_limit { trash.visible_rows = files_trash_limit }
	trash.clamp_page()
	mut children := frame_elements(18 + trash.visible_rows)
	children << ui2.label('', tr('files.trash.title'), ui2.rect(8, 8, f64(inner), 26), ui2.TextStyle{ color: body_text, size: 18 })
	children << console_button('files.trash.back', 'files.trash.back', 8, 40, 136, false)
	children << console_button('files.trash.refresh', 'files.trash.refresh', 152, 40, 92, false)
	children << console_button('files.trash.restore', 'files.trash.restore', 252, 40, 150, false)
	children << console_button('files.trash.empty', 'files.trash.empty', 410, 40, 132, false)
	children << ui2.label('', tr('files.trash.hint'), ui2.rect(8, 76, f64(inner), 28), ui2.TextStyle{ color: body_muted, size: 11, lines: 2 })
	children << ui2.label('', tr('files.trash.limited'), ui2.rect(8, 108, f64(inner), 28), ui2.TextStyle{ color: body_muted, size: 11, lines: 2 })
	if trash.entries.len == 0 {
		children << ui2.label('', tr(if trash.damaged {
			'files.trash.damaged'
		} else {
			'files.trash.empty_list'
		}), ui2.rect(8, 146, f64(inner), 24), ui2.TextStyle{ color: body_muted, size: 12 })
	}
	for row in 0 .. trash.visible_rows {
		index := trash.page * trash.visible_rows + row
		if index >= trash.entries.len || 142 + (row + 1) * 48 > height - 104 { break }
		entry := &trash.entries[index]
		mut labels := frame_elements(2)
		label_width := if inner > 16 { inner - 16 } else { 1 }
		labels << ui2.label('', files_trash_name(entry.path), ui2.rect(8, 3, f64(label_width), 20), ui2.TextStyle{ color: body_text, size: 13 })
		labels << ui2.label('', entry.path, ui2.rect(8, 23, f64(label_width), 19), ui2.TextStyle{ color: body_muted, size: 11 })
		children << ui2.clickable_view(entry.action, ui2.rect(8, f64(142 + row * 48), f64(inner), 44), ui2.BoxStyle{
			bg:            if trash.selected == index { body_panel } else { app_surface }
			radius:        4
			border_color:  if trash.selected == index { app_accent } else { body_rule }
			border_left:   1
			border_right:  1
			border_top:    1
			border_bottom: 1
		}, labels)
	}
	footer := if height > 104 { height - 104 } else { 0 }
	children << console_button('files.trash.previous', 'files.trash.previous', 8, footer, 100, false)
	children << console_button('files.trash.next', 'files.trash.next', 116, footer, 100, false)
	if trash.confirming {
		children << ui2.label('', tr('files.trash.confirm_hint'), ui2.rect(8, f64(footer + 32), f64(inner), 26), ui2.TextStyle{ color: body_text, size: 11, lines: 2 })
		children << console_button('files.trash.confirm', 'files.trash.confirm', 8, footer + 64, 180, false)
		children << console_button('files.trash.cancel', 'files.trash.cancel', 196, footer + 64, 100, false)
	} else {
		children << ui2.label('', tr(trash.status), ui2.rect(8, f64(footer + 34), f64(inner), 54), ui2.TextStyle{ color: body_text, size: 12, lines: 3 })
	}
	return ui2.screen(app_surface, children)
}

fn (mut a FilesContextApp) ensure_trash() {
	if a.trash.home.len == 0 && a.trash.home_fd < 0 {
		home := if desktop_user_home.len > 0 { desktop_user_home } else { desktop_home }
		a.trash = files_trash_new(home)
	}
}

fn (mut a FilesContextApp) open_trash() {
	a.ensure_trash()
	a.clear_rename()
	a.preview.close()
	a.files.info.close()
	a.tag_picker = false
	a.files.search_focused = false
	a.trash_open = true
	a.trash.reload()
}

// Reserve an actual footer instead of covering the browser's last row.
fn (a &FilesContextApp) trash_footer(size ui2.Rect) []ui2.Element {
	mut children := frame_elements(3)
	top := if size.height > 34 { size.height - 34 } else { 0.0 }
	children << ui2.view('', ui2.rect(0, top, size.width, 34), ui2.BoxStyle{ bg: body_panel }, [])
	children << console_button('files.trash.open', 'files.trash.open', 8, int(top) + 3, 96, false)
	if size.width > 120 && a.trash.status != 'files.trash.ready' {
		children << ui2.label('', tr(a.trash.status), ui2.rect(112, top + 3, size.width - 120, 28), ui2.TextStyle{ color: body_text, size: 11, lines: 2 })
	}
	return children
}
