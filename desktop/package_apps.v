// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.packagecore
import json2
import ui2

__global packaged_apps = packagecore.Registry{}

fn (mut d Desktop) refresh_package_apps() {
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	changed := packaged_apps.refresh('/var/lib/vinix-packages', 0, architecture) or {
		packaged_apps.close()
		eprintln('vinix-desktop: package registration unavailable: ${err}')
		d.dirty = true
		return
	}
	if changed { d.dirty = true }
}

fn desktop_menu_count() int { return available_apps.len + packaged_apps.apps.len }

fn desktop_menu_name(index int) string {
	if index < available_apps.len { return available_apps[index].title }
	return packaged_apps.apps[index - available_apps.len].name
}

fn desktop_menu_matches(index int, query string) bool {
	if index < available_apps.len { return app_matches(available_apps[index].title, query) }
	app := &packaged_apps.apps[index - available_apps.len]
	return start_menu_matches(app.name, query) || start_menu_matches(app.id, query) || start_menu_matches(app.description, query)
}

fn (mut d Desktop) launch_menu_app(index int) {
	if index < 0 || index >= desktop_menu_count() { return }
	if index < available_apps.len {
		d.launch_index(index)
		return
	}
	d.launch_package(packaged_apps.apps[index - available_apps.len].id, '')
}

fn (mut d Desktop) launch_package(id string, document string) {
	request := packagecore.Request{ id: id, document: document }
	request.validate() or { return }
	// A new Software window owns each launch and displays stdout/failures. The
	// CLI keeps the immutable-generation lease until the sandbox exits.
	index := shortcut_app_index_named('vinix-software')
	if index < 0 { return }
	window := d.launch_index_window(index)
	if window == 0 { return }
	encoded := json2.encode(request)
	event := packagecore.request_prefix + encoded
	defer {
		unsafe {
			encoded.free()
			event.free()
		}
	}
	d.send_to_window(window, event)
}

fn (d &Desktop) package_menu_button(index int, x int, y int, width int, height int) ui2.Element {
	app := &packaged_apps.apps[index - available_apps.len]
	return ui2.button_with_image(app.start_action, app.name, 'builtin:window',
		ui2.rect(f64(x), f64(y), f64(width), f64(height)),
		ui2.BoxStyle{
			bg:     if d.hover == app.start_action {
				start_menu_item_hover
			} else {
				start_menu_left
			}
			radius: 4
		},
		ui2.TextStyle{ color: start_menu_text, size: 12, align: .left })
}
