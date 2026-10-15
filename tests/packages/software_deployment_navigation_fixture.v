// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import tools.packages.pkgprotocol

const deployment_navigation_path = '/private/tmp/部署 company apps; $literal.json'

fn deployment_navigation_review(empty bool) pkgprotocol.Review {
	base := fixture_review('deploy', if empty { []string{} } else { ['editor'] })
	if !empty { return base }
	rows := base.rows.map(pkgprotocol.ReviewPackage{ ...it, requested: false, action: 'remove' })
	// Transfer row strings and permission arrays into the removal projection.
	unsafe { (&array(&base.rows)).free(); (&array(&base.requested)).free() }
	return pkgprotocol.Review{ ...base, requested: [], rows: rows }
}

fn software_deployment_navigation_service_fixture(args []string) !bool {
	mode := os.getenv('VINIX_SOFTWARE_DEPLOYMENT_NAVIGATION')
	if mode == '' || args.len < 2 { return false }
	if mode.starts_with('review-') && args[1] == 'deployment-review' {
		assert args.len == 3
		mut review := deployment_navigation_review(args[2] == '/empty.json')
		text := json2.encode(review)
		defer { review.close(); unsafe { text.free() } }
		print(if mode == 'review-partial' { text[..text.len / 2] } else { text }); flush_stdout()
		mut release := u8(0); assert C.read(0, &release, 1) == 1
		if mode == 'review-partial' { print(text[text.len / 2..]) }
		return true
	}
	if mode.starts_with('apply-') && args[1] == 'deployment-apply' {
		assert os.args[1] == '--progress' && args.len == 4 && args[2] == 'c'.repeat(64)
		assert args[3] in [deployment_navigation_path, '/empty.json']!
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'stage', package: 'editor', current: 1, total: 2 }))
		flush_stdout()
		mut release := u8(0); assert C.read(0, &release, 1) == 1 && release == `!`
		if mode == 'apply-failed' { eprintln('Deployment was not activated: disk space changed. Review again.'); exit(23) }
		os.write_file(os.getenv('VINIX_SOFTWARE_DEPLOYMENT_FIXTURE'), json2.encode(args[2..]))!
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 }))
		return true
	}
	return false
}

fn wait_for_deployment_output(mut app SoftwareApp, progress bool) {
	for _ in 0 .. 500 {
		app.poll()
		if (progress && app.progress_seen) || (!progress && app.output.len > 0) { return }
		time.sleep(time.millisecond)
	}
	assert false, 'deployment fixture did not reach its input barrier'
}

fn check_software_deployment_navigation() ! {
	receipt := os.temp_dir() + '/vinix-deployment-navigation-' + os.getpid().str()
	os.setenv('VINIX_SOFTWARE_DEPLOYMENT_FIXTURE', receipt, true)
	defer { os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_DEPLOYMENT_FIXTURE'); os.unsetenv('VINIX_SOFTWARE_DEPLOYMENT_NAVIGATION') }
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192}, query: 'kept search'.bytes(), filter: 1 }
	defer { app.close_app() }
	for path in [deployment_navigation_path, '/empty.json']! {
		for mode in ['review-partial', 'review-complete']! {
			for action in ['software.deployment.stop', 'software.cancel', 'escape']! {
				app.handle('software.deployment')!
				software_repository_text(mut app.deployment_path, path)
				form := app.build(ui2.rect(0, 0, 320, 240))!
				assert form.children.any(it.id == 'software.deployment.back') && form.children.any(it.text == app.status)
				free_window_tree(form)
				os.setenv('VINIX_SOFTWARE_DEPLOYMENT_NAVIGATION', mode, true)
				app.handle('software.deployment.review')!; pid := app.worker.pid
				wait_for_deployment_output(mut app, false)
				assert app.deployment_review_running() && app.prepare_close() && !app.review_ready && !app.admin_prompt
				assert app.worker.args == ['deployment-review', path]
				for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
					tree := app.build(size)!
					assert tree.children.any(it.id == 'software.deployment.stop') && tree.children.any(it.text == app.status)
					assert !tree.children.any(it.id in ['software.confirm', 'software.deployment.review', 'software.deployment.back'])
					free_window_tree(tree)
				}
				app.handle('software.confirm')!; app.paste_input('/must-not-edit.json')
				assert editor_bytes_text(app.deployment_path) == path && !os.exists(receipt)
				if action == 'escape' { app.key_input('\x1b') } else { app.handle(action)! }
				assert app.worker == unsafe { nil } && C.kill(pid, 0) != 0 && !app.worker_review && !app.review_ready
				assert app.review == '' && app.deployment_pending == '' && app.output.len == 0 && !app.output_truncated && !app.poll()
				assert app.deployment_mode && editor_bytes_text(app.deployment_path) == path && app.status.contains('review stopped')
				// Fresh retry preserves the literal filename and obtains a new proposal.
				os.unsetenv('VINIX_SOFTWARE_DEPLOYMENT_NAVIGATION')
				app.handle('software.deployment.review')!; wait_for_software(mut app)
				assert app.review_ready && app.review_snapshot.operation == 'deploy'
				if path == '/empty.json' { assert app.review_snapshot.rows.all(it.action == 'remove') && app.review_snapshot.requested.len == 0 }
				tree := app.build(ui2.rect(0, 0, 320, 240))!
				assert tree.children.any(it.id == 'software.cancel') && !tree.children.any(it.id == 'software.confirm')
				free_window_tree(tree)
				app.handle('software.details')!; assert app.details_mode
				details := app.build(ui2.rect(0, 0, 320, 240))!
				assert details.children.any(it.id == 'software.details.back') && !details.children.any(it.id == 'software.cancel')
				free_window_tree(details)
				app.handle('software.details.back')!; assert app.review_ready && !app.details_mode
				app.key_input('\x1b'); assert app.review == '' && app.deployment_pending == ''
				app.key_input('\x1b'); assert !app.deployment_mode && editor_bytes_text(app.deployment_path) == path
			}
		}
		for mode in ['apply-complete', 'apply-failed']! {
			app.handle('software.deployment')!; software_repository_text(mut app.deployment_path, path)
			app.handle('software.deployment.review')!; wait_for_software(mut app)
			assert app.review_ready
			// Confirmation uses the reviewed filename even if form storage changes.
			software_repository_text(mut app.deployment_path, '/changed-form.json')
			os.setenv('VINIX_SOFTWARE_DEPLOYMENT_NAVIGATION', mode, true)
			app.handle('software.confirm')!; pid := app.worker.pid
			wait_for_deployment_output(mut app, true)
			assert !app.deployment_review_running() && !app.prepare_close() && app.worker.args == ['--progress', 'deployment-apply', 'c'.repeat(64), path]
			for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
				tree := app.build(size)!
				assert tree.children.any(it.id == 'software.progress') && tree.children.any(it.text == app.status)
				assert !tree.children.any(it.id in ['software.deployment.stop', 'software.cancel', 'software.deployment.back', 'software.confirm'])
				free_window_tree(tree)
			}
			for action in ['software.deployment.stop', 'software.cancel', 'software.deployment.back']! { app.handle(action)! }
			app.key_input('\x1b'); app.stop_deployment_review()
			assert app.worker.pid == pid && C.kill(pid, 0) == 0 && !os.exists(receipt)
			release := u8(`!`); assert C.write(app.worker.stdio_fd[0], &release, 1) == 1
			wait_for_software(mut app)
			if mode == 'apply-failed' {
				assert app.deployment_mode && !app.review_ready && app.status.contains('disk space changed')
				compact := app.build(ui2.rect(0, 0, 320, 240))!
				assert compact.children.any(it.id == 'software.failure') && compact.children.any(it.id == 'software.deployment.back')
				assert compact.children.any(it.text == app.status)
				free_window_tree(compact)
				app.handle('software.failure')!; assert app.failure_mode
				app.handle('software.failure.back')!; assert !app.failure_mode && app.deployment_mode
				app.handle('software.deployment.back')!
			} else {
				assert json2.decode[[]string](os.read_file(receipt)!)! == ['c'.repeat(64), path]
				assert !app.deployment_mode && app.review == ''
				os.rm(receipt)!
			}
			os.unsetenv('VINIX_SOFTWARE_DEPLOYMENT_NAVIGATION')
		}
	}
	// Subflows keep their own compact views and lifecycle controls.
	app.handle('software.deployment')!; app.handle('software.deployment.snapshot')!
	snapshot := app.build(ui2.rect(0, 0, 320, 240))!
	assert snapshot.children.any(it.id == 'software.snapshot.back'); free_window_tree(snapshot)
	app.handle('software.snapshot.back')!
	software_repository_text(mut app.deployment_path, '/empty-audit.json')
	app.handle('software.deployment.audit')!; wait_for_software(mut app)
	audit := app.build(ui2.rect(0, 0, 320, 240))!
	assert audit.children.any(it.id == 'software.audit.back'); free_window_tree(audit)
	app.handle('software.audit.back')!
	assert app.query.bytestr() == 'kept search' && app.filter == 1
	println('Software deployment navigation: compact form/review/details/status/progress/failures, partial and complete-before-exit Stop/Cancel/Escape, fresh literal retry, empty removal, protected apply and subflow routing passed')
}

fn check_software_deployment_navigation_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		mut normal := deployment_navigation_review(false); mut empty := deployment_navigation_review(true)
		texts := [json2.encode(normal), json2.encode(empty)]!
		normal.close(); empty.close()
		arguments := ['deployment-apply']
		defer { unsafe { for text in texts { text.free() }; (&array(&arguments)).free() } }
		mut app := SoftwareApp{ output: []u8{cap: 8192} }
		app.initialize_deployment_field()
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				for text in texts {
					app.deployment_mode = true
					software_repository_text(mut app.deployment_path, deployment_navigation_path)
					free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
					free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
					app.review = 'deploy'.clone(); app.deployment_pending = deployment_navigation_path.clone()
					app.output.clear(); for byte in text { app.output << byte }
					app.load_review(); assert app.review_ready
					free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
					free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
					app.open_details(); assert app.details_mode
					free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
					app.handle_details('software.details.back')
					app.deployment_key_input('\x1b'); assert !app.review_ready
					app.capture_failure(arguments, 23)
					free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
					app.clear_failure()
					app.handle_deployment('software.deployment.back')
				}
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'deployment navigation retained ${kept} bytes'
		println('Software deployment navigation: 1000 normal/empty form/review/details/failure render, cancel and retirement cycles retain zero tracked bytes')
	}
}
