// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Right-click creation menu shared by the wallpaper and Files.
module main

import ui2

#include <sys/stat.h>

fn C.mkdir(path &char, mode u32) i32

const create_context_new_folder = 'files.create.folder'
const create_context_new_file = 'files.create.file'
const create_context_panel = 'context.create.panel'
const create_context_width = 180
const create_context_padding = 4
const create_context_row_height = 30
const create_context_height = 2 * create_context_row_height + 2 * create_context_padding
const create_context_name_attempts = 1000

const create_context_entries = [
	ui2.MenuEntry{
		id: create_context_new_folder
		title: 'New Folder'
	},
	ui2.MenuEntry{
		id: create_context_new_file
		title: 'New File'
	},
]

enum CreateContextTarget {
	none_
	desktop
	files
}

enum CreateItemKind {
	file
	folder
}

struct CreateContextMenuState {
mut:
	visible               bool
	target                CreateContextTarget
	x                     int
	y                     int
	app_index             int = -1
	swallow_left_release  bool
	swallow_right_release bool
}

__global create_context_menu = CreateContextMenuState{}

// FilesContextApp keeps the ordinary browser untouched and only adds the two
// creation actions emitted by the compositor-owned context menu.
struct FilesContextApp {
mut:
	files FileBrowserApp
}

fn open_files_with_context_menu(mut _ Desktop) !NativeApp {
	mut app := &FilesContextApp{}
	app.files.browser.read(desktop_home)
	if app.files.browser.error != '' {
		// Keep the same fallback as open_files(): a missing persistent home
		// should not make the immutable system tree unreachable.
		unsafe { app.files.browser.error.free() }
		app.files.browser.error = ''
		app.files.browser.read('/')
	}
	if app.files.browser.error != '' {
		return error(app.files.browser.error)
	}
	return app
}

fn (mut a FilesContextApp) build(size ui2.Rect) !ui2.Element {
	return a.files.build(size)
}

fn (mut a FilesContextApp) handle(event_id string) ! {
	match event_id {
		create_context_new_folder {
			a.create_item(.folder)!
			return
		}
		create_context_new_file {
			a.create_item(.file)!
			return
		}
		else {}
	}
	a.files.handle(event_id)!
}

fn (mut a FilesContextApp) create_item(kind CreateItemKind) ! {
	path := a.files.current_path().clone()
	create_unique_item(path, kind) or {
		unsafe { path.free() }
		return err
	}
	if a.files.view_mode == .columns {
		a.files.reset_miller_columns(path)
		unsafe { path.free() }
		return
	}
	// FileBrowser.read takes ownership of path when it succeeds, exactly as
	// normal navigation does.
	a.files.browser.read(path)
}

fn create_item_base_name(kind CreateItemKind) string {
	return match kind {
		.file { 'New File' }
		.folder { 'New Folder' }
	}
}

fn create_item_path(directory string, name string) string {
	if directory == '/' {
		return '/${name}'
	}
	if directory.ends_with('/') {
		return '${directory}${name}'
	}
	return '${directory}/${name}'
}

fn create_unique_item(directory string, kind CreateItemKind) ! {
	base := create_item_base_name(kind)
	for attempt in 0 .. create_context_name_attempts {
		name := if attempt == 0 { base } else { '${base} (${attempt + 1})' }
		path := create_item_path(directory, name)
		if desktop_stat(path) == none {
			ok := match kind {
				.file {
					fd := desktop_create_truncated(path)
					if fd >= 0 {
						desktop_close(fd)
						true
					} else {
						false
					}
				}
				.folder { C.mkdir(&char(path.str), 0o755) == 0 }
			}
			if !ok {
				message := 'cannot create ${path}'
				unsafe {
					path.free()
					if attempt > 0 { name.free() }
				}
				return error(message)
			}
			unsafe {
				path.free()
				if attempt > 0 { name.free() }
			}
			return
		}
		unsafe {
			path.free()
			if attempt > 0 { name.free() }
		}
	}
	return error('cannot find an unused ${base} name in ${directory}')
}

fn (mut d Desktop) set_create_context_menu(target CreateContextTarget, app_index int, x int, y int) {
	mut menu_x := x
	mut menu_y := y
	if menu_x + create_context_width > d.canvas.width {
		menu_x = d.canvas.width - create_context_width
	}
	if menu_y + create_context_height > d.canvas.height {
		menu_y = d.canvas.height - create_context_height
	}
	if menu_x < 0 {
		menu_x = 0
	}
	if menu_y < 0 {
		menu_y = 0
	}
	create_context_menu.visible = true
	create_context_menu.target = target
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
	create_context_menu.app_index = -1
	d.hover = ''
	d.dirty = true
}

// open_create_context_menu gives Files first refusal, then only treats truly
// empty wallpaper as the desktop. Other windows, shortcuts and the taskbar
// keep their existing right-click behavior.
fn (mut d Desktop) open_create_context_menu(x int, y int) bool {
	if d.switcher.active || d.start_menu_open {
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
			d.raise(window_id)
			d.set_create_context_menu(.files, app_index, x, y)
			return true
		}
		d.close_create_context_menu()
		return false
	}
	if y >= d.canvas.height - taskbar_height || d.hit_action(x, y) != '' {
		d.close_create_context_menu()
		return false
	}
	d.set_create_context_menu(.desktop, -1, x, y)
	return true
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
	if action != create_context_new_folder && action != create_context_new_file {
		d.close_create_context_menu()
		return false
	}
	target := create_context_menu.target
	app_index := create_context_menu.app_index
	kind := if action == create_context_new_folder { CreateItemKind.folder } else { CreateItemKind.file }
	create_context_menu.swallow_left_release = true
	d.close_create_context_menu()
	match target {
		.desktop {
			create_unique_item(desktop_home, kind) or {
				eprintln('vinix-desktop: ${err}')
			}
		}
		.files {
			if app_index >= 0 && app_index < d.apps.len {
				d.apps[app_index].handle(action) or {
					eprintln('vinix-desktop: Files: ${err}')
				}
			}
		}
		.none_ {}
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

fn (mut d Desktop) render_create_context_menu() {
	if !create_context_menu.visible {
		return
	}
	mut children := frame_elements(create_context_entries.len)
	for index, entry in create_context_entries {
		y := create_context_padding + index * create_context_row_height
		children << ui2.button(entry.id, entry.title, ui2.rect(f64(create_context_padding), f64(y), f64(create_context_width - 2 * create_context_padding), f64(create_context_row_height)), ui2.BoxStyle{
			bg: if d.hover == entry.id { files_row_hover } else { app_surface }
			radius: 5
		}, ui2.TextStyle{
			color: body_text
			size: 13
			align: .left
		})
	}
	panel := ui2.clickable_view(create_context_panel, ui2.rect(f64(create_context_menu.x), f64(create_context_menu.y), f64(create_context_width), f64(create_context_height)), ui2.BoxStyle{
		bg: app_surface
		radius: 7
		border_color: body_rule
		border_left: 1
		border_top: 1
		border_right: 1
		border_bottom: 1
	}, children)
	// Render after the normal tree so the menu floats over windows and the
	// taskbar, then repaint the pointer because the menu may cover its first
	// copy from render().
	d.render_element(panel, 0, 0, 2)
	d.draw_cursor()
	free_tree(panel)
}
