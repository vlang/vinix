// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import desktop.packagecore
import tools.packages.pkgprotocol

fn verify_navigation_frame(complete bool) string {
	text := json2.encode(pkgprotocol.Progress{ phase: if complete { 'complete' } else { 'verify' },
		package: if complete { '' } else { 'editor' }, path: if complete { '' } else { 'bin/editor' },
		current: if complete { u64(1) } else { 0 }, total: if complete { u64(1) } else { 0 } })
	defer { unsafe { text.free() } }
	return pkgprotocol.progress_prefix + text + '\n'
}

fn software_verify_navigation_service_fixture(args []string) !bool {
	mode := os.getenv('VINIX_SOFTWARE_VERIFY_NAVIGATION')
	if mode == '' || args.len < 2 { return false }
	if mode.starts_with('protected-') && args[1] in ['update', 'apply', 'run']! {
		if args[1] == 'update' { assert os.args[1..] == ['--progress', 'update'] }
		if args[1] == 'apply' { assert args[1..] == ['apply', 'c'.repeat(64), 'install', 'editor'] }
		if args[1] == 'run' { assert args[1..] == ['run', 'editor'] }
		print(verify_navigation_frame(false)); println('Protected operation running.'); flush_stdout()
		mut release := u8(0); assert C.read(0, &release, 1) == 1
		println('Protected operation finished.'); return true
	}
	if args[1] != 'verify' { return false }
	assert os.args[1..] == ['--progress', 'verify']
	frame := verify_navigation_frame(false)
	if mode == 'partial' { print(frame[..8]) } else { print(frame) }
	if mode in ['complete', 'healthy', 'failed']! {
		print(verify_navigation_frame(true))
		println('Installed package files and launchers verified.')
	}
	flush_stdout()
	mut release := u8(0); assert C.read(0, &release, 1) == 1
	if mode == 'failed' { eprintln('Storage read failed after the completion frame. Retry Verify installed.'); exit(24) }
	if mode == 'partial' { print(frame[8..]) }
	if mode !in ['complete', 'healthy']! {
		print(verify_navigation_frame(true)); println('Installed package files and launchers verified.')
	}
	return true
}

fn verify_navigation_app(administration bool) SoftwareApp {
	return SoftwareApp{ administration_required: administration, service_path: os.executable(), output: []u8{cap: 8192},
		query: 'kept query'.bytes(), matching: [0], selected: 0, filter: 1,
		catalog_error: 'catalog expired'.clone(), update_error: 'publisher revoked'.clone(),
		rows: [SoftwareRow{ id: 'editor', name: 'Editor', description: 'Write documents', version: '1.0.0',
			installed_version: '1.0.0', architecture: 'aarch64', kind: 'native', permissions: ['files'], requested: true }] }
}

fn wait_for_verify_navigation_output(mut app SoftwareApp, mode string) {
	for _ in 0 .. 5000 {
		app.poll()
		if mode == 'partial' && app.progress_pending.len >= 8 && !app.progress_seen { return }
		if mode == 'live' && app.progress_seen && app.progress_snapshot.phase == 'verify' { return }
		if mode in ['complete', 'healthy', 'failed']! && app.progress_seen && app.progress_snapshot.phase == 'complete' && app.output.len > 0 { return }
		if mode.starts_with('protected-') && app.progress_seen && app.output.len > 0 { return }
		time.sleep(time.millisecond)
	}
	assert false, 'verification fixture did not reach its output barrier (${mode}): ${app.status}'
}

fn check_software_verify_navigation() ! {
	defer { os.unsetenv('VINIX_SOFTWARE_VERIFY_NAVIGATION') }
	mut app := verify_navigation_app(true)
	defer { app.close_app() }
	for mode in ['partial', 'live', 'complete']! {
		for action in ['software.verify.stop', 'software.cancel', 'escape']! {
			app.focus = true; app.select_all = true
			os.setenv('VINIX_SOFTWARE_VERIFY_NAVIGATION', mode, true); app.handle('software.verify')!
			pid := app.worker.pid
			wait_for_verify_navigation_output(mut app, mode)
			assert app.verification_running() && app.prepare_close() && !app.admin_prompt && !app.focus && !app.select_all
			if mode == 'complete' {
				assert app.status.contains('waiting for the service to exit') && !app.status.contains('files and launchers verified')
				assert editor_bytes_text(app.output).contains('files and launchers verified')
			}
			for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
				tree := app.build(size)!
				assert tree.children.any(it.id == 'software.verify.stop') && tree.children.any(it.text == app.status)
				assert tree.children.any(it.id == 'software.progress') == (mode != 'partial')
				assert !tree.children.any(it.id == 'software.verify')
				free_window_tree(tree)
			}
			for event in ['software.verify', 'software.refresh', 'software.install', 'software.reload', 'software.row.0', 'software.search']! { app.handle(event)! }
			for input in ['\x1b', '\r', '\n', '\x01', '\x08', '\x7f', 'must not edit', '']! { app.paste_input(input) }
			app.key_input('must not edit')
			app.handle(packagecore.request_prefix + '{"id":"editor"}')!
			assert app.worker.pid == pid && app.launch_request == '' && app.query.bytestr() == 'kept query'
			if action == 'escape' { app.key_input('\x1b') } else { app.handle(action)! }
			assert app.worker == unsafe { nil } && C.kill(pid, 0) != 0 && !app.worker_verify && !app.verification_running()
			assert !app.progress_seen && app.progress_snapshot.phase == '' && app.progress_pending.len == 0 && !app.progress_skip
			assert app.output.len == 0 && !app.output_truncated && !app.poll() && app.status.contains('Verification stopped')
			assert app.rows.len == 1 && app.selected == 0 && app.filter == 1 && app.matching == [0]
			assert app.catalog_error == 'catalog expired' && app.update_error == 'publisher revoked'
			full := app.build(ui2.rect(0, 0, 640, 610))!
			assert full.children.any(it.id == 'software.verify') && !full.children.any(it.id == 'software.verify.stop')
			free_window_tree(full)
		}
	}
	for mode in ['failed', 'healthy']! {
		os.setenv('VINIX_SOFTWARE_VERIFY_NAVIGATION', mode, true); app.handle('software.verify')!
		wait_for_verify_navigation_output(mut app, mode)
		assert app.status.contains('waiting for the service to exit') && app.worker != unsafe { nil }
		app.worker.stdin_write('x'); wait_for_software(mut app)
		if mode == 'failed' {
			assert app.status.contains('Storage read failed') && !app.status.contains('files and launchers verified')
			assert app.failure_pages.len > 0 && app.failure_heading.contains('exit 24')
			compact := app.build(ui2.rect(0, 0, 320, 240))!
			assert compact.children.any(it.id == 'software.failure'); free_window_tree(compact)
			app.handle('software.failure')!; app.key_input('\x1b'); assert !app.failure_mode
		} else {
			assert app.status.contains('files and launchers verified') && app.progress_snapshot.phase == 'complete'
			app.stop_verification(); assert app.status.contains('files and launchers verified')
		}
	}
	os.unsetenv('VINIX_SOFTWARE_VERIFY_NAVIGATION')
	for operation in ['update', 'apply', 'run']! {
		mut protected := verify_navigation_app(false)
		if operation == 'apply' { protected.begin_review('install', ['editor']); wait_for_software(mut protected) }
		os.setenv('VINIX_SOFTWARE_VERIFY_NAVIGATION', 'protected-' + operation, true)
		if operation == 'apply' { protected.handle('software.confirm')! }
		else if operation == 'run' { protected.start(['run', 'editor'], false); protected.worker_run = true }
		else { protected.handle('software.refresh')! }
		pid := protected.worker.pid
		wait_for_verify_navigation_output(mut protected, 'protected-' + operation)
		assert protected.progress_seen && protected.progress_snapshot.phase == 'verify' && !protected.verification_running() && !protected.prepare_close()
		for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
			tree := protected.build(size)!
			assert !tree.children.any(it.id == 'software.verify.stop'); free_window_tree(tree)
		}
		protected.handle('software.verify.stop')!; protected.handle('software.cancel')!; protected.key_input('\x1b'); protected.stop_verification()
		assert protected.worker.pid == pid && C.kill(pid, 0) == 0
		protected.worker.stdin_write('x'); wait_for_software(mut protected); protected.close_app()
		os.unsetenv('VINIX_SOFTWARE_VERIFY_NAVIGATION')
	}
	println('Software verification navigation: partial/live/complete-before-exit Stop/Cancel/Escape, pending completion despite human success text, kill/reap and buffer retirement, fresh retry and late failure, compact diagnostics, frozen catalog state and protected verify-phase transactions/launches passed')
}

fn check_software_verify_navigation_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		live := verify_navigation_frame(false); complete := verify_navigation_frame(true)
		arguments := ['--progress', 'verify']
		defer { unsafe { live.free(); complete.free(); (&array(&arguments)).free() } }
		mut app := verify_navigation_app(true)
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				// Allocate an unstarted descriptor: never launch a process in this
				// allocation measurement. Functional barriers above use real children.
				app.worker = os.new_process('/fixture-not-executed'.clone()); app.worker_verify = true
				app.operation_output(unsafe { tos(live.str, 8) }); app.operation_output(unsafe { tos(live.str + 8, live.len - 8) })
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.operation_output(complete); app.operation_line('Installed package files and launchers verified.')
				assert app.status.contains('waiting for the service to exit')
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.key_input('\x1b'); assert app.worker == unsafe { nil } && !app.progress_seen && app.output.len == 0
				app.capture_failure(arguments, 24)
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.clear_failure()
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'verification navigation retained ${kept} bytes'
		println('Software verification navigation: 1000 fragmented/live/complete/wait/full/compact/stop/failure/descriptor-retirement cycles retain zero tracked bytes')
	}
}
