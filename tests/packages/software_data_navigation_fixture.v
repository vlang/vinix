// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import tools.packages.pkgprotocol

fn software_data_navigation_service_fixture(args []string) !bool {
	mode := os.getenv('VINIX_SOFTWARE_DATA_NAVIGATION')
	if mode == '' || args.len < 2 { return false }
	if mode.starts_with('list-') && args[1..] == ['--json', 'data-list'] {
		status := fixture_personal_data_status()
		text := json2.encode(pkgprotocol.PersonalDataStatus{ ...status,
			rows: status.rows.filter(it.id != 'removed-app' || !os.exists(os.getenv('VINIX_SOFTWARE_DATA_FIXTURE'))) })
		partial := mode == 'list-partial'
		print(if partial { text[..text.len / 2] } else { text }); flush_stdout()
		mut release := u8(0); assert C.read(0, &release, 1) == 1
		if mode == 'list-failed' { eprintln('Personal data inventory unavailable; repair account directory access and reload.'); exit(17) }
		if partial { print(text[text.len / 2..]) }
		return true
	}
	if mode.starts_with('purge-') && args[1] == 'purge-data' {
		assert args[1..] == ['purge-data', 'removed-app']
		println('Checking confirmed personal data deletion…'); flush_stdout()
		mut release := u8(0); assert C.read(0, &release, 1) == 1
		if mode == 'purge-failed' { eprintln('cannot purge removed-app: generation 3 is still in use; stop applications and retry'); exit(17) }
		os.write_file(os.getenv('VINIX_SOFTWARE_DATA_FIXTURE'), 'removed-app')!
		return true
	}
	return false
}

fn wait_for_data_navigation_output(mut app SoftwareApp) {
	for _ in 0 .. 5000 {
		app.poll()
		if app.output.len > 0 { return }
		time.sleep(time.millisecond)
	}
	assert false, 'personal data fixture did not reach its output barrier: ${app.status}'
}

fn check_software_data_navigation() ! {
	receipt := os.temp_dir() + '/vinix-data-navigation-' + os.getpid().str()
	os.setenv('VINIX_SOFTWARE_DATA_FIXTURE', receipt, true)
	defer { os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_DATA_FIXTURE'); os.unsetenv('VINIX_SOFTWARE_DATA_NAVIGATION') }
	mut app := SoftwareApp{ administration_required: true, service_path: os.executable(), output: []u8{cap: 8192}, query: 'kept query'.bytes(), filter: 1 }
	defer { app.close_app() }
	app.handle('software.data')!; wait_for_software(mut app)
	for ending in ['partial', 'complete']! {
		for action in ['software.data.stop', 'software.data.cancel', 'escape']! {
			app.handle('software.row.1')!
			os.setenv('VINIX_SOFTWARE_DATA_NAVIGATION', 'list-' + ending, true)
			app.handle('software.data.reload')!; pid := app.worker.pid
			wait_for_data_navigation_output(mut app)
			assert app.data_read_running() && app.prepare_close() && !app.data_ready && !app.admin_prompt
			for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
				tree := app.build(size)!
				assert tree.children.any(it.id == 'software.data.stop') && tree.children.any(it.text == app.status)
				assert !tree.children.any(it.id in ['software.data.confirm', 'software.data.cancel', 'software.data.back', 'software.data.reload', 'software.row.0'])
				free_window_tree(tree)
			}
			for event in ['software.data.confirm', 'software.data.delete', 'software.data.back', 'software.data.reload', 'software.row.2']! { app.handle(event)! }
			app.paste_input('\x1b'); assert app.worker.pid == pid && app.data_selected == 1
			if action == 'escape' { app.key_input('\x1b') } else { app.handle(action)! }
			assert app.worker == unsafe { nil } && C.kill(pid, 0) != 0 && app.data_worker == .none && !app.worker_view && !app.worker_review
			assert app.output.len == 0 && !app.output_truncated && !app.poll() && app.status.contains('stopped')
			assert !app.data_ready && app.data_pending == '' && app.data_mode && !os.exists(receipt)
			app.handle('software.data.delete')!; assert app.data_pending == '' && app.worker == unsafe { nil }
			compact := app.build(ui2.rect(0, 0, 320, 240))!
			assert compact.children.any(it.id == 'software.data.back') && compact.children.any(it.id == 'software.data.reload')
			free_window_tree(compact)
			os.unsetenv('VINIX_SOFTWARE_DATA_NAVIGATION'); app.handle('software.data.reload')!; wait_for_software(mut app)
			assert app.data_ready && app.data_status.rows.len == 4 && app.data_selected == -1
		}
	}
	os.setenv('VINIX_SOFTWARE_DATA_NAVIGATION', 'list-failed', true)
	app.handle('software.data.reload')!; wait_for_data_navigation_output(mut app)
	app.worker.stdin_write('x'); wait_for_software(mut app)
	assert !app.data_ready && app.failure_pages.len > 0 && app.status.contains('account directory access')
	app.handle('software.data.delete')!; assert app.data_pending == ''
	failed := app.build(ui2.rect(0, 0, 320, 240))!
	assert failed.children.any(it.id == 'software.data.back') && failed.children.any(it.id == 'software.data.reload') && failed.children.any(it.id == 'software.failure')
	free_window_tree(failed)
	app.handle('software.failure')!; app.handle('software.failure.back')!; assert !app.failure_mode && app.data_mode
	os.unsetenv('VINIX_SOFTWARE_DATA_NAVIGATION'); app.handle('software.data.reload')!; wait_for_software(mut app)
	for action in ['software.data.cancel', 'escape']! {
		app.handle('software.row.1')!; app.handle('software.data.delete')!
		selected := app.data_selected; scroll := app.data_scroll
		for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 640, 610)]! {
			tree := app.build(size)!
			assert tree.children.any(it.id == 'software.data.cancel')
			assert tree.children.any(it.id == 'software.data.confirm') == (size.width >= 640)
			assert !tree.children.any(it.id in ['software.data.back', 'software.data.reload', 'software.row.0'])
			free_window_tree(tree)
		}
		assert app.data_selected == selected && app.data_scroll == scroll && app.data_pending == 'removed-app'
		if action == 'escape' { app.key_input('\x1b') } else { app.handle(action)! }
		assert app.data_pending == '' && app.status.contains('cancelled') && app.worker == unsafe { nil }
	}
	for mode in ['purge-failed', 'purge-complete']! {
		app.handle('software.row.1')!; app.handle('software.data.delete')!
		os.setenv('VINIX_SOFTWARE_DATA_NAVIGATION', mode, true)
		app.handle('software.data.confirm')!; pid := app.worker.pid
		wait_for_data_navigation_output(mut app)
		assert app.worker.args == ['purge-data', 'removed-app'] && !app.admin_prompt && !app.prepare_close() && !app.data_read_running()
		for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
			tree := app.build(size)!
			assert tree.children.any(it.text == app.status)
			assert !tree.children.any(it.id in ['software.data.stop', 'software.data.cancel', 'software.data.confirm', 'software.data.back', 'software.data.reload'])
			free_window_tree(tree)
		}
		for event in ['software.data.stop', 'software.data.cancel', 'software.data.back', 'software.data.reload', 'software.data.confirm', 'software.row.2']! { app.handle(event)! }
		app.key_input('\x1b'); app.stop_data_read()
		assert app.worker.pid == pid && C.kill(pid, 0) == 0 && !os.exists(receipt) && app.data_pending == 'removed-app'
		if mode == 'purge-complete' { os.setenv('VINIX_SOFTWARE_DATA_NAVIGATION', 'list-complete', true) }
		app.worker.stdin_write('x')
		if mode == 'purge-complete' {
			for _ in 0 .. 5000 { app.poll(); if app.data_worker == .list { break }; time.sleep(time.millisecond) }
			assert app.data_worker == .list && app.data_result == 'Personal data deleted for removed-app.'
			wait_for_data_navigation_output(mut app)
			assert app.data_read_running() && !app.data_ready && app.data_pending == '' && os.read_file(receipt)! == 'removed-app'
			app.handle('software.data.stop')!
			assert !app.data_ready && app.data_result == 'Personal data deleted for removed-app.'
			app.handle('software.data.delete')!; assert app.data_pending == ''
			os.unsetenv('VINIX_SOFTWARE_DATA_NAVIGATION'); app.handle('software.data.reload')!
		}
		wait_for_software(mut app)
		if mode == 'purge-failed' {
			assert app.data_pending == 'removed-app' && app.status.contains('still in use') && app.failure_pages.len > 0 && app.prepare_close()
			compact := app.build(ui2.rect(0, 0, 320, 240))!
			assert compact.children.any(it.id == 'software.failure') && compact.children.any(it.id == 'software.data.cancel')
			free_window_tree(compact)
			app.handle('software.failure')!; app.key_input('\x1b'); assert !app.failure_mode && app.data_pending == 'removed-app'
			app.key_input('\x1b'); assert app.data_pending == '' && app.data_mode
		} else {
			assert app.data_ready && !app.data_status.rows.any(it.id == 'removed-app') && app.status == 'Personal data deleted for removed-app.' && app.data_result == ''
		}
		os.unsetenv('VINIX_SOFTWARE_DATA_NAVIGATION')
	}
	app.key_input('\x1b'); wait_for_software(mut app)
	assert !app.data_mode && app.query.bytestr() == 'kept query' && app.filter == 1
	mut root := SoftwareApp{ service_path: os.executable() }
	root.handle('software.data')!
	tree := root.build(ui2.rect(0, 0, 320, 240))!
	assert tree.children.any(it.id == 'software.data.back') && !tree.children.any(it.id in ['software.data.reload', 'software.data.confirm'])
	free_window_tree(tree); root.key_input('\x1b'); wait_for_software(mut root); assert !root.data_mode; root.close_app()
	println('Software personal data navigation: partial and complete-before-exit inventory Stop/Cancel/Escape, fresh inventory requirement, compact controls and stable selection, protected purge, stopped post-delete reload, retained result and failure diagnostics passed')
}

fn check_software_data_navigation_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		mut rows := []pkgprotocol.PersonalData{cap: 32}
		for index in 0 .. 32 { rows << pkgprotocol.PersonalData{ id: 'app-' + index.str() } }
		text := json2.encode(pkgprotocol.PersonalDataStatus{ format: 1, rows: rows })
		mut status := pkgprotocol.PersonalDataStatus{ rows: rows }; status.close()
		defer { unsafe { text.free() } }
		arguments := ['purge-data', 'app-1']
		defer { unsafe { (&array(&arguments)).free() } }
		mut app := SoftwareApp{ administration_required: true, data_mode: true, output: []u8{cap: 8192} }
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.output.clear(); for byte in text { app.output << byte }; app.load_personal_data()
				app.handle_personal_data('software.row.1')
				free_window_tree(app.build(ui2.rect(0, 0, 900, 1200))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.handle_personal_data('software.data.delete')
				app.progress_seen = true
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
				compact := app.build(ui2.rect(0, 0, 320, 240))!
				assert compact.children.any(it.id == 'software.progress')
				free_window_tree(compact); app.progress_seen = false
				app.data_key_input('\x1b'); assert app.data_pending == ''
				app.capture_failure(arguments, 17)
				app.progress_seen = true
				free_window_tree(app.build(ui2.rect(0, 0, 900, 1200))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.progress_seen = false; app.clear_failure(); app.clear_personal_data()
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'personal data navigation retained ${kept} bytes'
		println('Software personal data navigation: 1000 inventory/select/full/compact/confirm/cancel/failure/progress/retirement cycles retain zero tracked bytes')
	}
}
