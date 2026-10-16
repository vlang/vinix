// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import tools.packages.pkgprotocol

const deployment_navigation_path = '/private/tmp/部署 company apps; $literal.json'

fn check_software_distribution_path_paste() ! {
	mut app := SoftwareApp{ output: []u8{cap: 8192} }
	app.initialize_deployment_field(); app.initialize_mirror_field()
	defer { app.close_app() }
	original := '/literal 部署 é🚀; $source.json'
	for form in 0 .. 3 {
		app.deployment_mode = form == 0; app.mirror_mode = form > 0
		app.mirror_locked = form == 2; app.mirror_lock_focus = form == 2; app.focus = true
		software_repository_text(mut app.deployment_path, original)
		software_repository_text(mut app.mirror_path, original)
		software_repository_text(mut app.mirror_lock_path, original)
		mut field := match form { 0 { &app.deployment_path } 1 { &app.mirror_path } else { &app.mirror_lock_path } }
		for selected in [false, true]! {
			app.select_all = selected
			for input in ['\x1b', '\r', '\n', '\t', '\x1b[Z', '\x01', '\x7f', '\x08', '\x00',
				'/bad\npath', '/bad\x00path', '\xff', '\xc3', '\xe2\x82', '\xc0\xaf', '\xed\xa0\x80', '\xf4\x90\x80\x80', '\xc2\x80', '\xc2\x9f']! {
				app.paste_input(input)
				assert app.focus && app.select_all == selected && app.worker == unsafe { nil } && app.review == ''
				assert app.deployment_mode == (form == 0) && app.mirror_mode == (form > 0) && app.mirror_lock_focus == (form == 2)
				assert editor_bytes_text(app.deployment_path) == original && editor_bytes_text(app.mirror_path) == original
				assert editor_bytes_text(app.mirror_lock_path) == original && app.status.contains('field was kept intact')
			}
			app.set_status('kept status'); app.paste_input('')
			assert app.focus && app.select_all == selected && app.status == 'kept status' && editor_bytes_text(*field) == original
		}
		value := original + 'q'.repeat(4096 - original.len)
		oversized := value + '🚀'
		app.select_all = true; app.paste_input(value)
		assert editor_bytes_text(*field) == value && field.len == 4096 && !app.select_all
		app.paste_input('🚀'); assert editor_bytes_text(*field) == value && !app.select_all
		app.select_all = true; app.paste_input(oversized)
		assert editor_bytes_text(*field) == value && app.select_all
		app.paste_input(original); assert editor_bytes_text(*field) == original && !app.select_all
		app.paste_input('🚀'); app.key_input('\x7f'); assert editor_bytes_text(*field) == original
		app.key_input('\x01'); app.key_input('\x08'); assert field.len == 0 && !app.select_all
		app.paste_input(original); app.key_input('\r'); assert !app.focus && editor_bytes_text(*field) == original
		app.select_all = true
		app.paste_input('\x1b'); app.paste_input('/ignored'); app.paste_input('')
		assert !app.focus && app.select_all && editor_bytes_text(*field) == original
		assert app.deployment_mode == (form == 0) && app.mirror_mode == (form > 0)
		unsafe { value.free(); oversized.free() }
	}
	// A saved deployment owns the source path; only its destination is editable.
	app.mirror_source = '/saved 部署.json'.clone(); app.mirror_source_sha256 = 'd'.repeat(64)
	app.focus = true; app.select_all = true; app.mirror_lock_focus = true
	app.paste_input('/changed-source.json')
	assert editor_bytes_text(app.mirror_lock_path) == original && app.select_all && app.mirror_source == '/saved 部署.json'
	app.mirror_lock_focus = false; app.paste_input('/new-destination é; $literal')
	assert editor_bytes_text(app.mirror_path) == '/new-destination é; $literal' && !app.select_all
	assert app.mirror_source == '/saved 部署.json' && app.mirror_source_sha256 == 'd'.repeat(64)
	println('Software distribution path paste: deployment/destination/lock fields, atomic controls/UTF-8/4096-byte refusal, preserved focus/selection, literal append/replace, empty/unfocused no-op, keyboard editing and fixed saved source PASS')
}

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
	check_software_distribution_path_paste()!
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
				assert form.children.any(it.id == 'software.deployment.back') && form.children.any(it.id == 'software.status')
				free_window_tree(form)
				os.setenv('VINIX_SOFTWARE_DEPLOYMENT_NAVIGATION', mode, true)
				app.handle('software.deployment.review')!; pid := app.worker.pid
				wait_for_deployment_output(mut app, false)
				assert app.deployment_review_running() && app.prepare_close() && !app.review_ready && !app.admin_prompt
				assert app.worker.args == ['deployment-review', path]
				for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
					tree := app.build(size)!
					assert tree.children.any(it.id == 'software.deployment.stop') && tree.children.any(it.text == app.status)
					assert !tree.children.any(it.id in ['software.confirm', 'software.deployment.review', 'software.deployment.back', 'software.report.read'])
					free_window_tree(tree)
				}
				app.handle('software.confirm')!; app.paste_input('/must-not-edit.json')
				app.handle('software.report.read')!; assert !app.report_reader_mode && app.worker.pid == pid && app.details_pages.len == 0
				for input in ['\x1b', '\r', '\n', '\x01', '\x08', '\x7f']! { app.paste_input(input) }
				assert app.worker.pid == pid && app.deployment_review_running()
				assert editor_bytes_text(app.deployment_path) == path && !os.exists(receipt)
				if action == 'escape' { app.key_input('\x1b') } else { app.handle(action)! }
				assert app.worker == unsafe { nil } && C.kill(pid, 0) != 0 && !app.worker_review && !app.review_ready
				assert app.review == '' && app.deployment_pending == '' && app.output.len == 0 && !app.output_truncated && !app.poll()
				assert app.deployment_mode && editor_bytes_text(app.deployment_path) == path && app.status.contains('review stopped')
				// Fresh retry preserves the literal filename and obtains a new proposal.
				os.unsetenv('VINIX_SOFTWARE_DEPLOYMENT_NAVIGATION')
				app.handle('software.deployment.review')!; wait_for_software(mut app)
				assert app.review_ready && app.review_snapshot.operation == 'deploy'
				for input in ['\x1b', '\r', '\n', '\x01', '\x08', '\x7f']! { app.paste_input(input) }
				assert app.review_ready && app.deployment_pending == path && app.worker == unsafe { nil }
				if path == '/empty.json' { assert app.review_snapshot.rows.all(it.action == 'remove') && app.review_snapshot.requested.len == 0 }
				package_plan_cycle(mut app, false)!
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
				assert !tree.children.any(it.id in ['software.deployment.stop', 'software.cancel', 'software.deployment.back', 'software.confirm', 'software.report.read'])
				free_window_tree(tree)
			}
			for action in ['software.deployment.stop', 'software.cancel', 'software.deployment.back']! { app.handle(action)! }
			app.handle('software.report.read')!; assert !app.report_reader_mode && app.worker.pid == pid
			for input in ['\x1b', '\r', '\n', '\x01', '\x08', '\x7f']! { app.paste_input(input) }
			app.key_input('\x1b'); app.stop_deployment_review()
			assert app.worker.pid == pid && C.kill(pid, 0) == 0 && !os.exists(receipt)
			release := u8(`!`); assert C.write(app.worker.stdio_fd[0], &release, 1) == 1
			wait_for_software(mut app)
			if mode == 'apply-failed' {
				assert app.deployment_mode && !app.review_ready && app.status.contains('disk space changed')
				compact := app.build(ui2.rect(0, 0, 320, 240))!
				assert compact.children.any(it.id == 'software.status') && compact.children.any(it.id == 'software.deployment.back')
				free_window_tree(compact)
				deployment_form_select(mut app, 'software.failure')!; assert app.failure_mode
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
					app.focus = true; app.select_all = true; app.deployment_paste_input(deployment_navigation_path)
					app.select_all = true; app.deployment_paste_input('\x1b'); app.deployment_paste_input('bad\xff')
					app.deployment_paste_input(''); assert app.focus && app.select_all && editor_bytes_text(app.deployment_path) == deployment_navigation_path
					software_repository_text(mut app.deployment_path, deployment_navigation_path)
					free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
					free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
					app.review = 'deploy'.clone(); app.deployment_pending = deployment_navigation_path.clone()
					app.output.clear(); for byte in text { app.output << byte }
					app.load_review(); assert app.review_ready
					package_plan_cycle(mut app, false)!
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
		println('Software deployment path paste: 1000 literal/rejected/selected/empty input cycles retain zero tracked bytes')
		println('Software deployment plan reader: 1000 normal/removal-only/decode/read/item/page/render/resize/ignored-confirm/Back/cancel/cache-retirement cycles retain zero tracked bytes')
	}
}
