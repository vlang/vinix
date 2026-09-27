// SPDX-License-Identifier: GPL-2.0-or-later
// Files Settings is a separate native window backed by the Files executable.
module main

const files_settings_command_comma = '\x1b[44;9u'

fn files_settings_remove_shortcut(keys string) (string, bool) {
	mut kept := []u8{cap: keys.len}
	mut found := false
	mut at := 0
	for at < keys.len {
		if match_at(keys, at, files_settings_command_comma) > 0 {
			found = true
			at += files_settings_command_comma.len
			continue
		}
		kept << keys[at]
		at++
	}
	if !found {
		unsafe { kept.free() }
		return keys, false
	}
	rest := kept.bytestr()
	unsafe { kept.free() }
	return rest, true
}

fn (d &Desktop) focused_window_is_files_related() bool {
	for window in d.windows {
		if window.id == d.focus && !window.minimized {
			return window.title == 'Files' || window.title == files_settings_window_title
		}
	}
	return false
}

fn (mut d Desktop) take_files_settings_shortcut(keys string) string {
	if !d.focused_window_is_files_related() {
		return keys
	}
	rest, found := files_settings_remove_shortcut(keys)
	if found {
		d.open_files_settings_window()
	}
	return rest
}

fn (mut d Desktop) open_files_settings_window() {
	d.cancel_file_context_rename()
	for window in d.windows {
		if window.title == files_settings_window_title {
			d.activate(window.id)
			return
		}
	}
	d.launch(files_settings_factory())
}

// A Files window and its Settings window live in different processes. Send a
// readback after a preference or tag action so both show the saved state now.
fn (mut d Desktop) refresh_files_settings_clients(source_app_index int) {
	for window in d.windows {
		if window.app_index == source_app_index || window.app_index < 0
			|| window.app_index >= d.apps.len {
			continue
		}
		if window.title == 'Files' || window.title == files_settings_window_title {
			d.apps[window.app_index].handle(files_settings_refresh) or {
				eprintln('vinix-desktop: ${window.title}: ${err}')
			}
		}
	}
	d.dirty = true
}
