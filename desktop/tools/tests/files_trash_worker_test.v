// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn trash_worker_home(suffix string) string {
	home := os.real_path(os.temp_dir()) + '/vinix-trash-worker-' + C.getpid().str() + '-' + suffix
	os.mkdir_all(home) or { panic(err) }
	return home
}

fn trash_worker_wait(mut app FilesContextApp) {
	for _ in 0 .. 500 { app.poll(); if app.worker_pid == 0 { return }; desktop_sleep_ms(10) }
	assert false, 'Trash worker did not finish'
}

fn test_recursive_empty_runs_in_background_and_reports_completion() {
	home := trash_worker_home('complete')
	os.mkdir_all(home + '/folder/nested')!
	os.write_file(home + '/folder/nested/document', 'content')!
	old_home := desktop_user_home
	desktop_user_home = home
	defer { desktop_user_home = old_home; os.rmdir_all(home) or {} }
	mut app := FilesContextApp{trash: files_trash_new(home)}
	defer { app.close_app() }
	app.files.browser.read(home.clone())
	assert app.trash.move(home + '/folder')
	app.trash_open = true
	app.trash.confirming = true
	app.handle('files.trash.confirm')!
	assert app.worker_pid > 0 && app.trash_job && app.operation_open && !app.trash_open
	trash_worker_wait(mut app)
	assert app.operation.state == .complete
	assert app.operation.index == 1 && app.operation.count == 1
	assert app.trash.entries.len == 0 && !app.trash.damaged
}

fn test_cancel_retains_trash_and_retry_requires_fresh_catalog_confirmation() {
	home := trash_worker_home('cancel')
	os.mkdir_all(home + '/folder')!
	for i in 0 .. 500 { os.write_file(home + '/folder/' + i.str(), 'keep')! }
	old_home := desktop_user_home
	desktop_user_home = home
	defer { desktop_user_home = old_home; os.rmdir_all(home) or {} }
	mut app := FilesContextApp{trash: files_trash_new(home)}
	defer { app.close_app() }
	app.files.browser.read(home.clone())
	assert app.trash.move(home + '/folder')
	app.trash.confirming = true
	app.start_trash_empty()!
	assert C.kill(app.worker_pid, C.SIGSTOP) == 0
	app.operation_action('files.operation.cancel')
	assert C.kill(app.worker_pid, C.SIGCONT) == 0
	trash_worker_wait(mut app)
	assert app.operation.state == .cancelled
	assert app.trash.entries.len == 1 && !app.trash.damaged
	app.operation_action('files.operation.retry')
	assert app.trash_open && !app.trash.confirming && app.worker_pid == 0
	app.trash.confirming = true
	app.start_trash_empty()!
	trash_worker_wait(mut app)
	assert app.operation.state == .complete && app.trash.entries.len == 0
}

fn test_background_empty_refuses_arrivals_not_present_in_confirmed_catalog() {
	home := trash_worker_home('arrival')
	os.write_file(home + '/first', 'first')!
	os.write_file(home + '/second', 'second')!
	old_home := desktop_user_home
	desktop_user_home = home
	defer { desktop_user_home = old_home; os.rmdir_all(home) or {} }
	mut app := FilesContextApp{trash: files_trash_new(home)}
	defer { app.close_app() }
	app.files.browser.read(home.clone())
	assert app.trash.move(home + '/first')
	app.trash.confirming = true
	mut other := files_trash_new(home)
	defer { other.close() }
	assert other.move(home + '/second')
	app.start_trash_empty()!
	trash_worker_wait(mut app)
	assert app.operation.state == .failed
	assert app.trash.entries.len == 2 && !app.trash.damaged
}
