// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import desktop.workflowcore

fn test_cross_volume_move_and_undo_preserve_complete_tree_and_permissions() {
	volume := os.getenv('VINIX_WORKFLOW_SECOND_VOLUME')
	if volume == '' { eprintln('Cross-volume qualification requires VINIX_WORKFLOW_SECOND_VOLUME'); return }
	home := os.real_path(os.temp_dir()) + '/vinix-cross-volume-' + C.getpid().str()
	destination := os.real_path(volume) + '/vinix-cross-volume-' + C.getpid().str()
	os.mkdir_all(home + '/mixed/nested')!
	os.mkdir(destination)!
	defer { os.rmdir_all(home) or {}; os.rmdir_all(destination) or {} }
	assert workflowcore.identify(home)!.device != workflowcore.identify(destination)!.device
	bytes := []u8{len: 768 * 1024, init: u8(index % 239)}
	os.write_file_array(home + '/mixed/nested/document', bytes)!
	os.chmod(home + '/mixed/nested/document', 0o640)!
	os.symlink('nested/document', home + '/mixed/link')!
	old_home := desktop_user_home
	desktop_user_home = home
	defer { desktop_user_home = old_home }
	mut app := FilesContextApp{}
	app.files.browser.read(home.clone())
	defer { app.close_app() }
	app.start_transfer([home + '/mixed'], destination, .move)!
	for _ in 0 .. 1000 { app.poll(); if app.worker_pid == 0 { break }; desktop_sleep_ms(10) }
	assert app.operation.state == .complete, app.operation.label
	assert !os.exists(home + '/mixed')
	assert os.read_bytes(destination + '/mixed/nested/document')! == bytes
	assert workflowcore.identify(destination + '/mixed/nested/document')!.mode & 0o777 == 0o640
	assert os.is_link(destination + '/mixed/link')
	assert app.undo_operations.len == 1
	app.undo_file_operation()!
	assert app.undo_pending && app.worker_pid > 0
	for _ in 0 .. 1000 { app.poll(); if app.worker_pid == 0 { break }; desktop_sleep_ms(10) }
	assert app.operation.state == .complete, app.operation.label
	assert app.undo_operations.len == 0 && !app.undo_pending
	assert !os.exists(destination + '/mixed')
	assert os.read_bytes(home + '/mixed/nested/document')! == bytes
	assert workflowcore.identify(home + '/mixed/nested/document')!.mode & 0o777 == 0o640
	assert os.is_link(home + '/mixed/link')
}
