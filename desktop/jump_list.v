// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Jump Lists: the menu a taskbar button opens on right-click.
//
// Like Windows 7's, it lists the program's recent documents or folders, then
// the tasks the program offers, then the program itself, pinning and closing.
// Recent items come from the shared history the applications write (see
// recent_items.v); tasks are declared here per process name. Opening an item
// starts a new window of the program and hands it the path over the ordinary
// action pipe, so no program needs a command line to be opened on something.
module main

import ui2

// Sent to an application process to open a document or folder. It is only
// ever produced by the compositor, never forwarded from a hit target.
const jump_open_prefix = 'vinix.open:'
const taskbar_context_close_all = 'taskbar.context.closeall'
const jump_list_actions = ['taskbar.jump.0', 'taskbar.jump.1', 'taskbar.jump.2', 'taskbar.jump.3',
	'taskbar.jump.4', 'taskbar.jump.5', 'taskbar.jump.6', 'taskbar.jump.7', 'taskbar.jump.8',
	'taskbar.jump.9', 'taskbar.jump.10', 'taskbar.jump.11', 'taskbar.jump.12', 'taskbar.jump.13',
	'taskbar.jump.14', 'taskbar.jump.15', 'taskbar.jump.16', 'taskbar.jump.17', 'taskbar.jump.18',
	'taskbar.jump.19']
const jump_list_prefix = 'taskbar.jump.'
const jump_list_width = 264
const jump_list_padding = 4
const jump_list_header_height = 26
const jump_list_row_height = 30
const jump_list_separator_height = 9
const jump_list_footer_bg = u32(0xeef2f7)

enum JumpEntryKind {
	header
	separator
	item
}

enum JumpCommand {
	none_
	open_path
	launch
	settings_page
	capture_screenshot
	pin
	unpin
	close_window
	close_all
}

// A task's path is absolute, or a folder in the user's home -- which is only
// known at run time -- when it does not start with a slash.
struct JumpTask {
	title   string
	icon    string
	command JumpCommand
	path    string
	arg     int
}

struct JumpEntry {
	kind    JumpEntryKind
	id      string
	title   string
	icon    string
	command JumpCommand
	path    string
	arg     int
	// Recent items own their title and path; everything else is a literal.
	owned bool
	// The part below the rule -- the program, pinning, closing -- sits on a
	// tinted footer, as it did on Windows 7.
	footer bool
}

struct JumpList {
mut:
	entries   []JumpEntry
	app_index int = -1
	windows   []int
	height    int
}

__global taskbar_jump_list = JumpList{}

const files_jump_tasks = [
	JumpTask{
		title:   'Home'
		icon:    'builtin:home'
		command: .open_path
		path:    ''
	},
	JumpTask{
		title:   'Documents'
		icon:    'builtin:documents'
		command: .open_path
		path:    'Documents'
	},
	JumpTask{
		title:   'Downloads'
		icon:    'builtin:downloads'
		command: .open_path
		path:    'Downloads'
	},
	JumpTask{
		title:   'Computer'
		icon:    'builtin:drive'
		command: .open_path
		path:    '/'
	},
]
const editor_jump_tasks = [
	JumpTask{
		title:   'New document'
		icon:    'builtin:file'
		command: .launch
	},
]
const settings_jump_tasks = [
	JumpTask{
		title:   'Wallpaper'
		icon:    'builtin:desktop'
		command: .settings_page
		arg:     3
	},
	JumpTask{
		title:   'Display'
		icon:    'builtin:brightness'
		command: .settings_page
		arg:     5
	},
	JumpTask{
		title:   'Wi-Fi'
		icon:    'builtin:network_wifi'
		command: .settings_page
		arg:     4
	},
	JumpTask{
		title:   'Battery'
		icon:    'builtin:battery_70'
		command: .settings_page
		arg:     6
	},
]
const capture_jump_tasks = [
	JumpTask{
		title:   'Take screenshot'
		icon:    'builtin:camera'
		command: .capture_screenshot
	},
]
const terminal_jump_tasks = [
	JumpTask{
		title:   'New window'
		icon:    'builtin:terminal'
		command: .launch
	},
]
const no_jump_tasks = []JumpTask{}

fn jump_list_tasks(process_name string) []JumpTask {
	return match process_name {
		'vinix-files' { files_jump_tasks }
		'vinix-editor' { editor_jump_tasks }
		'vinix-settings' { settings_jump_tasks }
		'vinix-capture' { capture_jump_tasks }
		'vinix-terminal' { terminal_jump_tasks }
		else { no_jump_tasks }
	}
}

// Only programs that record what they open have a Recent section.
fn jump_list_has_recent(process_name string) bool {
	return process_name == 'vinix-files' || process_name == 'vinix-editor'
}

// user_folder_path returns an owned absolute path for a Jump List task: the
// user's home, a folder in it, or an absolute path as given.
fn user_folder_path(path string) string {
	if path.starts_with('/') {
		return path.clone()
	}
	home := if desktop_user_home.len > 0 { desktop_user_home } else { desktop_home }
	if path.len == 0 {
		return home.clone()
	}
	return '${home}/${path}'
}

fn free_jump_list() {
	for entry in taskbar_jump_list.entries {
		if entry.owned {
			unsafe {
				entry.title.free()
				entry.path.free()
			}
		}
	}
	taskbar_jump_list.entries.clear()
	taskbar_jump_list.windows.clear()
	taskbar_jump_list.app_index = -1
	taskbar_jump_list.height = 0
}

fn jump_list_entry_height(kind JumpEntryKind) int {
	return match kind {
		.header { jump_list_header_height }
		.separator { jump_list_separator_height }
		.item { jump_list_row_height }
	}
}

fn jump_list_push(kind JumpEntryKind, title string, icon string, command JumpCommand, path string,
	arg int, owned bool, footer bool) {
	mut id := ''
	if kind == .item {
		mut count := 0
		for entry in taskbar_jump_list.entries {
			if entry.kind == .item {
				count++
			}
		}
		if count >= jump_list_actions.len {
			if owned {
				unsafe {
					title.free()
					path.free()
				}
			}
			return
		}
		id = jump_list_actions[count]
	}
	taskbar_jump_list.entries << JumpEntry{
		kind:    kind
		id:      id
		title:   title
		icon:    icon
		command: command
		path:    path
		arg:     arg
		owned:   owned
		footer:  footer
	}
	taskbar_jump_list.height += jump_list_entry_height(kind)
}

// build_jump_list collects everything the menu shows when it opens. The recent
// history is read from disk here rather than each frame, since another
// process may have added to it since the last time.
fn (d &Desktop) build_jump_list(entry TaskbarEntry) {
	free_jump_list()
	if entry.app_index < 0 || entry.app_index >= available_apps.len {
		return
	}
	factory := &available_apps[entry.app_index]
	taskbar_jump_list.app_index = entry.app_index
	ids := d.taskbar_entry_window_ids(entry)
	for id in ids {
		taskbar_jump_list.windows << id
	}
	unsafe { ids.free() }
	taskbar_jump_list.height = 2 * jump_list_padding

	if jump_list_has_recent(factory.process_name) {
		items := recent_items_for(d.home, factory.process_name, recent_items_per_app)
		if items.len > 0 {
			jump_list_push(.header, 'Recent', '', .none_, '', 0, false, false)
		}
		for item in items {
			is_dir := if info := desktop_stat(item.path) { info.is_dir } else { false }
			jump_list_push(.item, recent_item_title(item.path), if is_dir {
				'builtin:folder'
			} else {
				'builtin:file'
			}, .open_path, item.path, 0, true, false)
			unsafe { item.app.free() }
		}
		if items.cap > 0 {
			unsafe { items.free() }
		}
	}
	tasks := jump_list_tasks(factory.process_name)
	if tasks.len > 0 {
		jump_list_push(.header, 'Tasks', '', .none_, '', 0, false, false)
		for task in tasks {
			if task.command == .open_path {
				// The title is a literal, which freeing leaves alone.
				jump_list_push(.item, task.title, task.icon, task.command, user_folder_path(task.path),
					task.arg, true, false)
			} else {
				jump_list_push(.item, task.title, task.icon, task.command, task.path, task.arg,
					false, false)
			}
		}
	}
	if taskbar_jump_list.entries.len > 0 {
		jump_list_push(.separator, '', '', .none_, '', 0, false, true)
	}
	jump_list_push(.item, factory.title, factory.icon, .launch, '', 0, false, true)
	if d.taskbar_is_pinned(entry.app_index) {
		jump_list_push(.item, 'Unpin this program from taskbar', 'builtin:arrow_down', .unpin,
			'', 0, false, true)
	} else {
		jump_list_push(.item, 'Pin this program to taskbar', 'builtin:arrow_up', .pin, '', 0,
			false, true)
	}
	if taskbar_jump_list.windows.len == 1 {
		jump_list_push(.item, 'Close window', 'builtin:close', .close_window, '', 0, false, true)
	} else if taskbar_jump_list.windows.len > 1 {
		jump_list_push(.item, 'Close all windows', 'builtin:close', .close_all, '', 0, false,
			true)
	}
}

fn jump_list_entry_for(action string) ?JumpEntry {
	for entry in taskbar_jump_list.entries {
		if entry.kind == .item && entry.id == action {
			return entry
		}
	}
	return none
}

// place_jump_list rises from the taskbar above the button, instead of hanging
// from the pointer the way a context menu does.
fn (d &Desktop) place_jump_list(x int) {
	height := if taskbar_jump_list.height > 0 {
		taskbar_jump_list.height
	} else {
		context_menu_height(.desktop, false)
	}
	mut menu_x := x - jump_list_width / 2
	if menu_x + jump_list_width > d.canvas.width - 4 {
		menu_x = d.canvas.width - 4 - jump_list_width
	}
	if menu_x < 4 {
		menu_x = 4
	}
	mut menu_y := d.canvas.height - taskbar_height - height - 4
	if menu_y < 0 {
		menu_y = 0
	}
	create_context_menu.x = menu_x
	create_context_menu.y = menu_y
}

fn (mut d Desktop) render_jump_list() {
	mut children := frame_elements(taskbar_jump_list.entries.len + 1)
	mut y := jump_list_padding
	mut footer_top := -1
	for entry in taskbar_jump_list.entries {
		if entry.footer && footer_top < 0 {
			footer_top = y
		}
	}
	if footer_top >= 0 {
		children << ui2.view('', ui2.rect(0, f64(footer_top), f64(jump_list_width),
			f64(taskbar_jump_list.height - footer_top)), ui2.BoxStyle{
			bg: jump_list_footer_bg
		}, [])
	}
	for entry in taskbar_jump_list.entries {
		match entry.kind {
			.header {
				children << ui2.label('', entry.title, ui2.rect(12, f64(y + 4), f64(jump_list_width - 24),
					20), ui2.TextStyle{
					color: body_muted
					size:  11
					bold:  true
				})
			}
			.separator {
				children << ui2.view('', ui2.rect(8, f64(y + 4), f64(jump_list_width - 16), 1),
					ui2.BoxStyle{
					bg: body_rule
				}, [])
			}
			.item {
				hovered := d.hover == entry.id
				children << ui2.button_with_image(entry.id, entry.title, entry.icon, ui2.rect(f64(jump_list_padding),
					f64(y), f64(jump_list_width - 2 * jump_list_padding), f64(jump_list_row_height)),
					ui2.BoxStyle{
					bg:          files_row_hover
					radius:      5
					transparent: !hovered
				}, ui2.TextStyle{
					color: body_text
					size:  12
					align: .left
				})
			}
		}
		y += jump_list_entry_height(entry.kind)
	}
	panel := ui2.clickable_view(create_context_panel, ui2.rect(f64(create_context_menu.x),
		f64(create_context_menu.y), f64(jump_list_width), f64(taskbar_jump_list.height)),
		ui2.BoxStyle{
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

// ── Commands ───────────────────────────────────────────────────────

// launch_index_window starts a program and returns its new window, or 0 when
// nothing opened (an exclusive program, a failed start, a missing package).
fn (mut d Desktop) launch_index_window(index int) int {
	before := d.next_id
	d.launch_index(index)
	if d.next_id == before {
		return 0
	}
	id := d.next_id - 1
	window_index := d.window_index(id) or { return 0 }
	if d.windows[window_index].app_index < 0 {
		return 0
	}
	return id
}

// send_to_window delivers a compositor-originated action to the application
// behind a window, exactly as a click inside it would be.
fn (mut d Desktop) send_to_window(window_id int, event string) bool {
	index := d.window_index(window_id) or { return false }
	app_index := d.windows[index].app_index
	if app_index < 0 || app_index >= d.apps.len {
		return false
	}
	d.apps[app_index].handle(event) or {
		eprintln('vinix-desktop: ${d.windows[index].title}: ${err}')
		return false
	}
	d.dirty = true
	return true
}

// open_path_in_app opens a document or folder in a new window of a program.
fn (mut d Desktop) open_path_in_app(app_index int, path string) {
	window_id := d.launch_index_window(app_index)
	if window_id == 0 {
		return
	}
	event := jump_open_prefix + path
	d.send_to_window(window_id, event)
	unsafe { event.free() }
}

fn (mut d Desktop) run_jump_command(command JumpCommand, app_index int, path string, arg int,
	windows []int) {
	match command {
		.none_ {}
		.open_path {
			d.open_path_in_app(app_index, path)
		}
		.launch {
			d.launch_index(app_index)
		}
		.settings_page {
			if arg >= 0 && arg < settings_categories.len {
				d.open_settings_category(settings_categories[arg])
			}
		}
		.capture_screenshot {
			if id := d.open_capture_window() {
				d.capture_from_window(id, capture_action_take_screenshot)
			}
		}
		.pin {
			if !d.pin_taskbar_app_in(d.home, app_index) {
				eprintln('vinix-desktop: could not pin taskbar app')
			}
		}
		.unpin {
			if !d.unpin_taskbar_app_in(d.home, app_index) {
				eprintln('vinix-desktop: could not unpin taskbar app')
			}
		}
		.close_window, .close_all {
			for id in windows {
				d.close_window(id)
			}
		}
	}
}
