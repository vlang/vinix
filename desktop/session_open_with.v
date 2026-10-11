// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.sessioncore
import ui2
import desktop.packagecore

fn (mut d Desktop) open_with(path string) {
	if !path.starts_with('/') || path.contains('\x00') { return }
	d.initialize_shell_hub()
	d.refresh_package_apps()
	d.hub.open_path.set(path) or { return }
	d.hub.open_default = false
	d.hub.open_page = 0
	for w in d.windows {
		if w.page == .open_with {
			d.activate(w.id)
			return
		}
	}
	d.spawn('Open With', .open_with, 150, 100, 520, 440)
}

fn open_with_builtin(name string) bool {
	return name in ['vinix-files', 'vinix-editor', 'vinix-preview', 'vinix-firefox', 'vinix-calendar']
}

fn (d &Desktop) open_with_count() int {
	mut count := 0
	for factory in available_apps { if open_with_builtin(factory.process_name) { count++ } }
	mime := sessioncore.mime_for_path(d.hub.open_path.str())
	for app in packaged_apps.apps { if app.accepts(mime) { count++ } }
	return count
}

fn (d &Desktop) open_with_contents(width int) []ui2.Element {
	mut out := frame_elements(10)
	out << body_line(d.hub.open_path.str(), 16, 14, width - 32)
	out << muted_line(sessioncore.mime_for_path(d.hub.open_path.str()), 16, 38, width - 32)
	mut y := 76
	mut slot := 0
	first := d.hub.open_page * 5
	for i, factory in available_apps {
		if !open_with_builtin(factory.process_name) { continue }
		if slot >= first && slot < first + 5 {
			out << settings_choice(d.hub.open_actions[i], factory.title, 16, y, width - 32, false)
			y += 38
		}
		slot++
	}
	mime := sessioncore.mime_for_path(d.hub.open_path.str())
	for app in packaged_apps.apps {
		if !app.accepts(mime) { continue }
		if slot >= first && slot < first + 5 {
			out << settings_choice(app.open_action, app.name, 16, y, width - 32, false)
			y += 38
		}
		slot++
	}
	out << settings_toggle('session.open.default', 'Use this application by default', 16, 280, width - 32, d.hub.open_default)
	if slot > 5 {
		out << settings_choice('session.open.previous', 'Previous applications', 16, 324, (width - 40) / 2, false)
		out << settings_choice('session.open.next', 'Next applications', width / 2 + 4, 324, (width - 40) / 2, false)
	}
	return out
}

fn (mut d Desktop) select_open_with(index int) {
	if index < 0 || index >= available_apps.len || d.hub.open_path.len == 0 { return }
	if !open_with_builtin(available_apps[index].process_name) { return }
	path := d.hub.open_path.str().clone()
	defer { unsafe { path.free() } }
	if d.hub.open_default {
		d.hub.associations.set(sessioncore.mime_for_path(path), available_apps[index].process_name, false) or { return }
		d.hub.association_overrides.set(sessioncore.mime_for_path(path), available_apps[index].process_name, false) or { return }
		d.save_associations()
	}
	for w in d.windows {
		if w.page == .open_with {
			d.close_window(w.id)
			break
		}
	}
	d.open_path_in_app(index, path)
}

fn (mut d Desktop) select_package_open_with(id string) {
	index := packaged_apps.find(id) or { return }
	path := d.hub.open_path.str().clone()
	defer { unsafe { path.free() } }
	app := &packaged_apps.apps[index]
	if !app.accepts(sessioncore.mime_for_path(path)) { return }
	if d.hub.open_default { d.session_associate_document(path, app.association) }
	for window in d.windows {
		if window.page == .open_with {
			d.close_window(window.id)
			break
		}
	}
	d.launch_package(id, path)
}

fn (mut d Desktop) open_document_in_handler(name string, path string) {
	if name.starts_with(packagecore.association_prefix) {
		d.refresh_package_apps()
		if id := packaged_apps.handler(name, sessioncore.mime_for_path(path)) {
			d.launch_package(id, path)
		}
		return
	}
	index := shortcut_app_index_named(name)
	if index >= 0 { d.open_path_in_app(index, path) }
}

fn (mut d Desktop) load_associations() {
	path := '${d.home}/.vinix-associations'
	defer { unsafe { path.free() } }
	record := sessioncore.load(path, 65536) or { return }
	defer { unsafe { record.free() } }
	associations := sessioncore.decode_associations(record) or { return }
	for i in 0 .. associations.count {
		a := associations.items[i]
		name := a.app.str()
		if shortcut_app_index_named(name) >= 0 || (name.starts_with(packagecore.association_prefix) && packagecore.identifier(unsafe { tos(name.str + packagecore.association_prefix.len, name.len - packagecore.association_prefix.len) })) {
			d.hub.associations.set(a.type.str(), a.app.str(), a.uri) or {}
			d.hub.association_overrides.set(a.type.str(), a.app.str(), a.uri) or {}
		}
	}
}

fn (d &Desktop) save_associations() {
	path := '${d.home}/.vinix-associations'
	record := d.hub.association_overrides.encode()
	defer {
		unsafe {
			path.free()
			record.free()
		}
	}
	sessioncore.save(path, record) or { eprintln('vinix-desktop: could not save associations: ${err}') }
}

// Files and launcher retain their format-specific fallbacks; a user's MIME
// choice is shared by every entry point that opens that document type.
fn (mut d Desktop) session_document_app(path string, fallback string) string {
	if info := desktop_stat(path) {
		if info.is_dir { return 'vinix-files' }
	}
	d.initialize_shell_hub()
	d.refresh_package_apps()
	return d.registered_document_app(path, fallback)
}

fn (d &Desktop) registered_document_app(path string, fallback string) string {
	mime := sessioncore.mime_for_path(path)
	if name := d.hub.association_overrides.resolve(mime, false) {
		if !name.starts_with(packagecore.association_prefix) || packaged_apps.handler(name, mime) != none {
			return name
		}
	}
	// Retain the user's choice on disk for rollback/reinstall, but use the
	// built-in fallback while its package or MIME permission is unavailable.
	if fallback.starts_with(packagecore.association_prefix) {
		if packaged_apps.handler(fallback, mime) != none { return fallback }
		return workflow_default_app(path)
	}
	return fallback
}

fn (mut d Desktop) session_associate_document(path string, app string) {
	if shortcut_app_index_named(app) < 0 {
		if packaged_apps.handler(app, sessioncore.mime_for_path(path)) == none { return }
	}
	d.initialize_shell_hub()
	kind := sessioncore.mime_for_path(path)
	d.hub.associations.set(kind, app, false) or { return }
	d.hub.association_overrides.set(kind, app, false) or { return }
	d.save_associations()
}

fn (mut d Desktop) begin_session_drop(m SessionMessage) {
	if m.count != 2 || !d.session_sender_has_gesture(m.pid) { return }
	path := m.fields[1].str()
	if !path.starts_with('/') || C.access(&char(path.str), C.R_OK) != 0 { return }
	d.hub.drop_path = m.fields[1]
	d.hub.drop_pid = m.pid
	d.hub.drop_active = true
	if d.hub.drop_released {
		_ = d.complete_session_drop(d.hub.drop_release_x, d.hub.drop_release_y)
		d.hub.drop_released = false
	}
}

fn (mut d Desktop) complete_session_drop(x int, y int) bool {
	if !d.hub.drop_active { return false }
	d.hub.drop_active = false
	for i := d.windows.len - 1; i >= 0; i-- {
		w := d.windows[i]
		if w.workspace != d.current_workspace || w.minimized || x < w.x || x >= w.x + w.width || y < w.y || y >= w.y + w.height {
			continue
		}
		if w.app_index < 0 || w.app_index >= d.apps.len { return true }
		action := '${jump_open_prefix}${d.hub.drop_path.str()}'
		mut app := d.apps[w.app_index]
		app.handle(action) or {}
		unsafe { action.free() }
		d.dirty = true
		return true
	}
	d.open_with(d.hub.drop_path.str())
	return true
}

// A compositor-generated request resolves the row in the real Files model;
// application-provided hit labels cannot forge paths for another process.
fn native_app_session_action(mut app NativeApp, action string) bool {
	if !action.starts_with('vinix.drag.row:') { return false }
	if mut app is FilesContextApp {
		app.select_action(action['vinix.drag.row:'.len..])
		if app.context_path.len == 0 { return true }
		args := ['drag.begin', app.context_path]
		_ = session_call_ok('action', args)
		unsafe { (&array(&args)).free() }
	}
	return true
}

fn (mut d Desktop) session_file_press(action string, x int, y int) bool {
	if !action.starts_with(files_action_row) && !action.starts_with(files_action_column_row) && !action.starts_with(files_action_pane_left_row) && !action.starts_with(files_action_pane_right_row) {
		return false
	}
	for w in d.windows {
		if w.id != d.focus || w.factory_index < 0 || available_apps[w.factory_index].process_name != 'vinix-files' {
			continue
		}
		d.hub.file_press.set(action) or { return false }
		d.hub.file_press_window = w.id
		d.hub.file_press_x = x
		d.hub.file_press_y = y
		d.hub.file_dragging = false
		d.hub.drop_released = false
		d.mark_session_gesture()
		return true
	}
	return false
}

fn (mut d Desktop) session_file_move(x int, y int) bool {
	if d.hub.file_press_window == 0 { return false }
	if !d.hub.file_dragging && (x - d.hub.file_press_x > 6 || d.hub.file_press_x - x > 6 || y - d.hub.file_press_y > 6 || d.hub.file_press_y - y > 6) {
		index := d.window_index(d.hub.file_press_window) or { return false }
		if d.windows[index].app_index >= 0 {
			mut app := d.apps[d.windows[index].app_index]
			action := 'vinix.drag.row:${d.hub.file_press.str()}'
			app.handle(action) or {}
			unsafe { action.free() }
			d.hub.file_dragging = true
			d.hub.polled_at = 0
		}
	}
	return true
}

fn (mut d Desktop) session_file_release(x int, y int) bool {
	if d.hub.file_press_window == 0 { return false }
	if !d.hub.file_dragging {
		index := d.window_index(d.hub.file_press_window) or {
			d.hub.file_press_window = 0
			return true
		}
		if d.windows[index].app_index >= 0 {
			mut app := d.apps[d.windows[index].app_index]
			app.handle(d.hub.file_press.str()) or {}
		}
	} else {
		d.hub.drop_released = true
		d.hub.drop_release_x = x
		d.hub.drop_release_y = y
		if d.hub.drop_active {
			_ = d.complete_session_drop(x, y)
			d.hub.drop_released = false
		}
	}
	d.hub.file_press_window = 0
	d.pointer_capture = 0
	d.chrome_pointer_capture = false
	d.dirty = true
	return true
}
