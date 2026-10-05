// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn test_files_mouse_back_goes_up_once_per_press_in_both_views() {
	root := os.join_path(os.temp_dir(), 'vinix-files-mouse-back-test')
	child := os.join_path(root, 'child')
	os.rmdir_all(root) or {}
	os.mkdir_all(child) or { panic(err) }
	defer { os.rmdir_all(root) or {} }

	mut app := FilesContextApp{}
	app.files.browser.read(child.clone())
	app.set_context_path(os.join_path(child, 'selected.txt'))
	app.pointer_event(.up, .back, 0, 10, 70, 700, 400)
	assert app.files.current_path() == child
	app.pointer_event(.down, .back, 0, 10, 70, 700, 400)
	assert app.files.current_path() == root
	assert app.context_path == ''
	app.pointer_event(.up, .back, 0, 10, 70, 700, 400)
	assert app.files.current_path() == root

	app.files.browser.read(child.clone())
	app.files.set_view_mode(.columns)
	assert app.files.current_path() == child
	app.pointer_event(.down, .back, 0, 10, 70, 700, 400)
	assert app.files.current_path() == root
	app.pointer_event(.up, .back, 0, 10, 70, 700, 400)
	assert app.files.current_path() == root

	app.files.active_tag_id = 1
	app.pointer_event(.down, .back, 0, 10, 70, 700, 400)
	assert app.files.active_tag_id == -1
	assert app.files.current_path() == root

	app.files.navigate_to('/')
	app.pointer_event(.down, .back, 0, 10, 70, 700, 400)
	assert app.files.current_path() == '/'
	app.files.free_miller_columns()
	app.files.browser.free_entries()
	unsafe { app.files.browser.path.free() }
}
