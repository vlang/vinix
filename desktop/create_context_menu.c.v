// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
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
const file_context_tags = 'files.context.tags'
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
		id:    create_context_new_folder
		title: 'New Folder'
	},
	ui2.MenuEntry{
		id:    create_context_new_file
		title: 'New File'
	},
	ui2.MenuEntry{
		id:    file_context_paste
		title: 'Paste'
	},
]

const create_context_item_entries = [
	ui2.MenuEntry{
		id:    file_context_rename
		title: 'Rename'
	},
	ui2.MenuEntry{
		id:    file_context_copy
		title: 'Copy'
	},
	ui2.MenuEntry{
		id:    file_context_cut
		title: 'Cut'
	},
	ui2.MenuEntry{
		id:    file_context_paste
		title: 'Paste'
	},
	ui2.MenuEntry{
		id:    file_context_delete
		title: 'Delete'
	},
]

const create_context_files_item_entries = [
	ui2.MenuEntry{ id: file_context_rename, title: 'Rename' },
	ui2.MenuEntry{ id: file_context_copy, title: 'Copy' },
	ui2.MenuEntry{ id: file_context_cut, title: 'Cut' },
	ui2.MenuEntry{ id: file_context_paste, title: 'Paste' },
	ui2.MenuEntry{ id: file_context_tags, title: 'Tags…' },
	ui2.MenuEntry{ id: file_context_delete, title: 'Delete' },
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
					state:      .cancel
					select_all: selected
				}
			}
			`\n`, `\r` {
				return RenameInputResult{
					state:      .commit
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
		state:      .editing
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
	files               FileBrowserApp
	settings_only       bool
	settings_tab        int
	settings_selected   int
	settings_scroll     int
	settings_editing    bool
	settings_select_all bool
	settings_name       []u8
	tag_picker          bool
	tag_picker_scroll   int
	context_path        string
	rename_path         string
	rename_text         []u8
	rename_select_all   bool
	preview             FilesQuickLook
}

fn open_files_with_context_menu(mut _ Desktop) !NativeApp {
	mut app := &FilesContextApp{}
	app.files.settings = load_files_settings(desktop_home)
	app.files.browser.show_hidden = app.files.settings.show_hidden
	for location in files_locations[..files_locations.len - 1] {
		if location.path != desktop_home {
			ensure_directory(location.path) or {}
		}
	}
	app.files.browser.read(desktop_home)
	if app.files.browser.error != '' {
		unsafe { app.files.browser.error.free() }
		app.files.browser.error = ''
		app.files.browser.read('/')
	}
	if app.files.browser.error != '' {
		return error(app.files.browser.error)
	}
	app.restore_files_view_mode(desktop_home)
	return app
}

fn (mut a FilesContextApp) restore_files_view_mode(home string) {
	a.files.set_view_mode(load_files_view_mode(home))
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
	if a.files.active_tag_id >= 0 {
		paths := a.files.settings.tagged_paths(a.files.active_tag_id)
		visible := if a.files.visible_rows > 1 { a.files.visible_rows - 1 } else { 1 }
		index := paths.index(path)
		if index >= 0 {
			if index < a.files.browser.scroll { a.files.browser.scroll = index }
			if index >= a.files.browser.scroll + visible {
				a.files.browser.scroll = index - visible + 1
			}
		}
		unsafe { paths.free() }
		return
	}
	parent := parent_path(path)
	name := file_path_name(path)
	if a.files.view_mode == .commander {
		if a.files.active_pane == 0 {
			files_commander_focus_path(mut a.files.dual_left, parent, name, a.files.visible_rows)
		} else {
			files_commander_focus_path(mut a.files.dual_right, parent, name, a.files.visible_rows)
		}
		return
	}
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
	if a.files.view_mode == .commander {
		if a.files.active_pane == 0 {
			a.files.dual_right.read(a.files.dual_right.path.clone())
			a.files.dual_left.read(path)
		} else {
			a.files.dual_left.read(a.files.dual_left.path.clone())
			a.files.dual_right.read(path)
		}
		return
	}
	a.files.browser.read(path)
}

fn (mut a FilesContextApp) select_action(action string) {
	if action.starts_with(files_action_tag_row) {
		paths := a.files.settings.tagged_paths(a.files.active_tag_id)
		index := action[files_action_tag_row.len..].int()
		if index >= 0 && index < paths.len {
			a.set_context_path(paths[index])
			unsafe { paths.free() }
			return
		}
		unsafe { paths.free() }
	}
	if action.starts_with(files_action_pane_left_row) {
		a.files.active_pane = 0
		index := action[files_action_pane_left_row.len..].int()
		if index >= 0 && index < a.files.dual_left.entries.len {
			a.files.dual_left.selected_row = index
			path := create_item_path(a.files.dual_left.path, a.files.dual_left.entries[index].name)
			a.set_context_path(path)
			unsafe { path.free() }
			return
		}
	}
	if action.starts_with(files_action_pane_right_row) {
		a.files.active_pane = 1
		index := action[files_action_pane_right_row.len..].int()
		if index >= 0 && index < a.files.dual_right.entries.len {
			a.files.dual_right.selected_row = index
			path := create_item_path(a.files.dual_right.path, a.files.dual_right.entries[index].name)
			a.set_context_path(path)
			unsafe { path.free() }
			return
		}
	}
	if action.starts_with(files_action_row) {
		index := action[files_action_row.len..].int()
		if index >= 0 && index < a.files.browser.entries.len {
			a.files.browser.selected_row = index
			path := create_item_path(a.files.browser.path, a.files.browser.entries[index].name)
			a.set_context_path(path)
			unsafe { path.free() }
			return
		}
	}
	if row := parse_miller_row_action(action) {
		for column_index, column in a.files.columns {
			if column.id == row.column_id && row.row >= 0 && row.row < column.browser.entries.len {
				a.files.columns[column_index].selected_row = row.row
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
	content_left := files_content_left(width)
	if a.files.active_tag_id >= 0 {
		paths := a.files.settings.tagged_paths(a.files.active_tag_id)
		index := paths.index(a.rename_path)
		visible := if a.files.visible_rows > 1 { a.files.visible_rows - 1 } else { 1 }
		unsafe { paths.free() }
		if index < a.files.browser.scroll || index >= a.files.browser.scroll + visible {
			return none
		}
		return ui2.text_field('', '', rename_buffer_text(a.rename_text), ui2.rect(f64(content_left + 36),
			f64(files_header_height + 27 + (index - a.files.browser.scroll) * files_row_height),
			f64(width - content_left - 62), f64(files_row_height - 2)), ui2.BoxStyle{
			bg:     editor_path_focus
			radius: 4
		}, ui2.TextStyle{ color: body_text, size: 12 }, 0)
	}
	if a.files.view_mode == .commander {
		pane := a.files.active_pane
		browser := if pane == 0 { &a.files.dual_left } else { &a.files.dual_right }
		if browser.path != parent {
			return none
		}
		index := files_context_entry_index(browser.entries, name)
		if index < browser.scroll || index >= browser.scroll + a.files.visible_rows {
			return none
		}
		pane_x := files_commander_pane_x(width, pane)
		pane_width := files_commander_pane_width(width, pane)
		return ui2.text_field('', '', rename_buffer_text(a.rename_text), ui2.rect(f64(pane_x + files_padding + 22),
			f64(a.files.rows_top + (index - browser.scroll) * files_row_height + 1),
			f64(pane_width - 2 * files_padding - 28), f64(files_row_height - 2)), ui2.BoxStyle{
			bg:     editor_path_focus
			radius: 4
		}, ui2.TextStyle{ color: body_text, size: 12 }, 0)
	}
	if a.files.view_mode == .list {
		if a.files.browser.path != parent {
			return none
		}
		index := files_context_entry_index(a.files.browser.entries, name)
		if index < a.files.browser.scroll || index >= a.files.browser.scroll + a.files.visible_rows {
			return none
		}
		x := content_left + files_padding + 20
		y := files_header_height + (index - a.files.browser.scroll) * files_row_height
		mut field_width := width - x - files_padding - 72
		if field_width < 80 {
			field_width = 80
		}
		return ui2.text_field('', '', rename_buffer_text(a.rename_text), ui2.rect(f64(x),
			f64(y + 1), f64(field_width), f64(files_row_height - 2)), ui2.BoxStyle{
			bg:     editor_path_focus
			radius: 4
		}, ui2.TextStyle{
			color: body_text
			size:  13
		}, 0)
	}
	column_width := a.files.column_width
	for column_index := 0; column_index < a.files.columns.len; column_index++ {
		column_x := column_index * column_width - a.files.column_offset
		if column_x + column_width <= 0 || column_x >= a.files.viewport_width {
			continue
		}
		column := &a.files.columns[column_index]
		if column.browser.path == parent {
			index := files_context_entry_index(column.browser.entries, name)
			if index >= column.browser.scroll && index < column.browser.scroll + a.files.visible_rows {
				mut x := content_left + column_x + files_padding + 20
				if x < content_left + files_padding {
					x = content_left + files_padding
				}
				y := a.files.rows_top +
					(index - column.browser.scroll) * files_row_height
				mut field_width := column_width - 2 * files_padding - 52
				visible_right := if column_x + column_width < a.files.viewport_width {
					content_left + column_x + column_width
				} else {
					width
				}
				if field_width > visible_right - x - files_padding {
					field_width = visible_right - x - files_padding
				}
				if field_width < 40 {
					return none
				}
				return ui2.text_field('', '', rename_buffer_text(a.rename_text), ui2.rect(f64(x),
					f64(y + 1), f64(field_width), f64(files_row_height - 2)), ui2.BoxStyle{
					bg:     editor_path_focus
					radius: 4
				}, ui2.TextStyle{
					color: body_text
					size:  12
				}, 0)
			}
		}
	}
	return none
}

fn (mut a FilesContextApp) build(size ui2.Rect) !ui2.Element {
	if a.settings_only {
		return a.settings_window(size)
	}
	root := a.files.build(size)!
	if a.tag_picker {
		mut children := frame_elements(root.children.len + 1)
		children << root.children
		children << a.tag_picker_overlay(size)
		return ui2.Element{ ...root, children: children }
	}
	if a.preview.open {
		mut children := frame_elements(root.children.len + 1)
		children << root.children
		children << a.preview.build(size)
		return ui2.Element{
			...root
			children: children
		}
	}
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
	a.files.settings.remove_path(selected)
	a.files.settings.save(desktop_home)
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
	clipboard := file_context_clipboard_load()
	pasted := paste_file_clipboard(directory) or {
		if source := clipboard { unsafe { source.path.free() } }
		unsafe { directory.free() }
		return err
	}
	if source := clipboard {
		if source.mode == .cut {
			a.files.settings.rebase_path(source.path, pasted)
		} else {
			a.files.settings.copy_path(source.path, pasted)
		}
		a.files.settings.save(desktop_home)
		unsafe { source.path.free() }
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
	a.files.settings.rebase_path(old_path, new_path)
	a.files.settings.save(desktop_home)
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
	if event_id == files_settings_refresh {
		a.reload_files_settings(desktop_home)
		return
	}
	if a.settings_only {
		a.handle_settings(event_id)
		return
	}
	if a.preview.open {
		if event_id == files_quicklook_close {
			a.preview.close()
		}
		return
	}
	if a.tag_picker {
		if event_id == files_picker_close {
			a.tag_picker = false
		} else if event_id.starts_with(files_picker_toggle_prefix) {
			id := event_id[files_picker_toggle_prefix.len..].int()
			a.files.settings.toggle_tag(a.context_path, id)
			a.files.settings.save(desktop_home)
		}
		return
	}
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
		file_context_tags {
			if a.context_path.len > 0 {
				a.tag_picker = true
				a.tag_picker_scroll = 0
			}
			return
		}
		else {}
	}
	if event_id.starts_with(files_action_row) {
		index := event_id[files_action_row.len..].int()
		if index >= 0 && index < a.files.browser.entries.len {
			a.select_action(event_id)
		}
	} else if event_id.starts_with(files_action_pane_left_row)
		|| event_id.starts_with(files_action_pane_right_row)
		|| event_id.starts_with(files_action_tag_row)
		|| parse_miller_row_action(event_id) != none {
		a.select_action(event_id)
	} else if event_id == files_action_up || event_id == files_action_view_list
		|| event_id == files_action_view_columns || event_id == files_action_view_commander
		|| event_id == files_action_pane_left || event_id == files_action_pane_right
		|| event_id.starts_with('files.location.')
		|| (event_id.starts_with(files_action_tag_prefix)
			&& !event_id.starts_with(files_action_tag_row)) {
		a.clear_context_path()
	}
	a.handle_browser_action(event_id, desktop_home)!
}

fn (mut a FilesContextApp) handle_browser_action(event_id string, home string) ! {
	a.files.handle(event_id)!
	if event_id == files_action_view_list || event_id == files_action_view_columns
		|| event_id == files_action_view_commander {
		save_files_view_mode(home, a.files.view_mode)
	}
}

fn (mut a FilesContextApp) pointer_input_enabled() bool {
	return true
}

fn (mut a FilesContextApp) pointer_event(phase AppPointerPhase, button AppPointerButton,
	scroll int, x int, y int, width int, height int) {
	if a.settings_only {
		if phase == .scroll && a.settings_tab == 1 {
			a.settings_scroll = files_clamp(a.settings_scroll - scroll,
				if a.files.settings.tags.len > 0 { a.files.settings.tags.len - 1 } else { 0 })
		}
		return
	}
	if a.tag_picker {
		if phase == .scroll {
			a.tag_picker_scroll = files_clamp(a.tag_picker_scroll - scroll,
				if a.files.settings.tags.len > 0 { a.files.settings.tags.len - 1 } else { 0 })
		}
		return
	}
	if a.preview.open {
		if phase == .scroll {
			a.preview.scroll_by(-scroll * 3, height)
		}
		return
	}
	if button == .back {
		if phase == .down {
			a.clear_context_path()
			a.files.handle(files_action_up) or {}
		}
		return
	}
	a.files.pointer_event(phase, button, scroll, x, y, width, height)
}

fn (mut a FilesContextApp) key_input(input string) {
	if a.settings_only {
		a.settings_key_input(input)
		return
	}
	if a.preview.open {
		a.quicklook_key_input(input)
		return
	}
	if a.tag_picker {
		if input == '\x1b' { a.tag_picker = false }
		return
	}
	if a.files.view_mode == .commander && input == '\t' {
		a.files.active_pane = 1 - a.files.active_pane
		a.clear_context_path()
		return
	}
	a.quicklook_key_input(input)
}

fn (mut a FilesContextApp) close_app() {
	a.preview.close()
}

fn (mut d Desktop) clear_context_item_path() {
	if create_context_menu.item_path.len > 0 {
		unsafe { create_context_menu.item_path.free() }
	}
	create_context_menu.item_path = ''
}

fn context_menu_height(target CreateContextTarget, has_item bool) int {
	count := if has_item {
		if target == .files {
			create_context_files_item_entries.len
		} else {
			create_context_item_entries.len
		}
	} else {
		create_context_background_entries.len
	}
	return count * create_context_row_height + 2 * create_context_padding
}

fn (mut d Desktop) set_create_context_menu(target CreateContextTarget, app_index int, has_item bool,
	item_path string, x int, y int) {
	mut menu_x := x
	mut menu_y := y
	height := context_menu_height(target, has_item)
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
	d.set_hover('')
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
		|| action.starts_with(files_action_tag_row)
		|| action.starts_with(files_action_pane_left_row)
		|| action.starts_with(files_action_pane_right_row)
}

// Files gets the item under the pointer as a private selection event before
// the compositor shows the menu. Empty Files space instead clears that target.
fn (mut d Desktop) open_create_context_menu(x int, y int) bool {
	if d.switcher.active || d.start_menu_open {
		return false
	}
	d.cancel_file_context_rename()
	underlying, world := d.hit_action_world(x, y)
	if world == .application && (underlying.starts_with('files.settings.')
		|| underlying.starts_with('files.tags.')) {
		d.close_create_context_menu()
		return false
	}
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
			has_item := world == .application && files_context_row_action(underlying)
			if has_item {
				payload := files_context_select_prefix + underlying
				d.apps[app_index].handle(payload) or {
					eprintln('vinix-desktop: Files: ${err}')
				}
				unsafe { payload.free() }
			} else {
				if underlying == files_action_pane_left || underlying == files_action_pane_right {
					d.apps[app_index].handle(underlying) or {}
				}
				d.apps[app_index].handle(files_context_clear) or {}
			}
			d.raise(window_id)
			d.set_create_context_menu(.files, app_index, has_item, '', x, y)
			return true
		}
		d.close_create_context_menu()
		return false
	}
	if world == .desktop && underlying.starts_with(desktop_file_action_prefix) {
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
		|| action == file_context_paste || action == file_context_delete || action == file_context_tags
}

fn action_starts_rename(action string) bool {
	return action == create_context_new_folder || action == create_context_new_file
		|| action == file_context_rename
}

fn (mut d Desktop) desktop_context_action(action string, item_path string) ! {
	ensure_desktop_directory()!
	match action {
		create_context_new_folder, create_context_new_file {
			kind := if action == create_context_new_folder {
				CreateItemKind.folder
			} else {
				CreateItemKind.file
			}
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
	action, world := d.hit_action_world(x, y)
	if world == .application {
		d.close_create_context_menu()
		return false
	}
	if action == create_context_panel {
		d.trace_selector(action, world)
		create_context_menu.swallow_left_release = true
		return true
	}
	if !context_menu_action(action) {
		d.close_create_context_menu()
		return false
	}
	d.trace_selector(action, world)
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
					d.refresh_files_settings_clients(app_index)
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
		d.refresh_files_settings_clients(index)
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
					bg:     editor_path_focus
					radius: 4
				}, ui2.TextStyle{
					color: body_text
					size:  12
					align: .center
				}, 0)
		} else {
			icon_children << ui2.label('', entry.name, ui2.rect(0, f64(shortcut_icon + 16),
				f64(shortcut_width), 18), ui2.TextStyle{
				color:  if hovered { theme.shortcut_hover } else { theme.shortcut_label }
				shadow: true
				size:   12
				align:  .center
			})
		}
		icon := ui2.clickable_view(entry.row_action, ui2.rect(f64(x), f64(y), f64(shortcut_width),
			f64(shortcut_height)), ui2.BoxStyle{
			bg:          theme.shortcut_panel
			radius:      8
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
				bg:     if d.hover == entry.id { files_row_hover } else { app_surface }
				radius: 5
			}, ui2.TextStyle{
				color: body_text
				size:  13
				align: .left
			})
	}
	panel := ui2.clickable_view(create_context_panel, ui2.rect(f64(create_context_menu.x),
		f64(create_context_menu.y), f64(create_context_width), f64(height)), ui2.BoxStyle{
		bg:            app_surface
		radius:        7
		border_color:  body_rule
		border_left:   1
		border_top:    1
		border_right:  1
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
			if create_context_menu.target == .files {
				d.render_context_entries(create_context_files_item_entries)
			} else {
				d.render_context_entries(create_context_item_entries)
			}
		} else {
			d.render_context_entries(create_context_background_entries)
		}
	}
	// Both overlays are painted after render(), whose first cursor copy can be
	// covered by an icon or menu.
	d.draw_cursor()
}
