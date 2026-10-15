// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import tools.packages.pkgprotocol

fn software_mirror_navigation_service_fixture(args []string) !bool {
	mode := os.getenv('VINIX_SOFTWARE_MIRROR_NAVIGATION')
	if mode == '' || args.len < 2 { return false }
	if mode.starts_with('review-') && args[1] in ['mirror-review', 'mirror-deployment-review']! {
		locked := software_snapshot_export_review(if args[1] == 'mirror-deployment-review' { args[3] } else { mirror_fixture_lock }, false)
		text := if args[1] == 'mirror-deployment-review' { json2.encode(locked) } else { json2.encode(locked.mirror) }
		print(if mode == 'review-partial' { text[..text.len / 2] } else { text }); flush_stdout()
		// Keep the child alive after a partial OR a complete JSON document. The
		// review cannot be admitted until exit, and Stop must reap either case.
		mut release := u8(0); assert C.read(0, &release, 1) == 1
		if mode == 'review-partial' { print(text[text.len / 2..]) }
		return true
	}
	if mode.starts_with('writer-') && args[1] == 'mirror-deployment-apply' {
		assert os.args[1] == '--progress' && args[2..] == ['d'.repeat(64), mirror_fixture_destination, software_snapshot_fixture_path]
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'copy', package: 'runtime', path: 'lib/runtime', current: 1, total: 2 }))
		flush_stdout()
		mut release := u8(0); assert C.read(0, &release, 1) == 1 && release == `!`
		os.write_file(os.getenv('VINIX_SOFTWARE_MIRROR_FIXTURE'), 'published mirror')!
		if mode == 'writer-failure' { eprintln('Complete mirror exists, but the parent directory could not be flushed.'); exit(23) }
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 }))
		println('Offline deployment mirror ready: ' + mirror_fixture_destination + '/_deployment.json')
		return true
	}
	return false
}

fn prepare_mirror_navigation(mut app SoftwareApp, locked bool) ! {
	app.handle('software.mirror')!
	if locked {
		app.snapshot_ready = true; app.snapshot_mode = true
		app.snapshot_pending = software_snapshot_fixture_path.clone()
		app.snapshot_saved = software_snapshot_fixture_receipt(software_snapshot_fixture_path)
		app.handle_deployment_snapshot('software.snapshot.export')
	} else { app.mirror_locked = false; app.mirror_all = false }
	software_repository_text(mut app.mirror_path, mirror_fixture_destination)
}

fn wait_for_mirror_output(mut app SoftwareApp, progress bool) {
	for _ in 0 .. 500 {
		app.poll()
		if (progress && app.progress_seen) || (!progress && app.output.len > 0) { return }
		time.sleep(time.millisecond)
	}
	assert false, 'mirror fixture did not reach its input barrier'
}

fn check_software_mirror_navigation() ! {
	receipt := os.temp_dir() + '/vinix-mirror-navigation-' + os.getpid().str()
	os.setenv('VINIX_SOFTWARE_MIRROR_FIXTURE', receipt, true)
	defer { os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_MIRROR_FIXTURE'); os.unsetenv('VINIX_SOFTWARE_MIRROR_NAVIGATION') }
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192}, query: 'kept query'.bytes(), filter: 1,
		rows: [SoftwareRow{ id: 'editor', name: 'Editor' }], selected: 0 }
	defer { app.close_app() }
	for locked in [false, true]! {
		for mode in ['review-partial', 'review-complete'] {
			for action in ['software.mirror.stop', 'software.cancel', 'escape'] {
				prepare_mirror_navigation(mut app, locked)!
				os.setenv('VINIX_SOFTWARE_MIRROR_NAVIGATION', mode, true)
				app.handle('software.mirror.review')!
				pid := app.worker.pid
				wait_for_mirror_output(mut app, false)
				assert app.mirror_review_running() && !app.review_ready && app.prepare_close() && !os.exists(receipt)
				for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)] {
					tree := app.build(size)!
					assert tree.children.any(it.id == 'software.mirror.stop') && tree.children.any(it.text == app.status)
					assert !tree.children.any(it.id in ['software.confirm', 'software.mirror.review', 'software.mirror.back'])
					free_window_tree(tree)
				}
				app.handle('software.confirm')!; assert app.worker.pid == pid && !app.review_ready
				for input in ['\x1b', '\r', '\n', '\x01', '\x08', '\x7f']! { app.paste_input(input) }
				assert app.worker.pid == pid && app.mirror_review_running()
				if action == 'escape' { app.key_input('\x1b') } else { app.handle(action)! }
				assert app.worker == unsafe { nil } && !app.worker_review && !app.review_ready && app.review == ''
				assert app.output.len == 0 && !app.output_truncated && app.mirror_pages.len == 0 && !app.poll()
				assert app.status.contains('review stopped') && C.kill(pid, 0) != 0 && !os.exists(receipt)
				assert app.mirror_mode && editor_bytes_text(app.mirror_path) == mirror_fixture_destination
				if locked { assert app.mirror_source == software_snapshot_fixture_path && app.mirror_source_sha256 == 'd'.repeat(64) }
				compact := app.build(ui2.rect(0, 0, 320, 240))!
				assert compact.children.any(it.id == 'software.mirror.back'); free_window_tree(compact)
				// A fresh review after cancellation must use the preserved intent.
				os.unsetenv('VINIX_SOFTWARE_MIRROR_NAVIGATION')
				app.handle('software.mirror.review')!; wait_for_software(mut app)
				assert app.review_ready && app.mirror_details
				for input in ['\x1b', '\r', '\n', '\x01', '\x08', '\x7f']! { app.paste_input(input) }
				assert app.review_ready && app.mirror_details && app.mirror_pending == mirror_fixture_destination && app.worker == unsafe { nil }
				for packages in [false, true]! {
					if packages {
						for app.mirror_seen + 1 < app.mirror_pages.len { app.handle('software.mirror.next')! }
						app.handle('software.mirror.packages')!
					}
					tree := app.build(ui2.rect(0, 0, 320, 240))!
					assert tree.children.any(it.id == 'software.cancel') && !tree.children.any(it.id == 'software.confirm')
					free_window_tree(tree)
					if packages {
						app.handle('software.details')!; assert app.details_mode
						details := app.build(ui2.rect(0, 0, 320, 240))!
						assert details.children.any(it.id == 'software.details.back') && !details.children.any(it.id == 'software.cancel')
						free_window_tree(details)
						app.handle('software.details.back')!; assert !app.details_mode && app.review_ready
					}
				}
				app.key_input('\x1b'); assert !app.review_ready && app.mirror_pages.len == 0
				app.handle('software.mirror.back')!
				assert !app.mirror_mode && app.mirror_source == '' && app.mirror_source_sha256 == ''
			}
		}
	}
	for mode in ['writer-complete', 'writer-failure'] {
		prepare_mirror_navigation(mut app, true)!
		app.handle('software.mirror.review')!; wait_for_software(mut app)
		for app.mirror_seen + 1 < app.mirror_pages.len { app.handle('software.mirror.next')! }
		app.handle('software.mirror.packages')!
		os.setenv('VINIX_SOFTWARE_MIRROR_NAVIGATION', mode, true)
		app.handle('software.confirm')!; pid := app.worker.pid
		wait_for_mirror_output(mut app, true)
		assert app.worker_mirror && !app.mirror_review_running() && !app.prepare_close()
		for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)] {
			tree := app.build(size)!
			assert tree.children.any(it.id == 'software.progress') && tree.children.any(it.text == app.status)
			assert !tree.children.any(it.id in ['software.mirror.stop', 'software.cancel', 'software.mirror.back', 'software.confirm'])
			free_window_tree(tree)
		}
		for action in ['software.mirror.stop', 'software.cancel', 'software.mirror.back'] { app.handle(action)! }
		for input in ['\x1b', '\r', '\n', '\x01', '\x08', '\x7f']! { app.paste_input(input) }
		app.key_input('\x1b'); app.stop_mirror_review()
		assert app.worker.pid == pid && C.kill(pid, 0) == 0 && app.mirror_mode && !os.exists(receipt)
		release := u8(`!`); assert C.write(app.worker.stdio_fd[0], &release, 1) == 1
		wait_for_software(mut app)
		assert os.read_file(receipt)! == 'published mirror'
		compact := app.build(ui2.rect(0, 0, 320, 240))!
		assert compact.children.any(it.id == 'software.mirror.back') && compact.children.any(it.text == app.status)
		if mode == 'writer-failure' {
			assert app.status.contains('mirror exists') && app.failure_pages.len > 0
			assert compact.children.any(it.id == 'software.failure')
			app.handle('software.failure')!; assert app.failure_mode
			app.handle('software.failure.back')!; assert !app.failure_mode && app.mirror_mode
		} else { assert app.status.contains('/_deployment.json') }
		free_window_tree(compact)
		app.handle('software.mirror.back')!; os.rm(receipt)!
		os.unsetenv('VINIX_SOFTWARE_MIRROR_NAVIGATION')
	}
	assert app.query.bytestr() == 'kept query' && app.filter == 1 && app.selected == 0
	println('Software offline export navigation: compact Back/Cancel/Stop/status/progress/failures, partial and complete-before-exit review cancellation/reaping, frozen retry and protected publication passed')
}

fn check_software_mirror_navigation_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		text := json2.encode(software_snapshot_export_review(software_snapshot_fixture_path, false))
		arguments := ['mirror-deployment-apply']
		defer { unsafe { text.free(); (&array(&arguments)).free() } }
		mut app := SoftwareApp{ output: []u8{cap: 8192} }
		app.initialize_mirror_field()
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.snapshot_ready = true; app.snapshot_mode = true
				app.snapshot_pending = software_snapshot_fixture_path.clone()
				app.snapshot_saved = software_snapshot_fixture_receipt(software_snapshot_fixture_path)
				app.handle_deployment_snapshot('software.snapshot.export')
				app.select_all = true; app.mirror_paste_input(mirror_fixture_destination)
				app.select_all = true; app.mirror_paste_input('\x1b'); app.mirror_paste_input('bad\xff'); app.mirror_paste_input('')
				assert app.focus && app.select_all && editor_bytes_text(app.mirror_path) == mirror_fixture_destination
				free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.review = 'mirror'.clone(); app.mirror_pending = mirror_fixture_destination.clone()
				app.mirror_lock_pending = app.mirror_source.clone()
				app.output.clear(); for byte in text { app.output << byte }
				app.load_review(); assert app.review_ready
				free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				for app.mirror_seen + 1 < app.mirror_pages.len { app.handle_mirror('software.mirror.next') }
				app.handle_mirror('software.mirror.packages')
				free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.open_details(); assert app.details_mode
				free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.handle_details('software.details.back')
				app.mirror_key_input('\x1b'); assert !app.review_ready
				app.worker_failed = true
				app.capture_failure(arguments, 23)
				free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.clear_failure(); app.worker_failed = false
				app.handle_mirror('software.mirror.back')
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'offline export navigation retained ${kept} bytes'
		println('Software offline export navigation: 1000 compact form/path/package/failure render, cancel and retirement cycles retain zero tracked bytes')
		println('Software offline path paste: 1000 literal/rejected/selected/empty input cycles retain zero tracked bytes')
	}
}
