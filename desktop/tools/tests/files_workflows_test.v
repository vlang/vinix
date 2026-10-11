// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
import ui2

fn files_workflow_test_home() string {
	path := os.real_path(os.temp_dir()) + '/vinix-files-workflows-${C.getpid()}'
	os.rmdir_all(path) or {}
	os.mkdir_all(path) or { panic(err) }
	return path
}

fn test_files_tabs_keep_navigation_and_multi_selection_does_not_enter_folders() {
	home := files_workflow_test_home()
	defer { os.rmdir_all(home) or {} }
	os.mkdir(home + '/folder')!
	os.write_file(home + '/document', 'document')!
	mut app := FilesContextApp{}
	app.files.browser.read(home.clone())
	defer { app.close_app() }
	app.handle('files.selection.toggle')!
	app.handle('files.row.0')!
	assert app.selection == [home + '/folder']
	assert app.files.current_path() == home
	app.handle('files.tab.new')!
	assert app.tabs.len == 2 && app.active_tab == 1
	app.files.navigate_to(home + '/folder')
	app.handle('files.tab.0')!
	assert app.files.current_path() == home && app.selection == [home + '/folder']
	app.handle('files.tab.1')!
	assert app.files.current_path() == home + '/folder'
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 800, 600))!
	free_tree(tree)
}

fn test_files_worker_reports_progress_copies_batch_and_undo_trashes_copy() {
	home := files_workflow_test_home()
	defer { os.rmdir_all(home) or {} }
	old_user := desktop_user_home
	desktop_user_home = home
	defer { desktop_user_home = old_user }
	os.mkdir(home + '/destination')!
	os.write_file(home + '/one', 'first')!
	os.write_file(home + '/two', 'second')!
	mut app := FilesContextApp{}
	app.files.browser.read((home + '/destination').clone())
	defer { app.close_app() }
	app.start_transfer([home + '/one', home + '/two'], home + '/destination', .copy)!
	for _ in 0 .. 300 {
		app.poll()
		if app.operation.state == .complete { break }
		desktop_sleep_ms(10)
	}
	assert app.operation.state == .complete, app.operation.label
	assert os.read_file(home + '/destination/one')! == 'first'
	assert os.read_file(home + '/destination/two')! == 'second'
	assert app.undo_operations.len == 2
	app.undo_file_operation()!
	assert !os.exists(home + '/destination/two')
	assert !os.exists(home + '/destination/one')
	assert app.trash.entries.len == 2
}

fn test_files_undo_renames_and_permissions_and_refuses_replaced_items() {
	home := files_workflow_test_home()
	defer { os.rmdir_all(home) or {} }
	os.write_file(home + '/original', 'original')!
	mut app := FilesContextApp{}
	app.files.browser.read(home.clone())
	defer { app.close_app() }
	app.begin_rename(home + '/original')
	app.rename_text.clear(); editor_append(mut app.rename_text, 'renamed')
	app.commit_rename()!
	assert os.exists(home + '/renamed')
	app.undo_file_operation()!
	assert os.exists(home + '/original') && !os.exists(home + '/renamed')
	app.files.info.read(home + '/original', 0)
	old_mode := app.files.info.mode & 0o777
	app.files.info.pending_mode = 0o600
	app.workflow_permission_action('files.permissions.apply')
	assert app.files.info.mode & 0o777 == 0o600
	app.files.info.close()
	if old_mode != 0o600 { app.undo_file_operation()! }
	app.begin_rename(home + '/original')
	app.rename_text.clear(); editor_append(mut app.rename_text, 'renamed')
	app.commit_rename()!
	os.write_file(home + '/renamed', 'external')!
	app.undo_file_operation() or { assert os.read_file(home + '/renamed')! == 'external'; return }
	assert false, 'undo must preserve later edits'
}

fn test_drag_in_tag_view_uses_tag_results_instead_of_the_current_folder() {
	home := files_workflow_test_home()
	defer { os.rmdir_all(home) or {} }
	os.mkdir_all(home + '/different-folder')!
	os.write_file(home + '/different-folder/document', 'tagged document')!
	mut app := FilesContextApp{}
	app.files.browser.read(home.clone())
	defer { app.close_app() }
	app.files.settings = default_files_settings()
	app.files.settings.toggle_tag(home + '/different-folder/document', 7)
	app.files.active_tag_id = 7
	app.files.rows_top = 100
	app.files.rows_height = 300
	assert app.path_at(files_content_left(800) + 40, 110, 800) == ''
	assert app.path_at(files_content_left(800) + 40, 126, 800) == home + '/different-folder/document'
}
