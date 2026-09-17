// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Right-click file operations shared by the wallpaper and Files.
module main

import ui2

const create_context_new_folder = 'files.create.folder'
const create_context_new_file = 'files.create.file'
const file_context_rename = 'files.context.rename'
const file_context_copy = 'files.context.copy'
const file_context_cut = 'files.context.cut'
const file_context_paste = 'files.context.paste'
const file_context_delete = 'files.context.delete'
const files_context_select_prefix = 'files.context.select.'
const files_context_clear = 'files.context.clear'
const files_context_rename_key_prefix = 'files.context.rename.key.'
const desktop_file_action_prefix = 'desktop.file.'
const create_context_panel = 'context.create.panel'
const create_context_width = 180
const create_context_padding = 4
const create_context_row_height = 30

const create_context_background_entries = [
	ui2.MenuEntry{
		id: create_context_new_folder
		title: 'New Folder'
	},
	ui2.MenuEntry{
		id: create_context_new_file
		title: 'New File'
	},
	ui2.MenuEntry{
		id: file_context_paste
		title: 'Paste'
	},
]

const create_context_item_entries = [
	ui2.MenuEntry{
		id: file_context_rename
		title: 'Rename'
	},
	ui2.MenuEntry{
		id: file_context_copy
		title: 'Copy'
	},
	ui2.MenuEntry{
		id: file_context_cut
		title: 'Cut'
	},
	ui2.MenuEntry{
		id: file_context_paste
		title: 'Paste'
	},
	ui2.MenuEntry{
		id: file_context_delete
		title: 'Delete'
	},
]

enum CreateContextTarget {
	none_
	desktop
	files
}

enum RenameInputState {
	editing
	commit
	cancel
}

struct RenameInputResult {
	state      RenameInputState
	select_all bool
}

struct CreateContextMenuState {
mut:
	visible               bool
	target                CreateContextTarget
	has_item              bool
	item_path             string
	x                     int
	y                     int
	app_index             int = -1
	rename_app_index      int = -1
	swallow_left_release  bool
	swallow_right_release bool
}

struct DesktopDirectoryState {
mut:
	entries           []FileEntry
	loaded            bool
	rename_path       string
	rename_text       []u8
	rename_select_all bool
}

__global create_context_menu = CreateContextMenuState{}
__global desktop_directory_state = DesktopDirectoryState{}

fn rename_buffer_text(buffer []u8) string {
	if buffer.len == 0 {
		return ''
	}
	return unsafe { tos(buffer.data, buffer.len) }
}

fn rename_buffer_set(mut buffer []u8, text string) {
	buffer.clear()
	for ch in text {
		buffer << ch
	}
}

fn apply_rename_input(mut buffer []u8, select_all bool, input string) RenameInputResult {
	mut selected := select_all
	for ch in input {
		match ch {
			0x1b {
				return RenameInputResult{
					state: .cancel
					select_all: selected
				}
			}
			`\n`, `\r` {
				return RenameInputResult{
					state: .commit
					select_all: selected
				}
			}
			8, 127 {
				if selected {
					buffer.clear()
					selected = false
				} else if buffer.len > 0 {
					buffer.delete_last()
				}
			}
			else {
				if ch >= 0x20 && ch < 0x7f && ch != `/` {
					if selected {
						buffer.clear()
						selected = false
					}
					if buffer.len < 255 {
						buffer << ch
					}
				}
			}
		}
	}
	return RenameInputResult{
		state: .editing
		select_all: selected
	}
}

fn rename_input_finishes(input string) bool {
	for ch in input {
		if ch == 0x1b || ch == `\n` || ch == `\r` {
			return true
		}
	}
	return false
}

fn free_desktop_directory_entries() {
	for index in 0 .. desktop_directory_state.entries.len {
		unsafe {
			desktop_directory_state.entries[index].name.free()
			desktop_directory_state.entries[index].row_action.free()
			desktop_directory_state.entries[index].size_text.free()
		}
	}
	if desktop_directory_state.entries.cap > 0 {
		unsafe { desktop_directory_state.entries.free() }
	}
	desktop_directory_state.entries = []FileEntry{}
}

fn (mut d Desktop) refresh_desktop_directory() bool {
	ensure_desktop_directory() or {
		eprintln('vinix-desktop: ${err}')
		return false
	}
	entries := read_file_entries(desktop_directory, desktop_file_action_prefix) or {
		eprintln('vinix-desktop: cannot open ${desktop_directory}')
		return false
	}
	free_desktop_directory_entries()
	desktop_directory_state.entries = entries
	desktop_directory_state.loaded = true
	d.dirty = true
	return true
}

fn desktop_directory_clear_rename() {
	if desktop_directory_state.rename_path.len > 0 {
		unsafe { desktop_directory_state.rename_path.free() }
	}
	desktop_directory_state.rename_path = ''
	desktop_directory_state.rename_text.clear()
	desktop_directory_state.rename_select_all = false
}

fn (mut d Desktop) desktop_directory_begin_rename(path string) {
	desktop_directory_clear_rename()
	desktop_directory_state.rename_path = path.clone()
	rename_buffer_set(mut desktop_directory_state.rename_text, file_path_name(path))
	desktop_directory_state.rename_select_all = true
	d.focus = 0
	d.dirty = true
}

fn (mut d Desktop) desktop_directory_rename_key(input string) {
	if desktop_directory_state.rename_path.len == 0 {
		return
	}
	result := apply_rename_input(mut desktop_directory_state.rename_text,
		desktop_directory_state.rename_select_all, input)
	desktop_directory_state.rename_select_all = result.select_all
	match result.state {
		.editing {
			d.dirty = true
		}
		.cancel {
			desktop_directory_clear_rename()
			d.dirty = true
		}
		.commit {
			name := rename_buffer_text(desktop_directory_state.rename_text)
			next := rename_item_path(desktop_directory_state.rename_path, name) or {
				eprintln('vinix-desktop: ${err}')
				d.dirty = true
				return
			}
			desktop_directory_clear_rename()
			d.refresh_desktop_directory()
			unsafe { next.free() }
		}
	}
}

// FilesContextApp keeps the browser model intact while adding selection,
// filesystem actions and the inline rename field used by the shared menu.
struct FilesContextApp {
mut:
	files             FileBrowserApp
	context_path      string
	rename_path       string
	rename_text       []u8
	rename_select_all bool
}

fn open_files_with_context_menu(mut _ Desktop) !NativeApp {
	mut app := &FilesContextApp{}
	app.files.browser.read(desktop_home)
	if app.files.browser.error != '' {
		unsafe { app.files.browser.error.free() }
		app.files.browser.error = ''
		app.files.browser.read('/')
	}
	if app.files.browser.error != '' {
		return error(app.files.browser.error)
	}
	return app
}

fn (mut a FilesContextApp) set_context_path(path string) {
	next := path.clone()
	if a.context_path.len > 0 {
		unsafe { a.context_path.free() }
	}
	a.context_path = next
}

fn (mut a FilesContextApp) clear_context_path() {
	if a.context_path.len > 0 {
		unsafe { a.context_path.free() }
	}
	a.context_path = ''
}

fn (mut a FilesContextApp) clear_rename() {
	if a.rename_path.len > 0 {
		unsafe { a.rename_path.free() }
	}
	a.rename_path = ''
	a.rename_text.clear()
	a.rename_select_all = false
}

fn (mut a FilesContextApp) begin_rename(path string) {
	a.clear_rename()
	a.rename_path = path.clone()
	rename_buffer_set(mut a.rename_text, file_path_name(path))
	a.rename_select_all = true
	a.focus_path(path)
}

fn files_context_entry_index(entries []FileEntry, name string) int {
	for index, entry in entries {
		if entry.name == name {
			return index
		}
	}
	return -1
}

fn (mut a FilesContextApp) focus_path(path string) {
	parent := parent_path(path)
	name := file_path_name(path)
	if a.files.view_mode == .list {
		if a.files.browser.path != parent {
			return
		}
		index := files_context_entry_index(a.files.browser.entries, name)
		if index < 0 {
			return
		}
		if index < a.files.browser.scroll {
			a.files.browser.scroll = index
		} else if index >= a.files.browser.scroll + a.files.visible_rows {
			a.files.browser.scroll = index - a.files.visible_rows + 1
			if a.files.browser.scroll < 0 {
				a.files.browser.scroll = 0
			}
		}
		return
	}
	for column_index in 0 .. a.files.columns.len {
		if a.files.columns[column_index].browser.path != parent {
			continue
		}
		index := files_context_entry_index(a.files.columns[column_index].browser.entries, name)
		if index < 0 {
			return
		}
		if index < a.files.columns[column_index].browser.scroll {
			a.files.columns[column_index].browser.scroll = index
		} else if index >= a.files.columns[column_index].browser.scroll + a.files.visible_rows {
			a.files.columns[column_index].browser.scroll = index - a.files.visible_rows + 1
			if a.files.columns[column_index].browser.scroll < 0 {
				a.files.columns[column_index].browser.scroll = 0
			}
		}
		return
	}
}

// path is owned by the caller. List mode hands that ownership to FileBrowser;
// column mode clones it into its retained columns and releases the temporary.
fn (mut a FilesContextApp) refresh_to(path string) {
	if a.files.view_mode == .columns {
		a.files.reset_miller_columns(path)
		unsafe { path.free() }
		return
	}
	a.files.browser.read(path)
}

fn (mut a FilesContextApp) select_action(action string) {
	if action.starts_with(files_action_row) {
		index := action[files_action_row.len..].int()
		if index >= 0 && index < a.files.browser.entries.len {
			path := create_item_path(a.files.browser.path, a.files.browser.entries[index].name)
			a.set_context_path(path)
			unsafe { path.free() }
			return
		}
	}
	if row := parse_miller_row_action(action) {
		for column in a.files.columns {
			if column.id == row.column_id && row.row >= 0 && row.row < column.browser.entries.len {
				path := create_item_path(column.browser.path, column.browser.entries[row.row].name)
				a.set_context_path(path)
				unsafe { path.free() }
				return
			}
		}
	}
	a.clear_context_path()
}

fn (a &FilesContextApp) rename_overlay(size ui2.Rect) ?ui2.Element {
	if a.rename_path.len == 0 {
		return none
	}
	parent := parent_path(a.rename_path)
	name := file_path_name(a.rename_path)
	width := int(size.width)
	if a.files.view_mode == .list {
		if a.files.browser.path != parent {
			return none
		}
		index := files_context_entry_index(a.files.browser.entries, name)
		if index < a.files.browser.scroll || index >= a.files.browser.scroll + a.files.visible_rows {
			return none
		}
		x := files_padding + 20
		y := files_header_height + (index - a.files.browser.scroll) * files_row_height
		mut field_width := width - x - files_padding - 72
		if field_width < 80 {
			field_width = 80
		}
		return ui2.text_field('', '', rename_buffer_text(a.rename_text), ui2.rect(f64(x),
			f64(y + 1), f64(field_width), f64(files_row_height - 2)), ui2.BoxStyle{
			bg: editor_path_focus
			radius: 4
		}, ui2.TextStyle{
			color: body_text
			size: 13
		}, 0)
	}
	mut slots := 1
	if width >= files_column_min_width {
		slots = width / files_column_min_width
		if slots < 1 {
			slots = 1
		}
	}
	column_width := width / slots
	mut start := a.files.columns.len - slots
	if start < 0 {
		start = 0
	}
	mut slot := 0
	for column_index := start; column_index < a.files.columns.len && slot < slots; column_index++ {
		column := &a.files.columns[column_index]
		if column.browser.path == parent {
			index := files_context_entry_index(column.browser.entries, name)
			if index >= column.browser.scroll && index < column.browser.scroll + a.files.visible_rows {
				x := slot * column_width + files_padding + 20
				y := files_header_height + files_column_header_height
					+ (index - column.browser.scroll) * files_row_height
				mut this_width := column_width
				if slot + 1 == slots {
					this_width = width - slot * column_width
				}
				mut field_width := this_width - 2 * files_padding - 52
				if field_width < 72 {
					field_width = 72
				}
				return ui2.text_field('', '', rename_buffer_text(a.rename_text), ui2.rect(f64(x),
					f64(y + 1), f64(field_width), f64(files_row_height - 2)), ui2.BoxStyle{
					bg: editor_path_focus
					radius: 4
				}, ui2.TextStyle{
					color: body_text
					size: 12
				}, 0)
			}
		}
		slot++
	}
	return none
}

fn (mut a FilesContextApp) build(size ui2.Rect) !ui2.Element {
	root := a.files.build(size)!
	if overlay := a.rename_overlay(size) {
		mut children := frame_elements(root.children.len + 1)
		children << root.children
		children << overlay
		return ui2.Element{
			...root
			children: children
		}
	}
	return root
}

fn (mut a FilesContextApp) create_item(kind CreateItemKind) ! {
	directory := a.files.current_path().clone()
	created := create_unique_item(directory, kind) or {
		unsafe { directory.free() }
		return err
	}
	a.refresh_to(directory)
	a.set_context_path(created)
	a.begin_rename(created)
	unsafe { created.free() }
}

fn (mut a FilesContextApp) rename_selected() ! {
	if a.context_path.len == 0 || desktop_lstat(a.context_path) == none {
		return error('no file selected')
	}
	a.begin_rename(a.context_path)
}

fn (mut a FilesContextApp) copy_selected(mode FileClipboardMode) ! {
	if a.context_path.len == 0 || !file_context_clipboard_store(mode, a.context_path) {
		return error('cannot put the selected item on the clipboard')
	}
}

fn (mut a FilesContextApp) delete_selected() ! {
	if a.context_path.len == 0 {
		return error('no file selected')
	}
	selected := a.context_path.clone()
	current := a.files.current_path().clone()
	mut next_current := current.clone()
	if file_context_path_inside(current, selected) {
		unsafe { next_current.free() }
		next_current = parent_path(selected).clone()
	}
	file_context_remove_path(selected) or {
		unsafe {
			selected.free()
			current.free()
			next_current.free()
		}
		return err
	}
	a.clear_context_path()
	if a.rename_path == selected {
		a.clear_rename()
	}
	a.refresh_to(next_current)
	unsafe {
		selected.free()
		current.free()
	}
}

fn (mut a FilesContextApp) paste() ! {
	directory := a.files.current_path().clone()
	pasted := paste_file_clipboard(directory) or {
		unsafe { directory.free() }
		return err
	}
	a.refresh_to(directory)
	a.set_context_path(pasted)
	a.focus_path(pasted)
	unsafe { pasted.free() }
}

fn (mut a FilesContextApp) commit_rename() ! {
	if a.rename_path.len == 0 {
		return
	}
	old_path := a.rename_path.clone()
	current := a.files.current_path().clone()
	name := rename_buffer_text(a.rename_text)
	new_path := rename_item_path(old_path, name) or {
		unsafe {
			old_path.free()
			current.free()
		}
		return err
	}
	next_current := file_context_rebased_path(current, old_path, new_path)
	a.clear_rename()
	a.set_context_path(new_path)
	a.refresh_to(next_current)
	a.focus_path(new_path)
	unsafe {
		old_path.free()
		current.free()
		new_path.free()
	}
}

fn (mut a FilesContextApp) rename_key_input(input string) ! {
	if a.rename_path.len == 0 {
		return
	}
	result := apply_rename_input(mut a.rename_text, a.rename_select_all, input)
	a.rename_select_all = result.select_all
	match result.state {
		.editing {}
		.cancel { a.clear_rename() }
		.commit { a.commit_rename()! }
	}
}

fn (mut a FilesContextApp) handle(event_id string) ! {
	if event_id.starts_with(files_context_select_prefix) {
		a.select_action(event_id[files_context_select_prefix.len..])
		return
	}
	if event_id.starts_with(files_context_rename_key_prefix) {
		a.rename_key_input(event_id[files_context_rename_key_prefix.len..])!
		return
	}
	match event_id {
		files_context_clear {
			a.clear_context_path()
			return
		}
		create_context_new_folder {
			a.create_item(.folder)!
			return
		}
		create_context_new_file {
			a.create_item(.file)!
			return
		}
		file_context_rename {
			a.rename_selected()!
			return
		}
		file_context_copy {
			a.copy_selected(.copy)!
			return
		}
		file_context_cut {
			a.copy_selected(.cut)!
			return
		}
		file_context_paste {
			a.paste()!
			return
		}
		file_context_delete {
			a.delete_selected()!
			return
		}
		else {}
	}
	a.files.handle(event_id)!
}

fn (mut d Desktop) clear_context_item_path() {
	if create_context_menu.item_path.len > 0 {
		unsafe { create_context_menu.item_path.free() }
	}
	create_context_menu.item_path = ''
}

fn context_menu_height(has_item bool) int {
	count := if has_item { create_context_item_entries.len } else { create_context_background_entries.len }
	return count * create_context_row_height + 2 * create_context_padding
}

fn (mut d Desktop) set_create_context_menu(target CreateContextTarget, app_index int, has_item bool,
	item_path string, x int, y int) {
	mut menu_x := x
	mut menu_y := y
	height := context_menu_height(has_item)
	if menu_x + create_context_width > d.canvas.width {
		menu_x = d.canvas.width - create_context_width
	}
	if menu_y + height > d.canvas.height {
		menu_y = d.canvas.height - height
	}
	if menu_x < 0 {
		menu_x = 0
	}
	if menu_y < 0 {
		menu_y = 0
	}
	d.clear_context_item_path()
	if item_path.len > 0 {
		create_context_menu.item_path = item_path.clone()
	}
	create_context_menu.visible = true
	create_context_menu.target = target
	create_context_menu.has_item = has_item
	create_context_menu.app_index = app_index
	create_context_menu.x = menu_x
	create_context_menu.y = menu_y
	create_context_menu.swallow_right_release = true
	d.dirty = true
}

fn (mut d Desktop) close_create_context_menu() {
	if !create_context_menu.visible {
		return
	}
	create_context_menu.visible = false
	create_context_menu.target = .none_
	create_context_menu.has_item = false
	create_context_menu.app_index = -1
	d.clear_context_item_path()
	d.hover = ''
	d.dirty = true
}

fn (mut d Desktop) cancel_file_context_rename() {
	if desktop_directory_state.rename_path.len > 0 {
		desktop_directory_clear_rename()
		d.dirty = true
	}
	index := create_context_menu.rename_app_index
	if index >= 0 && index < d.apps.len {
		payload := files_context_rename_key_prefix + '\x1b'
		d.apps[index].handle(payload) or {}
		unsafe { payload.free() }
	}
	create_context_menu.rename_app_index = -1
}

fn files_context_row_action(action string) bool {
	return action.starts_with(files_action_row) || action.starts_with(files_action_column_row)
}

// Files gets the item under the pointer as a private selection event before
// the compositor shows the menu. Empty Files space instead clears that target.
fn (mut d Desktop) open_create_context_menu(x int, y int) bool {
	if d.switcher.active || d.start_menu_open {
		return false
	}
	d.cancel_file_context_rename()
	underlying := d.hit_action(x, y)
	for i := d.windows.len - 1; i >= 0; i-- {
		window := &d.windows[i]
		if window.minimized || x < window.x || x >= window.x + window.width || y < window.y
			|| y >= window.y + window.height {
			continue
		}
		body_top := window.y + d.theme().title_height
		if window.title == 'Files' && window.app_index >= 0 && window.app_index < d.apps.len
			&& y >= body_top {
			app_index := window.app_index
			window_id := window.id
			has_item := files_context_row_action(underlying)
			if has_item {
				payload := files_context_select_prefix + underlying
				d.apps[app_index].handle(payload) or {
					eprintln('vinix-desktop: Files: ${err}')
				}
				unsafe { payload.free() }
			} else {
				d.apps[app_index].handle(files_context_clear) or {}
			}
			d.raise(window_id)
			d.set_create_context_menu(.files, app_index, has_item, '', x, y)
			return true
		}
		d.close_create_context_menu()
		return false
	}
	if underlying.starts_with(desktop_file_action_prefix) {
		index := underlying[desktop_file_action_prefix.len..].int()
		if index >= 0 && index < desktop_directory_state.entries.len {
			path := create_item_path(desktop_directory, desktop_directory_state.entries[index].name)
			d.set_create_context_menu(.desktop, -1, true, path, x, y)
			unsafe { path.free() }
			return true
		}
	}
	if y >= d.canvas.height - taskbar_height || underlying != '' {
		d.close_create_context_menu()
		return false
	}
	d.set_create_context_menu(.desktop, -1, false, '', x, y)
	return true
}

fn context_menu_action(action string) bool {
	return action == create_context_new_folder || action == create_context_new_file
		|| action == file_context_rename || action == file_context_copy || action == file_context_cut
		|| action == file_context_paste || action == file_context_delete
}

fn action_starts_rename(action string) bool {
	return action == create_context_new_folder || action == create_context_new_file
		|| action == file_context_rename
}

fn (mut d Desktop) desktop_context_action(action string, item_path string) ! {
	ensure_desktop_directory()!
	match action {
		create_context_new_folder, create_context_new_file {
			kind := if action == create_context_new_folder { CreateItemKind.folder } else { CreateItemKind.file }
			created := create_unique_item(desktop_directory, kind)!
			d.refresh_desktop_directory()
			d.desktop_directory_begin_rename(created)
			unsafe { created.free() }
		}
		file_context_rename {
			if item_path.len == 0 {
				return error('no file selected')
			}
			d.desktop_directory_begin_rename(item_path)
		}
		file_context_copy {
			if item_path.len == 0 || !file_context_clipboard_store(.copy, item_path) {
				return error('cannot copy the selected item')
			}
		}
		file_context_cut {
			if item_path.len == 0 || !file_context_clipboard_store(.cut, item_path) {
				return error('cannot cut the selected item')
			}
		}
		file_context_paste {
			pasted := paste_file_clipboard(desktop_directory)!
			d.refresh_desktop_directory()
			unsafe { pasted.free() }
		}
		file_context_delete {
			if item_path.len == 0 {
				return error('no file selected')
			}
			file_context_remove_path(item_path)!
			d.refresh_desktop_directory()
		}
		else {}
	}
}

fn (mut d Desktop) create_context_left_down(x int, y int) bool {
	if !create_context_menu.visible {
		return false
	}
	action := d.hit_action(x, y)
	if action == create_context_panel {
		create_context_menu.swallow_left_release = true
		return true
	}
	if !context_menu_action(action) {
		d.close_create_context_menu()
		return false
	}
	target := create_context_menu.target
	app_index := create_context_menu.app_index
	item_path := if create_context_menu.item_path.len > 0 {
		create_context_menu.item_path.clone()
	} else {
		''
	}
	create_context_menu.swallow_left_release = true
	d.close_create_context_menu()
	match target {
		.desktop {
			d.desktop_context_action(action, item_path) or {
				eprintln('vinix-desktop: ${err}')
			}
		}
		.files {
			if app_index >= 0 && app_index < d.apps.len {
				mut handled := true
				d.apps[app_index].handle(action) or {
					handled = false
					eprintln('vinix-desktop: Files: ${err}')
				}
				if handled && action_starts_rename(action) {
					create_context_menu.rename_app_index = app_index
				}
				if handled && action in [create_context_new_folder, create_context_new_file,
					file_context_paste, file_context_delete] {
					d.refresh_desktop_directory()
				}
			}
		}
		.none_ {}
	}
	if item_path.len > 0 {
		unsafe { item_path.free() }
	}
	d.dirty = true
	return true
}

fn take_create_context_left_release() bool {
	if !create_context_menu.swallow_left_release {
		return false
	}
	create_context_menu.swallow_left_release = false
	return true
}

fn take_create_context_right_release() bool {
	if !create_context_menu.swallow_right_release {
		return false
	}
	create_context_menu.swallow_right_release = false
	return true
}

// Rename typing is deliberately intercepted before ordinary focused-app input.
// That keeps Files' existing keyboard contract unchanged while a temporary
// filename editor owns text until Return or Escape.
fn (mut d Desktop) file_context_rename_key_input(input string) bool {
	if desktop_directory_state.rename_path.len > 0 {
		d.desktop_directory_rename_key(input)
		return true
	}
	index := create_context_menu.rename_app_index
	if index < 0 || index >= d.apps.len {
		return false
	}
	payload := files_context_rename_key_prefix + input
	mut handled := true
	d.apps[index].handle(payload) or {
		handled = false
		eprintln('vinix-desktop: Files: ${err}')
	}
	unsafe { payload.free() }
	if handled && rename_input_finishes(input) {
		create_context_menu.rename_app_index = -1
		d.refresh_desktop_directory()
	}
	d.dirty = true
	return true
}

fn desktop_file_icon_occluded(d &Desktop, x int, y int, width int, height int) bool {
	for window in d.windows {
		if window.minimized {
			continue
		}
		if x < window.x + window.width && x + width > window.x && y < window.y + window.height
			&& y + height > window.y {
			return true
		}
	}
	return false
}

fn (mut d Desktop) render_desktop_file_icons() {
	if d.start_menu_open || d.switcher.shown {
		return
	}
	if !desktop_directory_state.loaded && !d.refresh_desktop_directory() {
		return
	}
	rows := shortcut_rows_for_height(d.canvas.height)
	theme := d.theme()
	rename_name := if desktop_directory_state.rename_path.len > 0 {
		file_path_name(desktop_directory_state.rename_path)
	} else {
		''
	}
	for index in 0 .. desktop_directory_state.entries.len {
		entry := &desktop_directory_state.entries[index]
		slot := available_apps.len + index
		column := slot / rows
		row := slot % rows
		x := shortcut_left + column * (shortcut_width + shortcut_gap)
		y := shortcut_top + row * (shortcut_height + shortcut_gap)
		if x + shortcut_width > d.canvas.width {
			break
		}
		if desktop_file_icon_occluded(d, x, y, shortcut_width, shortcut_height) {
			continue
		}
		hovered := d.hover == entry.row_action
		renaming := rename_name != '' && entry.name == rename_name
		icon_x := (shortcut_width - shortcut_icon) / 2
		mut icon_children := frame_elements(2)
		icon_children << ui2.button_with_image('', '', if entry.is_dir {
			'builtin:folder'
		} else {
			'builtin:file'
		}, ui2.rect(f64(icon_x), 10, f64(shortcut_icon), f64(shortcut_icon)), ui2.BoxStyle{
			transparent: true
		}, ui2.TextStyle{
			color: if entry.is_dir { files_folder_icon } else { files_file_icon }
		})
		if renaming {
			icon_children << ui2.text_field('', '', rename_buffer_text(desktop_directory_state.rename_text),
				ui2.rect(2, f64(shortcut_icon + 13), f64(shortcut_width - 4), 22), ui2.BoxStyle{
					bg: editor_path_focus
					radius: 4
				}, ui2.TextStyle{
					color: body_text
					size: 12
					align: .center
				}, 0)
		} else {
			icon_children << ui2.label('', entry.name, ui2.rect(0, f64(shortcut_icon + 16),
				f64(shortcut_width), 18), ui2.TextStyle{
				color: if hovered { theme.shortcut_hover } else { theme.shortcut_label }
				shadow: true
				size: 12
				align: .center
			})
		}
		icon := ui2.clickable_view(entry.row_action, ui2.rect(f64(x), f64(y), f64(shortcut_width),
			f64(shortcut_height)), ui2.BoxStyle{
			bg: theme.shortcut_panel
			radius: 8
			transparent: !hovered && !renaming
		}, icon_children)
		d.render_element(icon, 0, 0, 1)
		free_tree(icon)
	}
}

fn (mut d Desktop) render_context_entries(entries []ui2.MenuEntry) {
	height := entries.len * create_context_row_height + 2 * create_context_padding
	mut children := frame_elements(entries.len)
	for index, entry in entries {
		y := create_context_padding + index * create_context_row_height
		children << ui2.button(entry.id, entry.title, ui2.rect(f64(create_context_padding), f64(y),
			f64(create_context_width - 2 * create_context_padding), f64(create_context_row_height)),
			ui2.BoxStyle{
				bg: if d.hover == entry.id { files_row_hover } else { app_surface }
				radius: 5
			}, ui2.TextStyle{
				color: body_text
				size: 13
				align: .left
			})
	}
	panel := ui2.clickable_view(create_context_panel, ui2.rect(f64(create_context_menu.x),
		f64(create_context_menu.y), f64(create_context_width), f64(height)), ui2.BoxStyle{
		bg: app_surface
		radius: 7
		border_color: body_rule
		border_left: 1
		border_top: 1
		border_right: 1
		border_bottom: 1
	}, children)
	d.render_element(panel, 0, 0, 2)
	free_tree(panel)
}

fn (mut d Desktop) render_create_context_menu() {
	// User files are part of the desktop surface, so paint them after the main
	// tree only where no window covers them. Their targets then participate in
	// the same hit testing as app shortcuts and context-menu rows.
	d.render_desktop_file_icons()
	if create_context_menu.visible {
		if create_context_menu.has_item {
			d.render_context_entries(create_context_item_entries)
		} else {
			d.render_context_entries(create_context_background_entries)
		}
	}
	// Both overlays are painted after render(), whose first cursor copy can be
	// covered by an icon or menu.
	d.draw_cursor()
}
