// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only Get Info for files, folders and symbolic links.
module main

import ui2

const files_action_info = 'files.info'
const files_action_info_close = 'files.info.close'

struct FilesInfoPanel {
mut:
	open              bool
	path              string
	name              string
	kind_text         string
	size_text         string
	permissions       string
	owner             string
	modified_text     string
	accessed_text     string
	changed_text      string
	link_target       string
	error_key         string
	mode              u32
	size              u64
	modified          i64
	accessed          i64
	changed           i64
	tz_offset_seconds i64
	language          DesktopLanguage
}

fn (mut info FilesInfoPanel) close() {
	unsafe {
		info.path.free()
		info.name.free()
		info.kind_text.free()
		info.size_text.free()
		info.permissions.free()
		info.owner.free()
		info.modified_text.free()
		info.accessed_text.free()
		info.changed_text.free()
		info.link_target.free()
	}
	info = FilesInfoPanel{}
}

fn files_info_permissions(mode u32) string {
	mut octal := [u8(`0` + ((mode >> 9) & 7)), u8(`0` + ((mode >> 6) & 7)),
		u8(`0` + ((mode >> 3) & 7)), u8(`0` + (mode & 7))]!
	mut flags := [u8(`-`), `-`, `-`, `-`, `-`, `-`, `-`, `-`, `-`]!
	letters := [u8(`r`), `w`, `x`]!
	for index in 0 .. 9 {
		if mode & (u32(1) << u32(8 - index)) != 0 { flags[index] = letters[index % 3] }
	}
	if mode & 0o4000 != 0 { flags[2] = if flags[2] == `x` { `s` } else { `S` } }
	if mode & 0o2000 != 0 { flags[5] = if flags[5] == `x` { `s` } else { `S` } }
	if mode & 0o1000 != 0 { flags[8] = if flags[8] == `x` { `t` } else { `T` } }
	octal_text := unsafe { tos(&octal[0], octal.len) }
	flags_text := unsafe { tos(&flags[0], flags.len) }
	return '${octal_text} (${flags_text})'
}

fn (mut info FilesInfoPanel) read(path string, tz_offset_seconds i64) {
	info.close()
	info.open = true
	info.path = path.clone()
	name_start := if path == '/' { 0 } else { (path.last_index('/') or { -1 }) + 1 }
	info.name = unsafe { tos(&u8(path.str) + name_start, path.len - name_start) }.clone()
	info.tz_offset_seconds = tz_offset_seconds
	// lstat keeps a symbolic link's own metadata visible, including links
	// whose target is missing. Following one would hide its mode and size.
	mut stat := C.stat{}
	if unsafe { C.lstat(&char(path.str), &stat) } != 0 {
		info.error_key = 'files.info.unavailable'
		return
	}
	info.mode = u32(stat.st_mode)
	info.size = u64(stat.st_size)
	info.modified = i64(stat.st_mtime)
	info.accessed = i64(stat.st_atime)
	info.changed = i64(stat.st_ctime)
	info.permissions = files_info_permissions(info.mode)
	uid := u32(stat.st_uid).str()
	gid := u32(stat.st_gid).str()
	info.owner = '${uid} / ${gid}'
	unsafe {
		uid.free()
		gid.free()
	}
	if info.mode & u32(C.S_IFMT) == u32(C.S_IFLNK) {
		mut target := [4096]u8{}
		length := C.readlink(&char(path.str), &char(&target[0]), usize(target.len))
		info.link_target = if length >= 0 && length < target.len {
			unsafe { tos(&target[0], int(length)) }.clone()
		} else {
			tr('files.info.unavailable').clone()
		}
	}
	info.relabel()
}

fn (mut info FilesInfoPanel) relabel() {
	unsafe {
		info.kind_text.free()
		info.size_text.free()
		info.modified_text.free()
		info.accessed_text.free()
		info.changed_text.free()
	}
	kind := info.mode & u32(C.S_IFMT)
	info.kind_text = if kind == u32(C.S_IFLNK) {
		tr('files.info.symbolic_link').clone()
	} else if kind == u32(C.S_IFDIR) || kind == u32(C.S_IFREG) {
		files_list_kind_text(info.name, kind == u32(C.S_IFDIR))
	} else {
		tr('files.info.special_file').clone()
	}
	info.size_text = human_size(info.size)
	info.modified_text = files_list_modified_text(info.modified, info.tz_offset_seconds)
	info.accessed_text = files_list_modified_text(info.accessed, info.tz_offset_seconds)
	info.changed_text = files_list_modified_text(info.changed, info.tz_offset_seconds)
	info.language = desktop_language
}

fn files_info_browser_selection(browser &FileBrowser) string {
	if browser.selected_row >= 0 && browser.selected_row < browser.entries.len {
		return join_path(browser.path, browser.entries[browser.selected_row].name)
	}
	return browser.path.clone()
}

fn (a &FileBrowserApp) info_selected_path() string {
	if a.view_mode == .commander {
		return files_info_browser_selection(if a.active_pane == 0 {
			&a.dual_left
		} else {
			&a.dual_right
		})
	}
	if a.view_mode == .columns && a.columns.len > 0 {
		column := a.columns.last()
		if column.selected_row >= 0 && column.selected_row < column.browser.entries.len {
			return join_path(column.browser.path, column.browser.entries[column.selected_row].name)
		}
		return column.browser.path.clone()
	}
	return files_info_browser_selection(&a.browser)
}

fn (mut a FileBrowserApp) open_info() {
	path := a.info_selected_path()
	a.info.read(path, a.tz_offset_seconds)
	unsafe { path.free() }
	a.search_focused = false
	a.path_drag = false
	a.horizontal_drag = false
	a.vertical_drag_id = -2
}

// Ctrl-G is distinct from Tab on a POSIX console. Enhanced keyboards can also
// send Ctrl-I / Cmd-I without confusing the commander's pane-switching Tab.
fn (mut a FileBrowserApp) info_key_input(input string) bool {
	trigger := input == '\x07' || input == '\x1b[105;5u' || input == '\x1b[105;9u'
	if a.info.open {
		if trigger || input == '\x1b' { a.info.close() }
		return true
	}
	if trigger {
		a.open_info()
		return true
	}
	return false
}

fn files_info_row(mut rows []ui2.Element, key string, value string, y int, width int) {
	rows << ui2.label('', tr(key), ui2.rect(16, f64(y), 140, 28), ui2.TextStyle{
		color: body_muted
		size:  12
	})
	rows << ui2.Element{
		...ui2.label('', value, ui2.rect(160, f64(y), f64(width - 178), 28), ui2.TextStyle{
			color: body_text
			size:  12
		})
		tooltip: value
	}
}

fn (mut a FileBrowserApp) build_info_overlay(mut children []ui2.Element, width int, height int) {
	if !a.info.open { return }
	if a.info.error_key.len == 0 && a.info.language != desktop_language { a.info.relabel() }
	panel_width := if width > 552 { 520 } else { width - 32 }
	panel_height := if a.info.link_target.len > 0 { 382 } else { 350 }
	x := (width - panel_width) / 2
	y := if height > panel_height + 32 { (height - panel_height) / 2 } else { 16 }
	mut rows := frame_elements(22)
	rows << ui2.label('', tr('files.info.title'), ui2.rect(16, 12, f64(panel_width - 120), 28),
		ui2.TextStyle{ color: body_heading, size: 18, bold: true })
	rows << ui2.button(files_action_info_close, tr('files.info.close'),
		ui2.rect(f64(panel_width - 96), 12, 80, 28), ui2.BoxStyle{ bg: body_panel, radius: 5 },
		ui2.TextStyle{ color: body_text, size: 12, align: .center })
	rows << ui2.Element{
		...ui2.label('', a.info.path, ui2.rect(16, 52, f64(panel_width - 32), 40),
			ui2.TextStyle{ color: body_text, size: 12, lines: 2 })
		tooltip: a.info.path
	}
	if a.info.error_key.len > 0 {
		rows << ui2.label('', tr(a.info.error_key), ui2.rect(16, 100, f64(panel_width - 32), 40),
			ui2.TextStyle{ color: files_error, size: 13, lines: 2 })
	} else {
		files_info_row(mut rows, 'files.info.kind', a.info.kind_text, 98, panel_width)
		files_info_row(mut rows, 'files.info.size', a.info.size_text, 130, panel_width)
		files_info_row(mut rows, 'files.info.permissions', a.info.permissions, 162, panel_width)
		files_info_row(mut rows, 'files.info.owner', a.info.owner, 194, panel_width)
		files_info_row(mut rows, 'files.info.modified', a.info.modified_text, 226, panel_width)
		files_info_row(mut rows, 'files.info.accessed', a.info.accessed_text, 258, panel_width)
		files_info_row(mut rows, 'files.info.changed', a.info.changed_text, 290, panel_width)
		if a.info.link_target.len > 0 {
			files_info_row(mut rows, 'files.info.target', a.info.link_target, 322, panel_width)
		}
	}
	// The full-window blocker receives clicks outside the panel and prevents
	// directory rows from navigating while their metadata is being read.
	children << ui2.clickable_view('files.info.blocker', ui2.rect(0, 0, f64(width), f64(height)),
		ui2.BoxStyle{ transparent: true }, [])
	children << ui2.view('files.info.panel', ui2.rect(f64(x), f64(y), f64(panel_width), f64(panel_height)),
		ui2.BoxStyle{
			bg:            app_surface
			radius:        8
			border_color:  body_rule
			border_top:    1
			border_bottom: 1
			border_left:   1
			border_right:  1
		}, rows)
}
