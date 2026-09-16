// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// A file browser, built into the desktop.
//
// Unlike the calculator it is not a ui2 example but Vinix's own, and it reads
// a real filesystem: the listing comes from the kernel's getdents64 through
// musl's readdir, and each entry is stat'd for its size. It satisfies the same
// NativeApp interface a ui2 application does, so its process speaks the same
// compositor protocol and the window manager knows nothing about files.
module main

import ui2

// Longer than any name the kernel's Dirent can hold, so a listing never
// truncates one.
const max_name_len = 256

// A directory with more entries than this is listed no further. Vinix has no
// directory that large, and the cap keeps one pathological read from stalling
// the compositor for a whole frame.
const max_entries = 4096

struct FileEntry {
mut:
	name   string
	is_dir bool
	size   u64
	// Cached because these two strings are stable until a new directory is
	// read, while the element tree is rebuilt whenever desktop state changes.
	row_action string
	size_text  string
}

// FileBrowser is the model: where it is, what is there, and how far down the
// list has been scrolled.
struct FileBrowser {
mut:
	path    string = '/'
	entries []FileEntry
	scroll  int
	error   string
	// Row the pointer is over, or -1. Kept here rather than in the desktop's
	// hover state because rows are the application's, not the chrome's.
	hover_row int = -1
}

// join builds a child path without the doubled slash that string concatenation
// would give at the root.
fn join_path(dir string, name string) string {
	if dir.ends_with('/') {
		return dir + name
	}
	return '${dir}/${name}'
}

fn parent_path(path string) string {
	trimmed := path.trim_right('/')
	index := trimmed.last_index('/') or { return '/' }
	if index == 0 {
		return '/'
	}
	return trimmed[..index]
}

fn file_path_name(path string) string {
	if path == '/' {
		return path
	}
	index := path.last_index('/') or { return path }
	if index + 1 >= path.len {
		return path
	}
	return path[index + 1..]
}

// read_file_entries is shared by the list and Miller-column views. The action
// prefix is part of the cached row ids, so every visible column can route a
// click without allocating an action string on each compositor rebuild.
fn read_file_entries(path string, action_prefix string) ?[]FileEntry {
	dir := desktop_opendir(path)
	if dir == unsafe { nil } {
		return none
	}

	mut entries := []FileEntry{}
	unsafe { entries.flags |= .noslices }
	mut buffer := [max_name_len]u8{}
	mut names := unsafe { (&buffer[0]).vbytes(buffer.len) }
	for entries.len < max_entries {
		if !desktop_readdir(dir, mut names) {
			break
		}
		name := unsafe { cstring_to_vstring(&char(&buffer[0])) }
		// `.` says nothing, and `..` is the Up button's job.
		if name == '.' || name == '..' {
			unsafe { name.free() }
			continue
		}
		mut size := u64(0)
		mut is_dir := false
		full := join_path(path, name)
		if info := desktop_stat(full) {
			size = info.size
			is_dir = info.is_dir
		}
		unsafe { full.free() }
		// Unreadable entries remain visible, with unknown type and size.
		entries << FileEntry{
			name: name
			is_dir: is_dir
			size: size
		}
	}
	desktop_closedir(dir)

	// Directories first, then by name — the order a listing is read in is
	// whatever the filesystem happens to store, which is no order at all.
	entries.sort_with_compare(fn (a &FileEntry, b &FileEntry) int {
		if a.is_dir != b.is_dir {
			return if a.is_dir { -1 } else { 1 }
		}
		return compare_strings(a.name, b.name)
	})
	prepare_file_rows(mut entries, action_prefix)
	return entries
}

// read replaces the listing with the contents of `path`. A directory it cannot
// open leaves the browser where it was and says so, rather than emptying the
// window and looking like the directory is empty.
fn (mut b FileBrowser) read(path string) {
	entries := read_file_entries(path, files_action_row) or {
		unsafe { b.error.free() }
		b.error = 'cannot open ${path}'
		return
	}

	b.free_entries()
	unsafe {
		b.path.free()
		b.error.free()
	}
	b.path = path
	b.entries = entries
	b.scroll = 0
	b.error = ''
	b.hover_row = -1
}

fn prepare_file_rows(mut entries []FileEntry, action_prefix string) {
	for index in 0 .. entries.len {
		if entries[index].row_action.len == 0 {
			index_text := index.str()
			entries[index].row_action = action_prefix + index_text
			unsafe { index_text.free() }
		}
		if !entries[index].is_dir && entries[index].size_text.len == 0 {
			entries[index].size_text = human_size(entries[index].size)
		}
	}
}

fn (mut b FileBrowser) free_entries() {
	for index in 0 .. b.entries.len {
		unsafe {
			b.entries[index].name.free()
			b.entries[index].row_action.free()
			b.entries[index].size_text.free()
		}
	}
	if b.entries.cap > 0 {
		unsafe { b.entries.free() }
	}
}

fn (mut b FileBrowser) enter(index int) {
	if index < 0 || index >= b.entries.len {
		return
	}
	entry := b.entries[index]
	if !entry.is_dir {
		return
	}
	b.read(join_path(b.path, entry.name))
}

fn (mut b FileBrowser) go_up() {
	if b.path == '/' {
		return
	}
	b.read(parent_path(b.path))
}

// human_size keeps a listing's last column narrow. Sizes are shown to three
// significant figures at most, which is as much as anyone reads at a glance.
fn human_size(size u64) string {
	if size < 1024 {
		bytes := size.str()
		text := '${bytes} B'
		unsafe { bytes.free() }
		return text
	}
	mut value := f64(size) / 1024.0
	mut unit := 0
	for value >= 1024.0 && unit + 1 < file_size_units.len {
		value /= 1024.0
		unit++
	}
	if value < 10.0 {
		tenths := int(value * 10.0 + 0.5)
		whole := (tenths / 10).str()
		fraction := (tenths % 10).str()
		text := '${whole}.${fraction} ${file_size_units[unit]}'
		unsafe {
			whole.free()
			fraction.free()
		}
		return text
	}
	whole := int(value).str()
	text := '${whole} ${file_size_units[unit]}'
	unsafe { whole.free() }
	return text
}

const file_size_units = ['KB', 'MB', 'GB', 'TB']

// ── The native application ────────────────────────────────────────

const files_action_up = 'files.up'
const files_action_row = 'files.row.'
const files_action_scroll_up = 'files.scroll.up'
const files_action_scroll_down = 'files.scroll.down'
const files_action_view_toggle = 'files.view.toggle'
const files_action_column_row = 'files.column.row.'
const files_action_column_scroll_up = 'files.column.scroll.up.'
const files_action_column_scroll_down = 'files.column.scroll.down.'

const files_row_height = 24
const files_header_height = 38
const files_padding = 10
const files_column_header_height = 26
const files_column_min_width = 200

enum FilesViewMode {
	list
	columns
}

// One retained directory listing in Miller-column mode. A stable id, rather
// than the array position, is embedded in every row action so truncating the
// columns to follow another branch never invalidates the remaining actions.
struct MillerColumn {
mut:
	id                 int
	browser            FileBrowser
	selected_row       int = -1
	scroll_up_action   string
	scroll_down_action string
}

fn (mut c MillerColumn) release() {
	c.browser.free_entries()
	unsafe {
		c.browser.path.free()
		c.browser.error.free()
		c.scroll_up_action.free()
		c.scroll_down_action.free()
	}
}

struct FileBrowserApp {
mut:
	browser FileBrowser
	// Rows the window last had space for, so scrolling can clamp against the
	// window as it actually is rather than as it was when it opened.
	visible_rows int = 1
	view_mode FilesViewMode
	columns []MillerColumn
	next_column_id int = 1
}

fn open_files(mut _ Desktop) !NativeApp {
	mut app := &FileBrowserApp{}
	// Open on the home directory, the way every file manager does. It is also
	// the only writable, persistent part of this machine -- the rest of the
	// tree is the immutable system image -- so it is where a file the user
	// saves or edits actually is. Up still reaches `/`.
	app.browser.read(desktop_home)
	if app.browser.error != '' {
		// A system without the home directory is still browsable from the root.
		unsafe { app.browser.error.free() }
		app.browser.error = ''
		app.browser.read('/')
	}
	if app.browser.error != '' {
		return error(app.browser.error)
	}
	return app
}

fn (mut a FileBrowserApp) new_miller_column(path string) MillerColumn {
	id := a.next_column_id
	a.next_column_id++
	id_text := id.str()
	row_prefix := '${files_action_column_row}${id_text}.'
	scroll_up := files_action_column_scroll_up + id_text
	scroll_down := files_action_column_scroll_down + id_text
	entries := read_file_entries(path, row_prefix) or {
		error_text := 'cannot open ${path}'
		unsafe {
			id_text.free()
			row_prefix.free()
		}
		return MillerColumn{
			id: id
			browser: FileBrowser{
				path: path
				error: error_text
			}
			scroll_up_action: scroll_up
			scroll_down_action: scroll_down
		}
	}
	unsafe {
		id_text.free()
		row_prefix.free()
	}
	return MillerColumn{
		id: id
		browser: FileBrowser{
			path: path
			entries: entries
		}
		scroll_up_action: scroll_up
		scroll_down_action: scroll_down
	}
}

fn (mut a FileBrowserApp) free_miller_columns_from(start int) {
	mut first := start
	if first < 0 {
		first = 0
	}
	if first >= a.columns.len {
		return
	}
	for index := a.columns.len - 1; index >= first; index-- {
		a.columns[index].release()
		a.columns.delete(index)
	}
}

fn (mut a FileBrowserApp) free_miller_columns() {
	a.free_miller_columns_from(0)
}

fn (mut a FileBrowserApp) find_miller_entry(column int, name string) int {
	if column < 0 || column >= a.columns.len {
		return -1
	}
	for index, entry in a.columns[column].browser.entries {
		if entry.is_dir && entry.name == name {
			return index
		}
	}
	return -1
}

// Entering column view starts with the current directory and, when possible,
// its parent. That gives the default two-column window useful context without
// rereading every ancestor on a deep path.
fn (mut a FileBrowserApp) reset_miller_columns(path string) {
	a.free_miller_columns()
	if path == '/' {
		a.columns << a.new_miller_column(path.clone())
		return
	}
	parent := parent_path(path)
	parent_owned := parent.clone()
	a.columns << a.new_miller_column(parent_owned)
	name := file_path_name(path)
	selected := a.find_miller_entry(0, name)
	if selected >= 0 {
		a.columns[0].selected_row = selected
	}
	a.columns << a.new_miller_column(path.clone())
}

fn (mut a FileBrowserApp) set_view_mode(mode FilesViewMode) {
	if mode == a.view_mode {
		return
	}
	if mode == .columns {
		a.reset_miller_columns(a.browser.path)
		a.view_mode = .columns
		return
	}
	if a.columns.len > 0 {
		path := a.columns.last().browser.path.clone()
		a.browser.read(path)
	}
	a.free_miller_columns()
	a.view_mode = .list
}

fn (a &FileBrowserApp) current_path() string {
	if a.view_mode == .columns && a.columns.len > 0 {
		return a.columns.last().browser.path
	}
	return a.browser.path
}

fn (mut a FileBrowserApp) go_up_miller() {
	if a.columns.len == 0 {
		a.reset_miller_columns(a.browser.path)
		return
	}
	if a.columns.len > 1 {
		a.free_miller_columns_from(a.columns.len - 1)
		a.columns[a.columns.len - 1].selected_row = -1
		return
	}
	path := a.columns[0].browser.path
	if path == '/' {
		return
	}
	parent := parent_path(path).clone()
	a.free_miller_columns()
	a.columns << a.new_miller_column(parent)
}

fn (mut a FileBrowserApp) clamp_column_scroll(index int) {
	if index < 0 || index >= a.columns.len {
		return
	}
	max_scroll := a.columns[index].browser.entries.len - a.visible_rows
	if a.columns[index].browser.scroll > max_scroll {
		a.columns[index].browser.scroll = max_scroll
	}
	if a.columns[index].browser.scroll < 0 {
		a.columns[index].browser.scroll = 0
	}
}

fn (mut a FileBrowserApp) select_miller_row(column_id int, row int) {
	mut column_index := -1
	for index, column in a.columns {
		if column.id == column_id {
			column_index = index
			break
		}
	}
	if column_index < 0 || row < 0 || row >= a.columns[column_index].browser.entries.len {
		return
	}

	entry := a.columns[column_index].browser.entries[row]
	a.columns[column_index].selected_row = row
	a.free_miller_columns_from(column_index + 1)
	if !entry.is_dir {
		return
	}
	child := join_path(a.columns[column_index].browser.path, entry.name)
	a.columns << a.new_miller_column(child)
}

struct MillerRowAction {
	column_id int
	row       int
}

fn parse_miller_row_action(event_id string) ?MillerRowAction {
	if !event_id.starts_with(files_action_column_row) {
		return none
	}
	rest := event_id[files_action_column_row.len..]
	dot := rest.index('.') or { return none }
	column_id := rest[..dot].int()
	row := rest[dot + 1..].int()
	if column_id <= 0 || row < 0 {
		return none
	}
	return MillerRowAction{
		column_id: column_id
		row: row
	}
}

fn (mut a FileBrowserApp) build(size ui2.Rect) !ui2.Element {
	prepare_file_rows(mut a.browser.entries, files_action_row)
	width := int(size.width)
	height := int(size.height)
	inner := width - 2 * files_padding

	list_top := files_header_height
	content_header := if a.view_mode == .columns { files_column_header_height } else { 0 }
	list_height := height - list_top - content_header - files_padding
	a.visible_rows = if list_height > files_row_height {
		list_height / files_row_height
	} else {
		1
	}
	if a.view_mode == .list {
		a.clamp_scroll()
	}

	mut slot_count := 1
	if a.view_mode == .columns && width >= files_column_min_width {
		slot_count = width / files_column_min_width
		if slot_count < 1 {
			slot_count = 1
		}
	}
	mut rendered_columns := if a.view_mode == .columns { a.columns.len } else { 1 }
	if rendered_columns > slot_count {
		rendered_columns = slot_count
	}
	if rendered_columns < 1 {
		rendered_columns = 1
	}
	mut children := frame_elements(a.visible_rows * rendered_columns + 16)

	// Header: where we are, the way back out, and the optional column view.
	up_width := 40
	view_width := 64
	view_x := width - files_padding - view_width
	children << ui2.button(files_action_up, 'Up', ui2.rect(f64(files_padding), 8, f64(up_width), 22), ui2.BoxStyle{
		bg: if a.current_path() == '/' { files_up_disabled } else { files_up }
		radius: 5
	}, ui2.TextStyle{
		color: if a.current_path() == '/' { body_muted } else { app_on_accent }
		size: 12
		align: .center
	})
	children << ui2.button(files_action_view_toggle, if a.view_mode == .list { 'Columns' } else { 'List' }, ui2.rect(f64(view_x), 8, f64(view_width), 22), ui2.BoxStyle{
		bg: files_up
		radius: 5
	}, ui2.TextStyle{
		color: app_on_accent
		size: 11
		align: .center
	})
	path_left := files_padding + up_width + 10
	path_right := view_x - 8
	children << ui2.label('', a.current_path(), ui2.rect(f64(path_left), 8, f64(path_right - path_left), 22), ui2.TextStyle{
		color: body_heading
		size: 13
		bold: true
	})
	children << ui2.view('', ui2.rect(0, f64(list_top - 1), f64(width), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])

	if a.view_mode == .columns {
		if a.columns.len == 0 {
			a.reset_miller_columns(a.browser.path)
		}
		return a.build_miller_columns(width, height, list_top, slot_count, mut children)
	}

	if a.browser.error != '' {
		children << ui2.label('', a.browser.error, ui2.rect(f64(files_padding), f64(list_top + 8), f64(inner), 20), ui2.TextStyle{
			color: files_error
			size: 13
		})
		return ui2.screen(app_surface, children)
	}

	if a.browser.entries.len == 0 {
		children << ui2.label('', 'This directory is empty.', ui2.rect(f64(files_padding), f64(list_top + 8), f64(inner), 20), ui2.TextStyle{
			color: body_muted
			size: 13
		})
		return ui2.screen(app_surface, children)
	}

	// Rows.
	mut row := 0
	for index := a.browser.scroll; index < a.browser.entries.len && row < a.visible_rows; index++ {
		entry := &a.browser.entries[index]
		y := list_top + row * files_row_height
		hovered := a.browser.hover_row == index
		mut row_children := frame_elements(3)
		row_children << ui2.button_with_image('', '', if entry.is_dir {
			'builtin:folder'
		} else {
			'builtin:file'
		}, ui2.rect(f64(files_padding), 4, 16, 16), ui2.BoxStyle{
			transparent: true
		}, ui2.TextStyle{
			color: if entry.is_dir { files_folder_icon } else { files_file_icon }
		})
		row_children << ui2.label('', entry.name, ui2.rect(f64(files_padding + 24), 0, f64(inner - 24 - 72), f64(files_row_height)), ui2.TextStyle{
			color: if entry.is_dir { body_heading } else { body_text }
			size: 13
		})
		row_children << ui2.label('', entry.size_text, ui2.rect(f64(width - files_padding - 70), 0, 70, f64(files_row_height)), ui2.TextStyle{
			color: body_muted
			size: 11
			align: .right
		})
		children << ui2.clickable_view(entry.row_action, ui2.rect(0, f64(y), f64(width), f64(files_row_height)), ui2.BoxStyle{
			bg: files_row_hover
			transparent: !hovered
		}, row_children)
		row++
	}

	// Scroll buttons, only when there is somewhere to scroll to. A wheel would
	// be nicer, but a button works with the one thing every pointer has.
	if a.browser.entries.len > a.visible_rows {
		button_size := 18
		right := view_x - 8 - button_size
		children << ui2.button(files_action_scroll_up, '-', ui2.rect(f64(right - button_size - 4), 8, f64(button_size), 22), ui2.BoxStyle{
			bg: files_up
			radius: 5
		}, ui2.TextStyle{
			color: app_on_accent
			size: 12
			align: .center
		})
		children << ui2.button(files_action_scroll_down, '+', ui2.rect(f64(right), 8, f64(button_size), 22), ui2.BoxStyle{
			bg: files_up
			radius: 5
		}, ui2.TextStyle{
			color: app_on_accent
			size: 12
			align: .center
		})
	}

	return ui2.screen(app_surface, children)
}

fn (mut a FileBrowserApp) build_miller_columns(width int, height int, list_top int, slot_count int, mut children []ui2.Element) !ui2.Element {
	mut slots := slot_count
	if slots < 1 {
		slots = 1
	}
	column_width := width / slots
	mut start := a.columns.len - slots
	if start < 0 {
		start = 0
	}
	mut slot := 0
	for column_index := start; column_index < a.columns.len && slot < slots; column_index++ {
		a.clamp_column_scroll(column_index)
		column := &a.columns[column_index]
		x := slot * column_width
		mut this_width := column_width
		if slot + 1 == slots {
			this_width = width - x
		}
		column_name := file_path_name(column.browser.path)
		children << ui2.label('', column_name, ui2.rect(f64(x + files_padding), f64(list_top + 2), f64(this_width - 2 * files_padding - 46), 22), ui2.TextStyle{
			color: body_heading
			size: 12
			bold: true
		})
		if column.browser.entries.len > a.visible_rows {
			button_size := 18
			right := x + this_width - files_padding - button_size
			children << ui2.button(column.scroll_up_action, '-', ui2.rect(f64(right - button_size - 4), f64(list_top + 2), f64(button_size), 21), ui2.BoxStyle{
				bg: files_up
				radius: 5
			}, ui2.TextStyle{
				color: app_on_accent
				size: 12
				align: .center
			})
			children << ui2.button(column.scroll_down_action, '+', ui2.rect(f64(right), f64(list_top + 2), f64(button_size), 21), ui2.BoxStyle{
				bg: files_up
				radius: 5
			}, ui2.TextStyle{
				color: app_on_accent
				size: 12
				align: .center
			})
		}

		rows_top := list_top + files_column_header_height
		if column.browser.error != '' {
			children << ui2.label('', column.browser.error, ui2.rect(f64(x + files_padding), f64(rows_top + 8), f64(this_width - 2 * files_padding), 36), ui2.TextStyle{
				color: files_error
				size: 12
				lines: 2
			})
		} else if column.browser.entries.len == 0 {
			children << ui2.label('', 'Empty', ui2.rect(f64(x + files_padding), f64(rows_top + 8), f64(this_width - 2 * files_padding), 20), ui2.TextStyle{
				color: body_muted
				size: 12
			})
		} else {
			mut row_slot := 0
			for entry_index := column.browser.scroll; entry_index < column.browser.entries.len && row_slot < a.visible_rows; entry_index++ {
				entry := &column.browser.entries[entry_index]
				y := rows_top + row_slot * files_row_height
				selected := column.selected_row == entry_index
				mut row_children := frame_elements(3)
				row_children << ui2.button_with_image('', '', if entry.is_dir {
					'builtin:folder'
				} else {
					'builtin:file'
				}, ui2.rect(f64(files_padding), 4, 16, 16), ui2.BoxStyle{
					transparent: true
				}, ui2.TextStyle{
					color: if entry.is_dir { files_folder_icon } else { files_file_icon }
				})
				row_children << ui2.label('', entry.name, ui2.rect(f64(files_padding + 24), 0, f64(this_width - 2 * files_padding - 24 - 34), f64(files_row_height)), ui2.TextStyle{
					color: if entry.is_dir { body_heading } else { body_text }
					size: 12
				})
				row_children << ui2.label('', if entry.is_dir { '>' } else { entry.size_text }, ui2.rect(f64(this_width - files_padding - 30), 0, 30, f64(files_row_height)), ui2.TextStyle{
					color: body_muted
					size: 11
					align: .right
				})
				children << ui2.clickable_view(entry.row_action, ui2.rect(f64(x), f64(y), f64(this_width), f64(files_row_height)), ui2.BoxStyle{
					bg: files_row_hover
					transparent: !selected
				}, row_children)
				row_slot++
			}
		}
		if slot > 0 {
			children << ui2.view('', ui2.rect(f64(x), f64(list_top), 1, f64(height - list_top)), ui2.BoxStyle{
				bg: body_rule
			}, [])
		}
		slot++
	}
	return ui2.screen(app_surface, children)
}

fn (mut a FileBrowserApp) clamp_scroll() {
	max_scroll := a.browser.entries.len - a.visible_rows
	if a.browser.scroll > max_scroll {
		a.browser.scroll = max_scroll
	}
	if a.browser.scroll < 0 {
		a.browser.scroll = 0
	}
}

fn (mut a FileBrowserApp) handle(event_id string) ! {
	match event_id {
		files_action_up {
			if a.view_mode == .columns {
				a.go_up_miller()
			} else {
				a.browser.go_up()
			}
			return
		}
		files_action_view_toggle {
			a.set_view_mode(if a.view_mode == .list { .columns } else { .list })
			return
		}
		files_action_scroll_up {
			a.browser.scroll -= a.visible_rows
			a.clamp_scroll()
			return
		}
		files_action_scroll_down {
			a.browser.scroll += a.visible_rows
			a.clamp_scroll()
			return
		}
		else {}
	}
	if row := parse_miller_row_action(event_id) {
		a.select_miller_row(row.column_id, row.row)
		return
	}
	if event_id.starts_with(files_action_column_scroll_up) {
		id := event_id[files_action_column_scroll_up.len..].int()
		for index, column in a.columns {
			if column.id == id {
				a.columns[index].browser.scroll -= a.visible_rows
				a.clamp_column_scroll(index)
				return
			}
		}
	}
	if event_id.starts_with(files_action_column_scroll_down) {
		id := event_id[files_action_column_scroll_down.len..].int()
		for index, column in a.columns {
			if column.id == id {
				a.columns[index].browser.scroll += a.visible_rows
				a.clamp_column_scroll(index)
				return
			}
		}
	}
	if event_id.starts_with(files_action_row) {
		a.browser.enter(event_id[files_action_row.len..].int())
	}
}
