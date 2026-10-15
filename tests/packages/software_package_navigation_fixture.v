// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import tools.packages.pkgprotocol

const package_navigation_operations = ['install', 'remove', 'upgrade', 'repair', 'rollback']!

fn package_navigation_review(operation string, names []string) pkgprotocol.Review {
	base := fixture_review(operation, names)
	if operation != 'remove' { return base }
	rows := base.rows.map(pkgprotocol.ReviewPackage{ ...it, requested: false, action: 'remove' })
	// Transfer the row strings and permission arrays into the removal projection.
	unsafe { (&array(&base.rows)).free(); (&array(&base.requested)).free() }
	return pkgprotocol.Review{ ...base, requested: [], rows: rows }
}

fn software_package_navigation_service_fixture(args []string) !bool {
	mode := os.getenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION')
	if mode == '' || args.len < 2 { return false }
	if mode.starts_with('review-') && args[1] == 'review' {
		assert args[2] in package_navigation_operations
		text := json2.encode(package_navigation_review(args[2], args[3..]))
		partial := mode == 'review-partial'
		print(if partial { text[..text.len / 2] } else { text }); flush_stdout()
		mut release := u8(0); assert C.read(0, &release, 1) == 1
		if partial { print(text[text.len / 2..]) }
		return true
	}
	if mode.starts_with('apply-') && args[1] == 'apply' {
		assert os.args[1] == '--progress' && args[2] == 'c'.repeat(64) && args[3] in package_navigation_operations
		assert args[4..] == if args[3] in ['install', 'remove']! { ['editor'] } else { []string{} }
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'stage', current: 1, total: 2 }))
		flush_stdout()
		mut release := u8(0); assert C.read(0, &release, 1) == 1 && release == `!`
		if mode == 'apply-failed' { eprintln('Package operation was not activated: disk space changed. Review again.'); exit(23) }
		os.write_file(os.getenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION_RECEIPT'), json2.encode(args[2..]))!
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 }))
		return true
	}
	if mode == 'refresh' && args[1] == 'update' {
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'metadata', repository: 'fixture', path: 'index.json', current: 1 }))
		flush_stdout()
		mut release := u8(0); assert C.read(0, &release, 1) == 1 && release == `!`
		return true
	}
	return false
}

fn seed_package_navigation_catalog(mut app SoftwareApp) {
	if app.rows.len != 0 { app.selected = 0; return }
	unsafe { (&array(&app.rows)).free(); (&array(&app.matching)).free() }
	app.rows = [SoftwareRow{ id: 'editor', name: 'Editor', description: 'Write documents', version: '1.0.0', installed_version: '1.0.0',
		architecture: 'aarch64', kind: 'native', repository: 'fixture', public_key: 'a'.repeat(64), license: 'MIT', permissions: ['files'], requested: true }]
	app.matching = [0]; app.selected = 0
}

fn wait_for_package_navigation_output(mut app SoftwareApp, progress bool) {
	for _ in 0 .. 1000 {
		app.poll()
		if (progress && app.progress_seen) || (!progress && app.output.len > 0) { return }
		time.sleep(time.millisecond)
	}
	assert false, 'package fixture did not reach its input barrier'
}

fn check_package_navigation_writer(mut app SoftwareApp) ! {
	pid := app.worker.pid
	assert !app.package_review_running() && !app.prepare_close()
	compact := app.build(ui2.rect(0, 0, 320, 240))!
	assert compact.children.any(it.id == 'software.progress') && compact.children.any(it.text == app.status)
	assert !compact.children.any(it.id in ['software.review.stop', 'software.cancel', 'software.reload', 'software.confirm'])
	free_window_tree(compact)
	for action in ['software.review.stop', 'software.cancel', 'software.reload', 'software.search']! { app.handle(action)! }
	app.key_input('\x1b'); app.stop_package_review(); app.key_input('must-not-edit')
	assert app.worker.pid == pid && C.kill(pid, 0) == 0 && app.query.bytestr() == 'Editor'
}

fn check_software_package_navigation() ! {
	receipt := os.temp_dir() + '/vinix-package-navigation-' + os.getpid().str()
	os.setenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION_RECEIPT', receipt, true)
	defer { os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION_RECEIPT'); os.unsetenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION') }
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192}, query: 'Editor'.bytes(), filter: 1 }
	seed_package_navigation_catalog(mut app)
	defer { app.close_app() }
	for operation in package_navigation_operations {
		for mode in ['review-partial', 'review-complete']! {
			for action in ['software.review.stop', 'software.cancel', 'escape']! {
				os.setenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION', mode, true)
				app.handle('software.' + operation)!; pid := app.worker.pid
				wait_for_package_navigation_output(mut app, false)
				assert app.package_review_running() && app.prepare_close() && !app.review_ready && !app.admin_prompt
				assert app.worker.args == ['review', operation, ...if operation in ['install', 'remove']! { ['editor'] } else { []string{} }]
				for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
					tree := app.build(size)!
					assert tree.children.any(it.id == 'software.review.stop') && tree.children.any(it.text == app.status)
					assert !tree.children.any(it.id in ['software.confirm', 'software.cancel'])
					free_window_tree(tree)
				}
				app.handle('software.confirm')!; app.handle('software.search')!; app.key_input('must-not-edit')
				assert !os.exists(receipt) && app.query.bytestr() == 'Editor' && !app.focus
				if action == 'escape' { app.key_input('\x1b') } else { app.handle(action)! }
				assert app.worker == unsafe { nil } && C.kill(pid, 0) != 0 && !app.worker_review && !app.review_ready
				assert app.review == '' && app.review_names.len == 0 && app.review_snapshot.fingerprint == '' && app.output.len == 0 && !app.output_truncated && !app.poll()
				assert app.selected == 0 && app.filter == 1 && app.scroll == 0 && app.query.bytestr() == 'Editor' && app.status.contains('review stopped')
				// Retry must obtain a new complete review after the old worker is gone.
				os.unsetenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION')
				app.handle('software.' + operation)!; wait_for_software(mut app)
				assert app.review_ready && app.review_snapshot.operation == operation
				app.handle('software.row.1')!; assert app.review_selected == 1 && app.selected == 0
				compact := app.build(ui2.rect(0, 0, 320, 240))!
				assert compact.children.any(it.id == 'software.cancel') && !compact.children.any(it.id == 'software.confirm')
				free_window_tree(compact)
				app.handle('software.details')!; assert app.details_mode
				details := app.build(ui2.rect(0, 0, 320, 240))!
				assert details.children.any(it.id == 'software.details.back') && !details.children.any(it.id == 'software.cancel')
				free_window_tree(details)
				app.key_input('\x1b'); assert !app.details_mode && app.review_ready && app.review_selected == 1
				full := app.build(ui2.rect(0, 0, 640, 610))!
				assert full.children.any(it.id == 'software.confirm'); free_window_tree(full)
				app.key_input('\x1b'); assert !app.review_ready && app.review == '' && app.selected == 0
			}
		}
		for mode in ['apply-complete', 'apply-failed']! {
			seed_package_navigation_catalog(mut app)
			app.handle('software.' + operation)!; wait_for_software(mut app)
			assert app.review_ready
			// Confirmation owns the service's reviewed intent, not current selection.
			app.selected = -1
			os.setenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION', mode, true)
			app.handle('software.confirm')!
			wait_for_package_navigation_output(mut app, true); check_package_navigation_writer(mut app)!
			release := u8(`!`); assert C.write(app.worker.stdio_fd[0], &release, 1) == 1
			wait_for_software(mut app)
			assert !app.review_ready && app.review == '' && app.prepare_close()
			if mode == 'apply-failed' {
				assert app.status.contains('disk space changed') && !os.exists(receipt)
				compact := app.build(ui2.rect(0, 0, 320, 240))!
				assert compact.children.any(it.id == 'software.failure') && compact.children.any(it.id == 'software.reload')
				free_window_tree(compact)
				app.handle('software.failure')!; assert app.failure_mode
				app.handle('software.failure.back')!; assert !app.failure_mode
			} else {
				assert json2.decode[[]string](os.read_file(receipt)!)! == ['c'.repeat(64), operation, ...if operation in ['install', 'remove']! { ['editor'] } else { []string{} }]
				assert app.rows.len == 0, 'successful transaction did not reload the catalog'
				os.rm(receipt)!
			}
			os.unsetenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION'); app.clear_failure()
		}
		seed_package_navigation_catalog(mut app)
	}
	// A catalog refresh is a writer, not a read-only package proposal.
	os.setenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION', 'refresh', true)
	app.handle('software.search')!; assert app.focus
	app.handle('software.refresh')!; wait_for_package_navigation_output(mut app, true)
	check_package_navigation_writer(mut app)!
	release := u8(`!`); assert C.write(app.worker.stdio_fd[0], &release, 1) == 1
	wait_for_software(mut app); os.unsetenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION')
	seed_package_navigation_catalog(mut app)
	app.handle('software.details')!; assert app.details_mode
	details := app.build(ui2.rect(0, 0, 320, 240))!
	assert details.children.any(it.id == 'software.details.back'); free_window_tree(details)
	app.handle('software.details.back')!; assert !app.details_mode && app.selected == 0
	compact := app.build(ui2.rect(0, 0, 320, 240))!
	assert compact.children.any(it.id == 'software.reload') && compact.children.any(it.text == app.status)
	free_window_tree(compact)
	app.handle('software.reload')!; wait_for_software(mut app)
	for other in [SoftwareApp{ policy_mode: true }, SoftwareApp{ data_mode: true }, SoftwareApp{ launch_mode: true },
		SoftwareApp{ deployment_mode: true }, SoftwareApp{ mirror_mode: true }, SoftwareApp{ repository_mode: true },
		SoftwareApp{ health_mode: true }, SoftwareApp{ cleanup_mode: true }, SoftwareApp{ audit_mode: true }, SoftwareApp{ snapshot_mode: true }, SoftwareApp{ window_mode: true }]! {
		assert !other.package_screen_active() && !other.package_review_running()
	}
	assert app.query.bytestr() == 'Editor' && app.filter == 1
	println('Software package navigation: all five operations, partial and complete-before-exit Stop/Cancel/Escape, fresh retry, frozen catalog state, compact review/details/status/progress/failures, protected apply/refresh and reload passed')
}

fn check_software_package_navigation_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		mut texts := []string{cap: 5}
		for operation in package_navigation_operations {
			mut review := package_navigation_review(operation, if operation in ['install', 'remove']! { ['editor'.clone()] } else { []string{} })
			texts << json2.encode(review); review.close()
		}
		arguments := ['apply']
		defer { unsafe { for text in texts { text.free() }; (&array(&texts)).free(); (&array(&arguments)).free() } }
		mut app := SoftwareApp{ output: []u8{cap: 8192}, query: 'Editor'.bytes(), filter: 1 }
		seed_package_navigation_catalog(mut app)
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				for index, text in texts {
					operation := package_navigation_operations[index]
					app.review = operation.clone()
					if operation in ['install', 'remove']! { app.review_names << 'editor'.clone() }
					app.output.clear(); for byte in text { app.output << byte }; app.load_review(); assert app.review_ready
					free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
					app.open_details(); assert app.details_mode
					free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!); app.key_input('\x1b')
					app.key_input('\x1b'); assert !app.review_ready
				}
				app.open_details(); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!); app.handle_details('software.details.back')
				app.capture_failure(arguments, 23); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!); app.clear_failure()
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'package navigation retained ${kept} bytes'
		println('Software package navigation: 1000 catalog and five-operation full/compact/review/details/failure/cancel/retirement cycles retain zero tracked bytes')
	}
}
