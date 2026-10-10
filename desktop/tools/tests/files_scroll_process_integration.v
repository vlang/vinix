// SPDX-License-Identifier: GPL-2.0-or-later
// Horizontal wheel routing through the compositor and the real Files pipe.
module main

import os
import ui2

fn files_scroll_process_row(element ui2.Element, text string) ?ui2.Element {
	if element.kind == .view && element.id.starts_with(files_action_column_row) {
		for child in element.children {
			if child.text == text { return element }
		}
	}
	for child in element.children {
		if found := files_scroll_process_row(child, text) { return found }
	}
	return none
}

fn main() {
	if options := app_process_options(arguments()[1..]) {
		run_app_process(options)
		return
	}
	desktop_ignore_broken_pipe()
	root := os.join_path(os.real_path(os.temp_dir()), 'vinix-files-scroll-ipc-${os.getpid()}')
	os.mkdir_all(os.join_path(root, 'child')) or { panic(err) }
	previous_home := desktop_user_home
	desktop_user_home = root
	defer {
		desktop_user_home = previous_home
		os.rmdir_all(root) or {}
	}
	mut desktop := Desktop{}
	factory := app_factory_named('vinix-files') or { panic('Files missing') }
	mut app := start_remote_app_at_with_timeout(arguments()[0], factory, mut desktop,
		app_response_timeout_ms) or { panic(err) }
	defer { if mut app is RemoteApp { app.close() } }
	desktop.apps << app
	desktop.windows << Window{
		id: 1, x: 100, y: 100, width: 700, height: 400 + desktop.theme().title_height,
		page: .app, app_index: 0
	}
	app.handle(files_action_view_columns) or { panic(err) }
	before := app.build(ui2.rect(0, 0, 700, 400)) or { panic(err) }
	row := files_scroll_process_row(before, 'child') or { panic('child row missing') }
	x := 100 + int(row.frame.x) + 5
	y := 100 + desktop.theme().title_height + int(row.frame.y) + 5
	free_tree(before)
	desktop.on_app_pointer_horizontal_scroll(x, y, -1)
	after := app.build(ui2.rect(0, 0, 700, 400)) or { panic(err) }
	moved := files_scroll_process_row(after, 'child') or { panic('panned row missing') }
	assert moved.frame.x == row.frame.x + 48
	assert moved.frame.y == row.frame.y
	free_tree(after)
	desktop.on_app_pointer_horizontal_scroll(x, y, 1)
	restored := app.build(ui2.rect(0, 0, 700, 400)) or { panic(err) }
	back := files_scroll_process_row(restored, 'child') or { panic('restored row missing') }
	assert back.frame.x == row.frame.x
	free_tree(restored)
	assert desktop.pointer_capture == 0
	println('Files horizontal scroll IPC PASS')
}
