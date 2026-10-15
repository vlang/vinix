// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.sessioncore
import ui2

const shell_session_filename = '.vinix-window-session'

struct ShellSession {
mut:
	state             sessioncore.Windows
	saved             sessioncore.Windows
	loaded            bool
	saving            bool
	last_save_ms      i64
	failed            bool
	outputs           [8]sessioncore.Display
	output_count      int
	last_output_check i64
}

fn (d &Desktop) workspace_total() int { return d.session.state.workspace_count }

fn (mut d Desktop) configure_workspaces(count int) bool {
	d.session.state.configure(count) or { return false }
	for i in 0 .. d.windows.len {
		if d.windows[i].workspace >= count { d.windows[i].workspace = count - 1 }
	}
	if d.current_workspace >= count { d.switch_workspace(count - 1) }
	d.focus_top_window_in_current_workspace()
	d.dirty = true
	return true
}

fn (mut d Desktop) load_shell_session() {
	path := '${d.home}/${shell_session_filename}'
	defer { unsafe { path.free() } }
	record := sessioncore.load(path, 256 * 1024) or {
		d.session.loaded = true
		return
	}
	defer { unsafe { record.free() } }
	d.session.state = sessioncore.decode_windows(record) or {
		eprintln('vinix-desktop: ignoring invalid window session: ${err}')
		d.session.loaded = true
		return
	}
	d.session.loaded = true
	d.current_workspace = d.session.state.active
	d.shell_display_geometry()
}

fn (mut d Desktop) shell_display_geometry() {
	if d.session.output_count > 0 {
		displays := unsafe { d.session.outputs[..d.session.output_count] }
		d.session.state.update_displays(displays) or {}
		return
	}
	display := sessioncore.Display{
		id:      sessioncore.text('/dev/fb0') or { return }
		area:    sessioncore.Rect{ w: d.canvas.width, h: desktop_usable_height(d.canvas.height, d.taskbar_height()) }
		primary: true
	}
	displays := [display]
	d.session.state.update_displays(displays) or {}
	unsafe { displays.free() }
}

fn (mut d Desktop) restore_shell_session() bool {
	d.load_shell_session()
	if !d.session.state.restore_session || d.session.state.count == 0 { return false }
	active := d.current_workspace
	placements := d.session.state.windows
	count := d.session.state.count
	for slot in 0 .. count {
		p := placements[slot]
		d.current_workspace = p.workspace
		mut id := 0
		for index, factory in available_apps {
			if factory.process_name != p.app.str() || factory.exclusive_command.len > 0 { continue }
			if p.failed {
				id = d.spawn(factory.title, .app, p.frame.x, p.frame.y, p.frame.w, p.frame.h)
				wi := d.window_index(id) or { continue }
				d.windows[wi].factory_index = index
				d.windows[wi].recovery = true
			} else {
				id = d.launch_index_window(index)
				if id == 0 {
					id = d.spawn(factory.title, .app, p.frame.x, p.frame.y, p.frame.w, p.frame.h)
					wi := d.window_index(id) or { continue }
					d.windows[wi].factory_index = index
					d.windows[wi].recovery = true
				}
			}
			break
		}
		if p.app.str() == 'builtin.system' {
			id = d.spawn('System', .system, p.frame.x, p.frame.y, p.frame.w, p.frame.h)
		}
		if id == 0 { continue }
		index := d.window_index(id) or { continue }
		d.windows[index].x = p.frame.x
		d.windows[index].y = p.frame.y
		d.windows[index].width = p.frame.w
		d.windows[index].height = p.frame.h
		d.windows[index].restore_x = p.restore.x
		d.windows[index].restore_y = p.restore.y
		d.windows[index].restore_width = p.restore.w
		d.windows[index].restore_height = p.restore.h
		d.windows[index].maximized = p.maximized
		d.windows[index].minimized = p.minimized
		d.windows[index].snap = unsafe { WindowSnap(p.snap) }
		d.windows[index].group = p.group
		d.windows[index].display = p.display
		d.clamp_to_screen(index)
	}
	d.current_workspace = active
	d.focus_top_window_in_current_workspace()
	d.session.saving = true
	return d.windows.len > 0
}

fn (mut d Desktop) capture_shell_session() {
	d.session.state.active = d.current_workspace
	d.session.state.count = 0
	for window in d.windows {
		if d.session.state.count == sessioncore.max_windows { break }
		mut app_name := ''
		if window.factory_index >= 0 && window.factory_index < available_apps.len {
			app_name = available_apps[window.factory_index].process_name
		} else if window.page == .system {
			app_name = 'builtin.system'
		}
		if app_name.len == 0 { continue }
		mut instance := 0
		for i in 0 .. d.session.state.count {
			if d.session.state.windows[i].app.str() == app_name { instance++ }
		}
		mut failed := window.recovery
		if window.app_index >= 0 && window.app_index < d.apps.len {
			app := d.apps[window.app_index]
			if app is RemoteApp { failed = app.closed }
		}
		mut display := window.display
		if display.len == 0 {
			for i in 0 .. d.session.state.display_count {
				area := d.session.state.displays[i].area
				if window.x + window.width / 2 >= area.x && window.x + window.width / 2 < area.x + area.w {
					display = d.session.state.displays[i].id
					break
				}
			}
		}
		if display.len == 0 { display = sessioncore.text('/dev/fb0') or { continue } }
		p := sessioncore.Placement{
			app:       sessioncore.text(app_name) or { continue }
			instance:  instance
			display:   display
			workspace: window.workspace
			group:     window.group
			frame:     sessioncore.Rect{window.x, window.y, window.width, window.height}
			restore:   sessioncore.Rect{window.restore_x, window.restore_y, window.restore_width, window.restore_height}
			maximized: window.maximized
			minimized: window.minimized
			snap:      int(window.snap)
			failed:    failed
		}
		d.session.state.windows[d.session.state.count] = p
		d.session.state.count++
	}
	for i in d.session.state.count .. sessioncore.max_windows {
		d.session.state.windows[i] = sessioncore.Placement{}
	}
}

fn (mut d Desktop) save_shell_session(force bool) {
	if !d.session.saving { return }
	now := monotonic_millis()
	if !force && (d.drag.kind != .none_ || now - d.session.last_save_ms < 2000) { return }
	d.session.last_save_ms = now
	d.capture_shell_session()
	if !force && d.session.state == d.session.saved { return }
	path := '${d.home}/${shell_session_filename}'
	data := d.session.state.encode()
	defer {
		unsafe {
			path.free()
			data.free()
		}
	}
	sessioncore.save(path, data) or {
		d.session.failed = true
		eprintln('vinix-desktop: could not save window session: ${err}')
		return
	}
	d.session.failed = false
	d.session.saved = d.session.state
}

fn (mut d Desktop) arrange_workspace(layout sessioncore.Layout) {
	d.capture_shell_session()
	d.shell_display_geometry()
	d.session.state.set_layout(d.current_workspace, layout, 8) or { return }
	mut slot := 0
	for i in 0 .. d.windows.len {
		if d.windows[i].factory_index < 0 && d.windows[i].page != .system { continue }
		if slot >= d.session.state.count { break }
		p := d.session.state.windows[slot]
		slot++
		d.windows[i].x = p.frame.x
		d.windows[i].y = p.frame.y
		d.windows[i].width = p.frame.w
		d.windows[i].height = p.frame.h
		d.windows[i].maximized = p.maximized
		d.windows[i].snap = unsafe { WindowSnap(p.snap) }
	}
	d.dirty = true
}

fn (mut d Desktop) retry_session_window(id int) {
	index := d.window_index(id) or { return }
	factory := d.windows[index].factory_index
	if factory < 0 || factory >= available_apps.len { return }
	w := d.windows[index]
	d.close_window(id)
	new_id := d.launch_index_window(factory)
	i := d.window_index(new_id) or { return }
	d.windows[i].x = w.x
	d.windows[i].y = w.y
	d.windows[i].width = w.width
	d.windows[i].height = w.height
	d.windows[i].workspace = w.workspace
	d.windows[i].group = w.group
	d.clamp_to_screen(i)
}

fn (d &Desktop) session_recovery_contents(index int, width int) []ui2.Element {
	mut out := frame_elements(3)
	out << body_line('The application stopped responding or exited.', 18, 18, width - 36)
	out << muted_line('Restart it to recover this window.', 18, 42, width - 36)
	out << settings_choice(d.windows[index].id_retry, 'Restart application', 18, 72, width - 36, false)
	return out
}
