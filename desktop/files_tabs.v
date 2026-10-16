// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import desktop.workflowcore

struct FilesTab {
mut:
	path string
	mode FilesViewMode
	scroll int
	back []string
	forward []string
	selection []string
	action string
}

fn (mut a FilesContextApp) ensure_tabs() {
	if a.tabs.len == 0 { a.tabs << FilesTab{path: a.files.current_path().clone(), mode: a.files.view_mode, action: 'files.tab.0'} }
}

fn (mut tab FilesTab) close() {
	workflow_free_strings(tab.back)
	workflow_free_strings(tab.forward)
	workflow_free_strings(tab.selection)
	unsafe { tab.path.free(); tab.action.free() }
	tab = FilesTab{}
}

fn (mut a FilesContextApp) save_tab() {
	a.ensure_tabs()
	mut tab := &a.tabs[a.active_tab]
	workflow_free_strings(tab.back)
	workflow_free_strings(tab.forward)
	workflow_free_strings(tab.selection)
	unsafe { tab.path.free() }
	tab.path = a.files.current_path().clone()
	tab.mode = a.files.view_mode
	tab.scroll = a.files.browser.scroll
	tab.back = a.files.history_back.map(it.clone())
	tab.forward = a.files.history_forward.map(it.clone())
	tab.selection = a.selection.map(it.clone())
}

fn (mut a FilesContextApp) switch_tab(index int) {
	if index < 0 || index >= a.tabs.len || index == a.active_tab { return }
	a.save_tab()
	a.active_tab = index
	tab := &a.tabs[index]
	a.clear_selection_paths()
	a.clear_context_path()
	a.files.end_search()
	a.files.set_view_mode(tab.mode)
	a.files.navigate_to(tab.path)
	a.files.browser.scroll = tab.scroll
	files_history_clear(mut a.files.history_back)
	files_history_clear(mut a.files.history_forward)
	unsafe { a.files.history_path.free() }
	a.files.history_path = tab.path.clone()
	for path in tab.back { files_history_push(mut a.files.history_back, path.clone()) }
	for path in tab.forward { files_history_push(mut a.files.history_forward, path.clone()) }
	a.selection = tab.selection.map(it.clone())
	unsafe { a.selection_directory.free() }
	a.selection_directory = a.files.current_path().clone()
}

fn (mut a FilesContextApp) tab_action(event string) bool {
	if event == 'files.selection.toggle' { a.multi_select = !a.multi_select; return true }
	if event == 'files.selection.all' {
		a.clear_selection_paths()
		if a.files.active_tag_id >= 0 {
			paths := a.files.settings.tagged_paths(a.files.active_tag_id)
			for path in paths { a.selection << path.clone() }
			unsafe { paths.free() }
		} else if a.files.view_mode == .columns && a.files.columns.len > 0 {
			browser := &a.files.columns[a.files.columns.len - 1].browser
			for entry in browser.entries { a.selection << files_child_path(browser.path, entry.name) }
		} else if a.files.view_mode == .list {
			for entry in a.files.browser.entries { a.selection << files_child_path(a.files.browser.path, entry.name) }
		} else if a.files.view_mode == .commander {
			browser := if a.files.active_pane == 0 { &a.files.dual_left } else { &a.files.dual_right }
			for entry in browser.entries { a.selection << files_child_path(browser.path, entry.name) }
		}
		unsafe { a.selection_directory.free() }
		a.selection_directory = a.files.current_path().clone()
		a.multi_select = true
		return true
	}
	if event == 'files.tab.new' {
		a.ensure_tabs()
		if a.tabs.len >= 8 { return true }
		a.tabs << FilesTab{path: a.files.current_path().clone(), mode: a.files.view_mode, action: 'files.tab.${a.tabs.len}'}
		a.switch_tab(a.tabs.len - 1)
		return true
	}
	if event == 'files.tab.close' {
		a.ensure_tabs()
		if a.tabs.len <= 1 { return true }
		old := a.active_tab
		a.switch_tab(if old > 0 { old - 1 } else { 1 })
		a.tabs[old].close()
		a.tabs.delete(old)
		if a.active_tab > old { a.active_tab-- }
		for i in 0 .. a.tabs.len { unsafe { a.tabs[i].action.free() }; a.tabs[i].action = 'files.tab.${i}' }
		return true
	}
	if event.starts_with('files.tab.') { a.switch_tab(event['files.tab.'.len..].int()); return true }
	return false
}

fn (a &FilesContextApp) is_row_action(event string) bool {
	return event.starts_with(files_action_row) || event.starts_with(files_action_pane_left_row) || event.starts_with(files_action_pane_right_row) || event.starts_with(files_action_tag_row) || parse_miller_row_action(event) != none
}

fn (a &FilesContextApp) row_path(action string) string {
	if action.starts_with(files_action_tag_row) {
		paths := a.files.settings.tagged_paths(a.files.active_tag_id)
		defer { unsafe { paths.free() } }
		i := action[files_action_tag_row.len..].int()
		return if i >= 0 && i < paths.len { paths[i].clone() } else { '' }
	}
	if row := parse_miller_row_action(action) {
		for col in a.files.columns { if col.id == row.column_id && row.row >= 0 && row.row < col.browser.entries.len { return files_child_path(col.browser.path, col.browser.entries[row.row].name) } }
		return ''
	}
	mut browser := &a.files.browser
	mut prefix := files_action_row
	if action.starts_with(files_action_pane_left_row) { browser = &a.files.dual_left; prefix = files_action_pane_left_row }
	else if action.starts_with(files_action_pane_right_row) { browser = &a.files.dual_right; prefix = files_action_pane_right_row }
	if !action.starts_with(prefix) { return '' }
	i := action[prefix.len..].int()
	if i < 0 || i >= browser.entries.len { return '' }
	return files_child_path(browser.path, browser.entries[i].name)
}

fn (a &FilesContextApp) highlight_selection(mut element ui2.Element) {
	if a.is_row_action(element.id) {
		path := a.row_path(element.id)
		if a.selection.index(path) >= 0 { element = ui2.Element{...element, box: ui2.BoxStyle{...element.box, bg: files_sidebar_selected, transparent: false}} }
		thumbnail := files_thumbnail_image(path)
		if thumbnail.len > 0 { element = ui2.Element{...element, image_path: thumbnail, key: workflow_owned_image_key} }
		unsafe { path.free() }
	}
	for i in 0 .. element.children.len { a.highlight_selection(mut element.children[i]) }
}

// A single folder needs no tab strip. Tab commands live in the context menu
// and keep their keyboard shortcuts even while the strip is hidden.
fn (a &FilesContextApp) tabs_height() int {
	return if a.tabs.len > 1 { 30 } else { 0 }
}

fn (a &FilesContextApp) browser_height(height int) int {
	available := height - a.tabs_height() - 34 - if a.operation_open { 66 } else { 0 }
	return if available > 0 { available } else { 1 }
}

fn (mut a FilesContextApp) tab_strip(size ui2.Rect) []ui2.Element {
	a.ensure_tabs()
	mut rows := frame_elements(a.tabs.len)
	if a.tabs.len <= 1 { return rows }
	width := int(size.width) / a.tabs.len
	top := if files_catalina { files_header_height() } else { 0 }
	for i, tab in a.tabs {
		path := if i == a.active_tab { a.files.current_path() } else { tab.path }
		rows << ui2.button(tab.action, file_path_name(path), ui2.rect(f64(i * width), f64(top), f64(width), 30), ui2.BoxStyle{bg: if i == a.active_tab { body_panel } else { app_surface }}, ui2.TextStyle{color: body_text, size: 11})
	}
	return rows
}

fn (a &FilesContextApp) path_at(x int, y int, width int) string {
	if y < a.files.rows_top || y >= a.files.rows_top + a.files.rows_height || x < files_content_left(width) { return '' }
	if a.files.active_tag_id >= 0 {
		if y < a.files.rows_top + 26 { return '' }
		paths := a.files.settings.tagged_paths(a.files.active_tag_id)
		defer { unsafe { paths.free() } }
		i := (y - a.files.rows_top - 26) / files_row_height() + a.files.browser.scroll
		return if i >= 0 && i < paths.len { paths[i].clone() } else { '' }
	}
	row := (y - a.files.rows_top) / files_row_height()
	if a.files.view_mode == .commander {
		pane := files_commander_pane_at(x, width)
		if pane < 0 { return '' }
		browser := if pane == 0 { &a.files.dual_left } else { &a.files.dual_right }
		i := row + browser.scroll
		if i >= browser.entries.len { return '' }
		return files_child_path(browser.path, browser.entries[i].name)
	}
	if a.files.view_mode == .columns {
		if a.files.column_width <= 0 { return '' }
		col := (x - files_content_left(width) + a.files.column_offset) / a.files.column_width
		if col < 0 || col >= a.files.columns.len { return '' }
		browser := &a.files.columns[col].browser
		i := row + browser.scroll
		if i >= browser.entries.len { return '' }
		return files_child_path(browser.path, browser.entries[i].name)
	}
	i := row + a.files.browser.scroll
	if i < 0 || i >= a.files.browser.entries.len { return '' }
	return files_child_path(a.files.browser.path, a.files.browser.entries[i].name)
}

fn (mut a FilesContextApp) workflow_drag(phase AppPointerPhase, button AppPointerButton, x int, y int, width int) bool {
	if phase == .down && button == .left {
		unsafe { a.drag_path.free() }
		a.drag_path = a.path_at(x, y, width)
		a.drag_start_x = x
		a.drag_start_y = y
		a.drag_active = false
	}
	if phase == .move && a.drag_path.len > 0 {
		if x - a.drag_start_x > 8 || a.drag_start_x - x > 8 || y - a.drag_start_y > 8 || a.drag_start_y - y > 8 { a.drag_active = true }
		return a.drag_active
	}
	if phase == .up && a.drag_path.len > 0 {
		active := a.drag_active
		if active {
			path := a.path_at(x, y, width)
			if info := desktop_stat(path) {
				if info.is_dir {
					paths := if a.selection.index(a.drag_path) >= 0 { a.selection.map(it.clone()) } else { [a.drag_path.clone()] }
					a.start_transfer(paths, path, workflowcore.TransferKind.copy) or { a.operation_error(err.msg()) }
					workflow_free_strings(paths)
				}
			}
			unsafe { path.free() }
			a.suppress_row_once = true
		}
		unsafe { a.drag_path.free() }
		a.drag_path = ''
		a.drag_active = false
		return active
	}
	return false
}

fn (mut a FilesContextApp) workflow_key(input string) bool {
	match input {
		'\x14' { a.tab_action('files.tab.new'); return true }
		'\x17' { a.tab_action('files.tab.close'); return true }
		'\x01' { a.tab_action('files.selection.all'); return true }
		'\x03' { a.operation_action('files.batch.copy'); return true }
		'\x18' { a.operation_action('files.batch.cut'); return true }
		'\x16' { a.operation_action('files.batch.paste'); return true }
		'\x1a' { a.operation_action('files.operation.undo'); return true }
		'\x1b[3~' { a.operation_action('files.batch.delete'); return true }
		else { return false }
	}
}

fn (mut a FilesContextApp) close_workflows() {
	if a.worker_pid > 0 { C.kill(a.worker_pid, C.SIGTERM); mut status := 0; C.waitpid(a.worker_pid, unsafe { &status }, C.WNOHANG); a.worker_pid = 0 }
	a.clear_selection_paths()
	for i in 0 .. a.tabs.len { a.tabs[i].close() }
	for undo in a.undo_operations { unsafe { undo.source.free(); undo.destination.free(); undo.trash_root.free(); undo.trash_bucket.free(); undo.backup.free() } }
	unsafe { a.selection.free(); a.selection_directory.free(); a.tabs.free(); a.undo_operations.free(); a.job_path.free(); a.drag_path.free(); a.operation.label.free(); a.operation.message.free() }
	a.selection = []string{}
	a.selection_directory = ''
	a.tabs = []FilesTab{}
	a.undo_operations = []FilesUndo{}
	a.job_path = ''
	a.drag_path = ''
	a.operation = FilesTransferReport{}
}
