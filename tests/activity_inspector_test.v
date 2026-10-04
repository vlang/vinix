// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn test_activity_inspector_command_preserves_argument_boundaries() {
	command := activity_inspector_command("/bin/worker\x00--mode\x00two words\x00it's\x00\x00")
	defer { unsafe { command.free() } }
	assert command == "/bin/worker --mode 'two words' 'it'\\''s' ''"
	assert activity_inspector_command('') == ''
}

fn test_activity_inspector_wraps_utf8_details_and_bounds_keyboard_scroll() {
	mut inspector := ActivityInspector{ width: 240, status_available: true, command_available: true, memory_available: true, files_available: true }
	defer { inspector.close() }
	inspector.command = 'worker --argument-with-long-text Привет ещё текст'.clone()
	inspector.status = 'State:\tR (running)\nUid:\t501\nThreads:\t3'.clone()
	inspector.maps = '00000000-00001000 rw-p 00000000 00:00 0 [heap]'.clone()
	inspector.smaps = 'Rss: 4 kB\nPrivate_Dirty: 4 kB\nShared_Clean: 0 kB'.clone()
	inspector.files = '0: /dev/tty\n1: pipe:[123]\n2: socket:[456]'.clone()
	inspector.rebuild_lines()
	assert inspector.overview_lines.len > 3
	assert inspector.memory_lines.len >= 5
	assert inspector.file_lines.len >= 3
	tree := inspector.build(340, 218)
	free_tree(tree)
	assert inspector.visible_rows == 5
	inspector.key_input('\x1b[F')
	assert inspector.scroll == inspector.overview_lines.len - 5
	inspector.key_input('\x1b[H')
	assert inspector.scroll == 0
	assert inspector.handle(activity_inspect_memory)
	assert inspector.tab == .memory && inspector.scroll == 0
	assert inspector.handle(activity_inspect_files)
	assert inspector.tab == .files && inspector.scroll == 0
	assert !inspector.handle('unrelated')
}

fn test_activity_inspector_reports_missing_proc_data_truthfully() {
	mut inspector := ActivityInspector{}
	defer { inspector.close() }
	inspector.sample(2147483647)
	assert inspector.pid == 2147483647
	assert !inspector.status_available
	assert !inspector.command_available
	assert !inspector.memory_available
	assert !inspector.files_available
	assert inspector.error == tr('activity.inspector.unavailable')
	assert inspector.command == '' && inspector.executable == ''
	assert inspector.overview_lines.len > 0
	assert inspector.memory_lines.len > 0
	assert inspector.file_lines.len > 0
}

fn test_activity_inspector_export_contains_selected_process_data() {
	mut inspector := ActivityInspector{
		pid:        42
		pid_text:   '42'.clone()
		executable: '/bin/worker'.clone()
		command:    '/bin/worker --task'.clone()
		status:     'Name: worker\nState: S'.clone()
		maps:       '0000-1000 rw-p [heap]'.clone()
		smaps:      'Rss: 4 kB'.clone()
		statm:      '1 1 0'.clone()
		files:      '0: /dev/tty'.clone()
	}
	defer { inspector.close() }
	home := os.join_path(os.temp_dir(), 'vinix-activity-inspector-test')
	defer { unsafe { home.free() } }
	os.mkdir_all(home)!
	path := os.join_path(home, 'Activity-Monitor-42.txt')
	defer {
		os.rm(path) or {}
		os.rmdir(home) or {}
		unsafe { path.free() }
	}
	assert inspector.export_report(home)
	report := os.read_file(path)!
	defer { unsafe { report.free() } }
	assert report.contains('PID: 42')
	assert report.contains('/bin/worker --task')
	assert report.contains('Rss: 4 kB')
	assert report.contains('0: /dev/tty')
	assert inspector.export_status != ''
}
