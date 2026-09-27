// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
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
	selected_row int = -1
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
	b.selected_row = -1
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
	// parent_path may be a slice of b.path. read() takes ownership of its
	// argument and releases the old b.path, so passing that slice directly
	// leaves the new path pointing into freed storage.
	b.read(parent_path(b.path).clone())
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
const files_action_view_list = 'files.view.list'
const files_action_view_columns = 'files.view.columns'
const files_action_column_row = 'files.column.row.'
const files_action_scrollbar = 'files.scrollbar'

const files_row_height = 24
const files_header_height = 38
const files_padding = 10
const files_column_min_width = 200
const files_view_button_width = 28
const files_path_left = 60
const files_path_top = 8
const files_path_height = 22
const files_horizontal_bar_height = 20
const files_scrollbar_width = 8
const files_scrollbar_min_thumb = 20
const files_sidebar_width = 152
const files_sidebar_min_window_width = 360
const files_sidebar_row_height = 29

struct FilesLocation {
	title  string
	path   string
	icon   string
	action string
}

const files_locations = [
	FilesLocation{ title: 'Home', path: desktop_home, icon: 'builtin:home', action: 'files.location.home' },
	FilesLocation{ title: 'Desktop', path: desktop_directory, icon: 'builtin:desktop', action: 'files.location.desktop' },
	FilesLocation{ title: 'Documents', path: '${desktop_home}/Documents', icon: 'builtin:documents', action: 'files.location.documents' },
	FilesLocation{ title: 'Downloads', path: '${desktop_home}/Downloads', icon: 'builtin:downloads', action: 'files.location.downloads' },
	FilesLocation{ title: 'Pictures', path: '${desktop_home}/Pictures', icon: 'builtin:folder', action: 'files.location.pictures' },
	FilesLocation{ title: 'Music', path: '${desktop_home}/Music', icon: 'builtin:folder', action: 'files.location.music' },
	FilesLocation{ title: 'Computer', path: '/', icon: 'builtin:drive', action: 'files.location.computer' },
]

fn files_content_left(width int) int {
	return if width >= files_sidebar_min_window_width { files_sidebar_width } else { 0 }
}

fn files_path_width(width int) int {
	right := width - files_padding - 2 * files_view_button_width - 2 - 8
	return if right > files_path_left { right - files_path_left } else { 1 }
}

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
}

fn (mut c MillerColumn) release() {
	c.browser.free_entries()
	unsafe {
		c.browser.path.free()
		c.browser.error.free()
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
	column_offset int
	column_width int
	viewport_width int
	rows_top int
	rows_height int
	reveal_last_column bool
	horizontal_drag bool
	horizontal_drag_x int
	horizontal_drag_offset int
	vertical_drag_id int = -2 // -2: none, -1: list, otherwise a MillerColumn id
	vertical_drag_y int
	vertical_drag_scroll int
	path_offset int
	path_content_width int
	path_viewport_width int
	path_drag bool
	path_drag_x int
	path_drag_offset int
	reveal_path_end bool
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

// Rebuild the chain from the filesystem root to the current directory so a
// deep path has its full history available to the horizontal scrollbar.
fn (mut a FileBrowserApp) reset_miller_columns(path string) {
	a.free_miller_columns()
	a.column_offset = 0
	a.reveal_last_column = true
	a.reveal_path_end = true
	mut paths := []string{}
	mut ancestor := path.clone()
	for {
		paths << ancestor
		if ancestor == '/' {
			break
		}
		ancestor = parent_path(ancestor).clone()
	}
	for index := paths.len - 1; index >= 0; index-- {
		if a.columns.len > 0 {
			parent_index := a.columns.len - 1
			a.columns[parent_index].selected_row = a.find_miller_entry(parent_index,
				file_path_name(paths[index]))
		}
		// []string.free() releases its elements; columns keep separate copies.
		a.columns << a.new_miller_column(paths[index].clone())
	}
	unsafe { paths.free() }
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

fn (mut a FileBrowserApp) navigate_to(path string) {
	// read() takes ownership on success. Sidebar paths are shared constants.
	owned := path.clone()
	a.browser.read(owned)
	if a.browser.error != '' {
		unsafe { owned.free() }
		return
	}
	if a.view_mode == .columns {
		a.reset_miller_columns(path)
	}
}

fn (a &FileBrowserApp) sidebar(height int) ui2.Element {
	mut rows := frame_elements(files_locations.len + 3)
	rows << ui2.label('', 'Favorites', ui2.rect(14, 10, files_sidebar_width - 28, 20), ui2.TextStyle{
		color: body_muted
		size: 11
		bold: true
	})
	for index, location in files_locations {
		if index == files_locations.len - 1 {
			rows << ui2.label('', 'Locations', ui2.rect(14, 225, files_sidebar_width - 28, 20), ui2.TextStyle{
				color: body_muted
				size: 11
				bold: true
			})
		}
		y := if index == files_locations.len - 1 { 250 } else { 35 + index * files_sidebar_row_height }
		if y + files_sidebar_row_height > height {
			continue
		}
		selected := a.current_path() == location.path
		mut contents := frame_elements(2)
		contents << ui2.button_with_image('', '', location.icon, ui2.rect(10, 5, 18, 18), ui2.BoxStyle{
			transparent: true
		}, ui2.TextStyle{
			color: files_sidebar_icon
		})
		contents << ui2.label('', location.title, ui2.rect(37, 0, files_sidebar_width - 48, files_sidebar_row_height), ui2.TextStyle{
			color: body_text
			size: 12
		})
		rows << ui2.clickable_view(location.action, ui2.rect(6, f64(y), files_sidebar_width - 12, files_sidebar_row_height), ui2.BoxStyle{
			bg: files_sidebar_selected
			radius: 6
			transparent: !selected
		}, contents)
	}
	return ui2.clickable_view('files.sidebar', ui2.rect(0, files_header_height, files_sidebar_width, f64(height)), ui2.BoxStyle{
		bg: files_sidebar_bg
	}, rows)
}

fn (a &FileBrowserApp) screen_with_sidebar(width int, height int, mut children []ui2.Element) ui2.Element {
	content_left := files_content_left(width)
	if content_left > 0 {
		children << a.sidebar(height - files_header_height)
		children << ui2.view('', ui2.rect(f64(content_left), files_header_height, 1,
			f64(height - files_header_height)), ui2.BoxStyle{
			bg: body_rule
		}, [])
	}
	return ui2.screen(app_surface, children)
}

fn (mut a FileBrowserApp) go_up_miller() {
	if a.columns.len == 0 {
		a.reset_miller_columns(a.browser.path)
		return
	}
	if a.columns.len > 1 {
		a.free_miller_columns_from(a.columns.len - 1)
		a.columns[a.columns.len - 1].selected_row = -1
		a.reveal_path_end = true
		return
	}
	path := a.columns[0].browser.path
	if path == '/' {
		return
	}
	parent := parent_path(path).clone()
	a.free_miller_columns()
	a.columns << a.new_miller_column(parent)
	a.reveal_path_end = true
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
	a.reveal_last_column = true
	a.reveal_path_end = true
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

fn files_clamp(value int, maximum int) int {
	return if value < 0 { 0 } else if value > maximum { maximum } else { value }
}

// Returns the thumb's position and length within a track. The same geometry
// drives painting and pointer handling, so the visible thumb is the hit area.
fn files_scroll_thumb(track int, visible int, total int, offset int) (int, int) {
	if track <= 0 || total <= visible || visible <= 0 {
		return 0, 0
	}
	mut length := track * visible / total
	if length < files_scrollbar_min_thumb {
		length = files_scrollbar_min_thumb
	}
	if length > track {
		length = track
	}
	position := files_clamp(offset, total - visible) * (track - length) / (total - visible)
	return position, length
}

fn (a &FileBrowserApp) max_column_offset() int {
	content_width := a.columns.len * a.column_width
	return if content_width > a.viewport_width { content_width - a.viewport_width } else { 0 }
}

fn (a &FileBrowserApp) max_path_offset() int {
	return if a.path_content_width > a.path_viewport_width {
		a.path_content_width - a.path_viewport_width
	} else { 0 }
}

fn (a &FileBrowserApp) pointer_over_path(x int, y int) bool {
	return x >= files_path_left && x < files_path_left + a.path_viewport_width
		&& y >= files_path_top && y < files_path_top + files_path_height
}

fn (mut a FileBrowserApp) build(size ui2.Rect) !ui2.Element {
	prepare_file_rows(mut a.browser.entries, files_action_row)
	width := int(size.width)
	height := int(size.height)
	content_left := files_content_left(width)
	content_width := width - content_left
	inner := content_width - 2 * files_padding
	if a.view_mode == .columns && a.columns.len == 0 {
		a.reset_miller_columns(a.browser.path)
	}
	mut slot_count := 1
	if a.view_mode == .columns && content_width >= files_column_min_width {
		slot_count = content_width / files_column_min_width
	}
	a.viewport_width = content_width
	a.column_width = content_width / slot_count
	a.path_viewport_width = files_path_width(width)
	if a.view_mode == .columns {
		// The path is drawn untruncated inside a clipped strip. Give it a
		// conservative glyph width so even wide names fit its virtual label.
		path_pixels := a.current_path().len * 12
		visible_path := a.path_viewport_width
		a.path_content_width = if path_pixels > visible_path { path_pixels } else { visible_path }
		if a.reveal_path_end {
			a.path_offset = a.max_path_offset()
			a.reveal_path_end = false
		} else {
			a.path_offset = files_clamp(a.path_offset, a.max_path_offset())
		}
	}
	column_max := a.max_column_offset()
	if a.reveal_last_column {
		a.column_offset = column_max
		a.reveal_last_column = false
	} else {
		a.column_offset = files_clamp(a.column_offset, column_max)
	}
	a.rows_top = files_header_height
	bar_height := if a.view_mode == .columns && column_max > 0 { files_horizontal_bar_height } else { 0 }
	a.rows_height = height - a.rows_top - bar_height - files_padding
	if a.rows_height < files_row_height {
		a.rows_height = files_row_height
	}
	a.visible_rows = a.rows_height / files_row_height
	if a.visible_rows < 1 {
		a.visible_rows = 1
	}
	if a.view_mode == .list {
		a.clamp_scroll()
	}
	mut children := frame_elements(a.visible_rows * (slot_count + 2) + 18)

	// Header: where we are, the way back out, and the two view choices.
	view_button_gap := 2
	view_x := width - files_padding - 2 * files_view_button_width - view_button_gap
	children << ui2.button(files_action_up, 'Up', ui2.rect(f64(files_padding), files_path_top, 40, files_path_height), ui2.BoxStyle{
		bg: if a.current_path() == '/' { files_up_disabled } else { files_up }
		radius: 5
	}, ui2.TextStyle{
		color: if a.current_path() == '/' { body_muted } else { app_on_accent }
		size: 12
		align: .center
	})
	children << files_view_button(files_action_view_list, 'List view', 'builtin:list_view',
		view_x, a.view_mode == .list)
	children << files_view_button(files_action_view_columns, 'Column view', 'builtin:column_view',
		view_x + files_view_button_width + view_button_gap, a.view_mode == .columns)
	if a.view_mode == .list {
		children << ui2.label('', a.current_path(), ui2.rect(files_path_left, files_path_top,
			f64(a.path_viewport_width), files_path_height), ui2.TextStyle{
			color: body_heading
			size: 13
			bold: true
		})
	} else {
		// The path shares the toolbar with Up and the view buttons. Navigation
		// reveals its end; dragging or wheeling reaches earlier segments.
		mut path_children := frame_elements(1)
		path_children << ui2.label('', a.current_path(), ui2.rect(f64(-a.path_offset), 0,
			f64(a.path_content_width), files_path_height), ui2.TextStyle{
			color: body_heading
			size: 13
			bold: true
		})
		children << ui2.Element{
			...ui2.view('', ui2.rect(files_path_left, files_path_top,
				f64(a.path_viewport_width), files_path_height), ui2.BoxStyle{
				transparent: true
			}, path_children)
			tooltip: a.current_path()
		}
	}
	children << ui2.view('', ui2.rect(0, f64(a.rows_top - 1), f64(width), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])

	if a.view_mode == .columns {
		return a.build_miller_columns(width, height, mut children)
	}

	if a.browser.error != '' {
		children << ui2.label('', a.browser.error, ui2.rect(f64(content_left + files_padding), f64(a.rows_top + 8), f64(inner), 20), ui2.TextStyle{
			color: files_error
			size: 13
		})
		return a.screen_with_sidebar(width, height, mut children)
	}

	if a.browser.entries.len == 0 {
		children << ui2.label('', 'This directory is empty.', ui2.rect(f64(content_left + files_padding), f64(a.rows_top + 8), f64(inner), 20), ui2.TextStyle{
			color: body_muted
			size: 13
		})
		return a.screen_with_sidebar(width, height, mut children)
	}

	// Rows.
	mut row := 0
	for index := a.browser.scroll; index < a.browser.entries.len && row < a.visible_rows; index++ {
		entry := &a.browser.entries[index]
		y := a.rows_top + row * files_row_height
		hovered := a.browser.hover_row == index || a.browser.selected_row == index
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
		row_children << ui2.label('', entry.size_text, ui2.rect(f64(content_width - files_padding - 70), 0, 70, f64(files_row_height)), ui2.TextStyle{
			color: body_muted
			size: 11
			align: .right
		})
		children << ui2.clickable_view(entry.row_action, ui2.rect(f64(content_left), f64(y), f64(content_width), f64(files_row_height)), ui2.BoxStyle{
			bg: files_row_hover
			transparent: !hovered
		}, row_children)
		row++
	}

	if a.browser.entries.len > a.visible_rows {
		children << files_vertical_scrollbar(width - files_scrollbar_width - 2, a.rows_top,
			a.rows_height, a.visible_rows, a.browser.entries.len, a.browser.scroll)
	}

	return a.screen_with_sidebar(width, height, mut children)
}

fn files_view_button(action string, label string, icon string, x int, selected bool) ui2.Element {
	return ui2.Element{
		...ui2.button_with_image(action, '', icon, ui2.rect(f64(x), 8, files_view_button_width,
			22), ui2.BoxStyle{
			bg:     if selected { files_up } else { body_panel }
			radius: 5
		}, ui2.TextStyle{
			color: if selected { app_on_accent } else { body_text }
		})
		tooltip:             label
		accessibility_label: label
		accessibility_value: if selected { 'selected' } else { '' }
	}
}

fn files_vertical_scrollbar(x int, y int, height int, visible int, total int, scroll int) ui2.Element {
	position, thumb_height := files_scroll_thumb(height, visible, total, scroll)
	mut bar_children := frame_elements(1)
	bar_children << ui2.view('', ui2.rect(1, f64(position), 6, f64(thumb_height)), ui2.BoxStyle{
		bg: body_muted
		radius: 3
	}, [])
	return ui2.clickable_view(files_action_scrollbar, ui2.rect(f64(x), f64(y), files_scrollbar_width,
		f64(height)), ui2.BoxStyle{
		bg: body_rule
		radius: 4
	}, bar_children)
}

fn (mut a FileBrowserApp) build_miller_columns(width int, height int, mut children []ui2.Element) !ui2.Element {
	column_width := a.column_width
	content_left := width - a.viewport_width
	for column_index := 0; column_index < a.columns.len; column_index++ {
		local_x := column_index * column_width - a.column_offset
		if local_x + column_width <= 0 || local_x >= a.viewport_width {
			continue
		}
		x := content_left + local_x
		a.clamp_column_scroll(column_index)
		column := &a.columns[column_index]
		rows_top := a.rows_top
		if column.browser.error != '' {
			children << ui2.label('', column.browser.error, ui2.rect(f64(x + files_padding), f64(rows_top + 8), f64(column_width - 2 * files_padding), 36), ui2.TextStyle{
				color: files_error
				size: 12
				lines: 2
			})
		} else if column.browser.entries.len == 0 {
			children << ui2.label('', 'Empty', ui2.rect(f64(x + files_padding), f64(rows_top + 8), f64(column_width - 2 * files_padding), 20), ui2.TextStyle{
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
				row_children << ui2.label('', entry.name, ui2.rect(f64(files_padding + 24), 0, f64(column_width - 2 * files_padding - 24 - 34), f64(files_row_height)), ui2.TextStyle{
					color: if entry.is_dir { body_heading } else { body_text }
					size: 12
				})
				row_children << ui2.label('', if entry.is_dir { '>' } else { entry.size_text }, ui2.rect(f64(column_width - files_padding - 30), 0, 30, f64(files_row_height)), ui2.TextStyle{
					color: body_muted
					size: 11
					align: .right
				})
				children << ui2.clickable_view(entry.row_action, ui2.rect(f64(x), f64(y), f64(column_width), f64(files_row_height)), ui2.BoxStyle{
					bg: files_row_hover
					transparent: !selected
				}, row_children)
				row_slot++
			}
		}
		if column.browser.entries.len > a.visible_rows {
			children << files_vertical_scrollbar(x + column_width - files_scrollbar_width - 2,
				rows_top, a.rows_height, a.visible_rows, column.browser.entries.len,
				column.browser.scroll)
		}
		if column_index > 0 {
			children << ui2.view('', ui2.rect(f64(x), f64(rows_top), 1, f64(a.rows_height)), ui2.BoxStyle{
				bg: body_rule
			}, [])
		}
	}
	max_offset := a.max_column_offset()
	if max_offset > 0 {
		track_width := a.viewport_width - 2 * files_padding
		thumb_x, thumb_width := files_scroll_thumb(track_width, a.viewport_width,
			a.columns.len * column_width, a.column_offset)
		bar_y := height - files_horizontal_bar_height + 5
		children << ui2.view('', ui2.rect(f64(content_left + files_padding), f64(bar_y), f64(track_width), 8), ui2.BoxStyle{
			bg: body_rule
			radius: 4
		}, [])
		children << ui2.view('', ui2.rect(f64(content_left + files_padding + thumb_x), f64(bar_y),
			f64(thumb_width), 8), ui2.BoxStyle{
			bg: body_muted
			radius: 4
		}, [])
	}
	return a.screen_with_sidebar(width, height, mut children)
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

fn (mut a FileBrowserApp) scroll_at(x int, y int, steps int, width int) {
	content_left := width - a.viewport_width
	if steps == 0 {
		return
	}
	if a.view_mode == .columns && a.pointer_over_path(x, y) {
		a.path_offset = files_clamp(a.path_offset - steps * 48, a.max_path_offset())
		return
	}
	if x < content_left {
		return
	}
	if a.view_mode == .columns && y >= a.rows_top + a.rows_height {
		a.column_offset = files_clamp(a.column_offset - steps * a.column_width,
			a.max_column_offset())
		return
	}
	if y < a.rows_top || y >= a.rows_top + a.rows_height {
		return
	}
	if a.view_mode == .list {
		maximum := if a.browser.entries.len > a.visible_rows {
			a.browser.entries.len - a.visible_rows
		} else { 0 }
		a.browser.scroll = files_clamp(a.browser.scroll - steps * 2, maximum)
		return
	}
	if a.column_width <= 0 {
		return
	}
	index := (x - content_left + a.column_offset) / a.column_width
	if index < 0 || index >= a.columns.len {
		return
	}
	maximum := if a.columns[index].browser.entries.len > a.visible_rows {
		a.columns[index].browser.entries.len - a.visible_rows
	} else { 0 }
	a.columns[index].browser.scroll = files_clamp(a.columns[index].browser.scroll - steps * 2,
		maximum)
}

fn (mut a FileBrowserApp) begin_vertical_drag(id int, y int, total int, current int) {
	a.vertical_drag_id = id
	a.vertical_drag_y = y
	a.vertical_drag_scroll = current
	position, thumb := files_scroll_thumb(a.rows_height, a.visible_rows, total, current)
	if y < a.rows_top + position || y >= a.rows_top + position + thumb {
		maximum := total - a.visible_rows
		travel := a.rows_height - thumb
		if travel > 0 && maximum > 0 {
			a.vertical_drag_scroll = files_clamp((y - a.rows_top - thumb / 2) * maximum / travel,
				maximum)
			if id == -1 {
				a.browser.scroll = a.vertical_drag_scroll
			} else {
				for index, column in a.columns {
					if column.id == id {
						a.columns[index].browser.scroll = a.vertical_drag_scroll
						break
					}
				}
			}
		}
	}
}

fn (mut a FileBrowserApp) pointer_event(phase AppPointerPhase, button AppPointerButton, scroll int, x int, y int, width int, height int) {
	content_left := width - a.viewport_width
	if phase == .scroll {
		a.scroll_at(x, y, scroll, width)
		return
	}
	if phase == .up {
		a.path_drag = false
		a.horizontal_drag = false
		a.vertical_drag_id = -2
		return
	}
	if phase == .move {
		if a.path_drag {
			a.path_offset = files_clamp(a.path_drag_offset - (x - a.path_drag_x),
				a.max_path_offset())
		} else if a.horizontal_drag {
			maximum := a.max_column_offset()
			track := a.viewport_width - 2 * files_padding
			_, thumb := files_scroll_thumb(track, a.viewport_width, a.columns.len * a.column_width,
				a.column_offset)
			travel := track - thumb
			if travel > 0 {
				a.column_offset = files_clamp(a.horizontal_drag_offset + (x - a.horizontal_drag_x) * maximum / travel,
					maximum)
			}
		} else if a.vertical_drag_id != -2 {
			mut total := a.browser.entries.len
			if a.vertical_drag_id >= 0 {
				for column in a.columns {
					if column.id == a.vertical_drag_id {
						total = column.browser.entries.len
						break
					}
				}
			}
			_, thumb := files_scroll_thumb(a.rows_height, a.visible_rows, total,
				a.vertical_drag_scroll)
			travel := a.rows_height - thumb
			maximum := total - a.visible_rows
			if travel > 0 && maximum > 0 {
				next := files_clamp(a.vertical_drag_scroll + (y - a.vertical_drag_y) * maximum / travel,
					maximum)
				if a.vertical_drag_id == -1 {
					a.browser.scroll = next
				} else {
					for index, column in a.columns {
						if column.id == a.vertical_drag_id {
							a.columns[index].browser.scroll = next
							break
						}
					}
				}
			}
		}
		return
	}
	if phase != .down || button != .left {
		return
	}
	if a.view_mode == .columns && a.pointer_over_path(x, y) {
		a.path_drag = true
		a.path_drag_x = x
		a.path_drag_offset = a.path_offset
		return
	}
	if x < content_left {
		return
	}
	if a.view_mode == .columns && a.max_column_offset() > 0
		&& y >= height - files_horizontal_bar_height && y < height - files_padding / 2 {
		track := a.viewport_width - 2 * files_padding
		position, thumb := files_scroll_thumb(track, a.viewport_width, a.columns.len * a.column_width,
			a.column_offset)
		maximum := a.max_column_offset()
		if x >= content_left + files_padding && x < width - files_padding {
			if x < content_left + files_padding + position || x >= content_left + files_padding + position + thumb {
				travel := track - thumb
				if travel > 0 {
					a.column_offset = files_clamp((x - content_left - files_padding - thumb / 2) * maximum / travel,
						maximum)
				}
			}
			a.horizontal_drag = true
			a.horizontal_drag_x = x
			a.horizontal_drag_offset = a.column_offset
		}
		return
	}
	if y < a.rows_top || y >= a.rows_top + a.rows_height {
		return
	}
	if a.view_mode == .list {
		if a.browser.entries.len > a.visible_rows && x >= width - files_scrollbar_width - 4 {
			a.begin_vertical_drag(-1, y, a.browser.entries.len, a.browser.scroll)
		}
		return
	}
	for index, column in a.columns {
		bar_x := content_left + index * a.column_width - a.column_offset + a.column_width - files_scrollbar_width - 2
		if column.browser.entries.len > a.visible_rows && x >= bar_x - 2
			&& x < bar_x + files_scrollbar_width + 2 {
			a.begin_vertical_drag(column.id, y, column.browser.entries.len, column.browser.scroll)
			return
		}
	}
}

fn (mut a FileBrowserApp) handle(event_id string) ! {
	for location in files_locations {
		if event_id == location.action {
			a.navigate_to(location.path)
			return
		}
	}
	match event_id {
		files_action_up {
			if a.view_mode == .columns {
				a.go_up_miller()
			} else {
				a.browser.go_up()
			}
			return
		}
		files_action_view_list {
			a.set_view_mode(.list)
			return
		}
		files_action_view_columns {
			a.set_view_mode(.columns)
			return
		}
		else {}
	}
	if row := parse_miller_row_action(event_id) {
		a.select_miller_row(row.column_id, row.row)
		return
	}
	if event_id.starts_with(files_action_row) {
		a.browser.enter(event_id[files_action_row.len..].int())
	}
}
