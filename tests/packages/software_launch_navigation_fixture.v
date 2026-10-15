// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import desktop.packagecore
import tools.packages.pkgprotocol

const launch_navigation_arguments = '--title "λ; $(literal)" "" --flag'

fn launch_navigation_files() []string {
	return ['/private/tmp/a space; $literal.txt', '/private/tmp/文档.txt', '/private/tmp/third',
		'/private/tmp/fourth', '/private/tmp/fifth', '/private/tmp/sixth', '/private/tmp/seventh']
}

fn launch_navigation_app() SoftwareApp {
	return SoftwareApp{ administration_required: true, service_path: os.executable(), output: []u8{cap: 8192},
		query: 'kept query'.bytes(), matching: [1, 0], filter: 2, selected: 0, rows: [
		SoftwareRow{ id: 'launch-app', name: 'Candidate', kind: 'linux', permissions: [],
			installed_name: 'Installed App é', installed_kind: 'linux', installed_version: '1.0.0', installed_permissions: ['files'] },
		SoftwareRow{ id: 'no-files', name: 'Candidate files', kind: 'linux', permissions: ['files'],
			installed_name: 'Installed without files', installed_kind: 'linux', installed_version: '1.0.0' }] }
}

fn fill_launch_navigation_draft(mut app SoftwareApp, files []string) ! {
	app.handle('software.run-options')!
	app.handle('software.launch.arguments')!; app.paste_input(launch_navigation_arguments)
	app.handle('software.launch.data-cwd')!
	for path in files {
		app.handle('software.launch.file')!; app.paste_input(path); app.handle('software.launch.add-file')!
	}
	app.handle('software.launch.arguments')!
}

fn software_launch_navigation_service_fixture(args []string) !bool {
	mode := os.getenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION')
	if mode == '' || args.len < 2 || args[1] != 'run-args' { return false }
	mut words := pkgprotocol.command_words(launch_navigation_arguments)!
	files := launch_navigation_files()
	mut expected := pkgprotocol.command_vector('launch-app', words, files, false, false)!
	defer { pkgprotocol.free_command_values(mut words); pkgprotocol.free_command_values(mut expected); unsafe { (&array(&files)).free() } }
	assert args[1..] == expected
	println('Application is running with the frozen literal command.'); flush_stdout()
	mut release := u8(0); assert C.read(0, &release, 1) == 1
	os.write_file(os.getenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION_RECEIPT'), json2.encode(args[1..]))!
	if mode == 'failed' { eprintln('Granted file is unavailable to the ordinary account. Correct file access and retry.'); exit(27) }
	println('Application finished successfully.')
	return true
}

fn wait_for_launch_navigation_output(mut app SoftwareApp) {
	for _ in 0 .. 5000 {
		app.poll()
		if app.output.len > 0 { return }
		time.sleep(time.millisecond)
	}
	assert false, 'launch fixture did not reach its output barrier: ${app.status}'
}

fn check_launch_empty_paste(mut app SoftwareApp) {
	arguments := editor_bytes_text(app.launch_arguments); file := editor_bytes_text(app.launch_file)
	argument_storage := app.launch_arguments.data; file_storage := app.launch_file.data
	status := app.status; selected := app.launch_file_selected; scroll := app.launch_file_scroll
	count := app.launch_documents.len; cwd := app.launch_data_cwd; id := app.launch_id
	focused := app.launch_focus; selection := app.select_all
	for focus in 0 .. 3 {
		for select_all in [false, true]! {
			app.launch_focus = focus; app.select_all = select_all
			app.paste_input('')
			assert editor_bytes_text(app.launch_arguments) == arguments && editor_bytes_text(app.launch_file) == file
			assert app.launch_arguments.data == argument_storage && app.launch_file.data == file_storage
			assert app.launch_focus == focus && app.select_all == select_all && app.status == status
			assert app.launch_mode && app.launch_id == id && app.launch_data_cwd == cwd && app.launch_documents.len == count
			assert app.launch_file_selected == selected && app.launch_file_scroll == scroll && app.worker == unsafe { nil }
		}
	}
	app.launch_focus = focused; app.select_all = selection
}

fn check_software_launch_navigation() ! {
	receipt := os.temp_dir() + '/vinix-launch-navigation-' + os.getpid().str()
	os.setenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION_RECEIPT', receipt, true)
	defer { os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION'); os.unsetenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION_RECEIPT') }
	files := launch_navigation_files()
	defer { unsafe { (&array(&files)).free() } }
	mut words := pkgprotocol.command_words(launch_navigation_arguments)!
	mut vector := pkgprotocol.command_vector('launch-app', words, files, false, false)!
	defer { pkgprotocol.free_command_values(mut words); pkgprotocol.free_command_values(mut vector) }
	mut app := launch_navigation_app()
	defer { app.close_app() }
	fill_launch_navigation_draft(mut app, files)!
	check_launch_empty_paste(mut app)
	assert app.launch_files_allowed && app.launch_name == 'Installed App é' && app.launch_documents == files && !app.launch_data_cwd
	app.handle('software.launch.up')!; app.handle('software.launch.file.1')!; app.handle('software.launch.down')!
	assert app.launch_file_scroll == 5 && app.launch_file_selected == 1
	app.key_input('\x01')
	for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 640, 610)]! {
		tree := app.build(size)!
		assert tree.children.any(it.id == 'software.launch.back') && tree.children.any(it.text == app.status)
		assert tree.children.any(it.id == 'software.launch.run') == (size.width >= 640)
		if size.width < 640 {
			assert !tree.children.any(it.id in ['software.launch.arguments', 'software.launch.file', 'software.launch.data-cwd', 'software.launch.terminal', 'software.launch.add-file'])
		}
		free_window_tree(tree)
		assert app.launch_file_scroll == 5 && app.launch_file_selected == 1 && app.launch_focus == 1 && app.select_all
	}
	for input in ['\x1b', '\r', '\n', '\x01', '\x08', '\x7f', '\xc2\x85', '\xff']! {
		app.paste_input(input)
		assert app.launch_mode && app.launch_focus == 1 && app.select_all && editor_bytes_text(app.launch_arguments) == launch_navigation_arguments
	}
	app.paste_input('x'.repeat(4097))
	assert editor_bytes_text(app.launch_arguments) == launch_navigation_arguments && app.select_all
	app.handle('software.launch.remove-file')!
	assert app.launch_documents.len == 6 && !app.launch_documents.contains(files[1]) && app.launch_file_selected == -1
	app.key_input('\x1b'); assert app.launch_mode && app.launch_focus == 0 && !app.select_all
	app.paste_input('\x1b'); assert app.launch_mode
	app.key_input('\x1b')
	assert !app.launch_mode && app.launch_documents.len == 0 && app.launch_arguments.len == 0 && app.launch_id == ''
	assert app.query.bytestr() == 'kept query' && app.matching == [1, 0] && app.selected == 0 && app.filter == 2
	fill_launch_navigation_draft(mut app, files)!
	app.handle('software.launch.file')!; app.paste_input('/private/tmp/not-yet-added')
	check_launch_empty_paste(mut app)
	app.handle('software.launch.run')!; assert app.worker == unsafe { nil } && app.status.contains('Add the entered file')
	app.key_input('\x01'); app.key_input('\x08')
	assert app.launch_file.len == 0
	app.handle('software.launch.arguments')!; app.key_input('\x01'); app.paste_input('"unfinished')
	app.handle('software.launch.run')!; assert app.worker == unsafe { nil } && app.status.contains('quoted argument')
	app.key_input('\x01'); app.paste_input(launch_navigation_arguments); app.key_input('\r')
	assert app.launch_focus == 0 && !app.select_all
	for mode in ['failed', 'complete']! {
		os.setenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION', mode, true)
		app.handle('software.launch.run')!; pid := app.worker.pid
		wait_for_launch_navigation_output(mut app)
		assert app.worker_run && app.worker.args == vector && !app.admin_prompt && !app.prepare_close()
		for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
			tree := app.build(size)!
			assert tree.children.any(it.text == app.status)
			assert !tree.children.any(it.id in ['software.launch.back', 'software.launch.run', 'software.launch.terminal', 'software.failure'])
			free_window_tree(tree)
		}
		for event in ['software.launch.back', 'software.launch.arguments', 'software.launch.file', 'software.launch.data-cwd',
			'software.launch.add-file', 'software.launch.remove-file', 'software.launch.up', 'software.launch.down', 'software.launch.file.0',
			'software.launch.run', 'software.launch.terminal', 'software.reload', 'software.cancel']! { app.handle(event)! }
		app.key_input('\x1b'); app.key_input('\x01'); app.paste_input('must not edit')
		app.handle(packagecore.request_prefix + '{"id":"no-files"}')!
		assert app.worker.pid == pid && C.kill(pid, 0) == 0 && app.launch_mode && app.launch_request == '' && !os.exists(receipt)
		assert app.launch_documents == files && !app.launch_data_cwd && editor_bytes_text(app.launch_arguments) == launch_navigation_arguments
		app.worker.stdin_write('x'); wait_for_software(mut app)
		assert app.launch_mode && app.prepare_close() && app.launch_documents == files && app.worker == unsafe { nil }
		assert json2.decode[[]string](os.read_file(receipt)!)! == vector
		if mode == 'failed' {
			assert app.failure_pages.len > 0 && app.status.contains('Correct file access')
			compact := app.build(ui2.rect(0, 0, 320, 240))!
			assert compact.children.any(it.id == 'software.failure') && compact.children.any(it.id == 'software.launch.back')
			free_window_tree(compact)
			app.handle('software.failure')!; app.key_input('\x1b'); assert !app.failure_mode && app.launch_mode
		} else { assert app.status.contains('finished successfully') }
		os.rm(receipt)!
	}
	os.unsetenv('VINIX_SOFTWARE_LAUNCH_NAVIGATION')
	app.handle('software.launch.terminal')!
	mut terminal_vector := pkgprotocol.command_vector('launch-app', words, files, false, true)!
	defer { pkgprotocol.free_command_values(mut terminal_vector) }
	assert !app.launch_mode && app.terminal_app != unsafe { nil } && app.terminal_app.argv == [app.service_path, ...terminal_vector]
	assert app.launch_documents.len == 0 && app.launch_arguments.len == 0 && !app.prepare_close()
	app.terminal_app.exited = true; app.close_terminal()
	app.selected = 1; app.handle('software.run-options')!
	assert !app.launch_files_allowed && app.launch_name == 'Installed without files' && app.launch_documents.len == 0
	app.handle('software.launch.file')!; app.paste_input(files[0]); app.handle('software.launch.add-file')!
	assert app.launch_documents.len == 0 && app.status.contains('does not declare file access')
	app.key_input('\x1b'); assert app.launch_mode && app.launch_focus == 0
	app.handle('software.launch.back')!; assert !app.launch_mode && app.launch_file.len == 0 && app.launch_documents.len == 0
	assert app.query.bytestr() == 'kept query' && app.matching == [1, 0] && app.filter == 2
	println('Software launch navigation: compact Back/status/failures, stable draft and file paging, Escape blur/back, control-paste refusal, installed permission basis, protected literal batch success/failure, retry and exact terminal transfer passed')
}

fn check_software_launch_navigation_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		mut files := []string{cap: 256}
		for index in 0 .. 256 { files << '/private/tmp/document-' + index.str() + ' é; $literal.txt' }
		defer { pkgprotocol.free_command_values(mut files) }
		arguments := ['run-args']
		defer { unsafe { (&array(&arguments)).free() } }
		mut app := launch_navigation_app()
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				fill_launch_navigation_draft(mut app, files)!
				check_launch_empty_paste(mut app)
				assert app.launch_documents.len == 256 && app.launch_file_scroll == 251 && app.launch_file_selected == 255
				app.handle('software.launch.file')!; app.paste_input('/private/tmp/overflow'); app.handle('software.launch.add-file')!
				check_launch_empty_paste(mut app)
				assert app.launch_documents.len == 256 && app.status.contains('At most 256')
				app.launch_file.clear(); app.handle('software.launch.arguments')!; app.key_input('\x01')
				app.paste_input('\x1b'); assert app.launch_focus == 1 && app.launch_mode && app.select_all
				free_window_tree(app.build(ui2.rect(0, 0, 900, 660))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.key_input('\x1b'); assert app.launch_mode && app.launch_focus == 0 && !app.select_all
				app.handle('software.launch.remove-file')!
				assert app.launch_documents.len == 255 && app.launch_file_selected == -1
				app.handle('software.launch.file')!; app.paste_input(files[255]); app.handle('software.launch.add-file')!
				assert app.launch_documents.len == 256
				app.capture_failure(arguments, 27)
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.handle('software.launch.terminal')!
				assert app.terminal_app != unsafe { nil } && !app.launch_mode && app.launch_documents.len == 0
				app.terminal_app.exited = true; app.close_terminal(); app.clear_failure()
				app.open_launch_options(); app.key_input('\x1b'); assert !app.launch_mode && app.launch_documents.len == 0
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'launch navigation retained ${kept} bytes'
		println('Software launch navigation: 1000 256-file draft/full/compact/paging/paste/blur/failure/terminal-transfer/retirement cycles retain zero tracked bytes')
	}
}
