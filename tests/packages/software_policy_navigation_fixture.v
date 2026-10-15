// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import tools.packages.pkgprotocol

fn software_policy_navigation_service_fixture(args []string) !bool {
	mode := os.getenv('VINIX_SOFTWARE_POLICY_NAVIGATION')
	if mode == '' || args.len < 2 { return false }
	if (mode.starts_with('list-') && args[1] == 'policy') || (mode.starts_with('review-') && args[1] == 'policy-review') {
		text := if args[1] == 'policy' {
			path := os.getenv('VINIX_SOFTWARE_POLICY_FIXTURE')
			if os.is_file(path) { os.read_file(path)! } else { json2.encode(fixture_policy_document()) }
		} else {
			assert args == [args[0], 'policy-review', policy_fixture_path]
			json2.encode(fixture_policy_review())
		}
		partial := mode.ends_with('-partial')
		print(if partial { text[..text.len / 2] } else { text }); flush_stdout()
		mut release := u8(0); assert C.read(0, &release, 1) == 1
		if partial { print(text[text.len / 2..]) }
		return true
	}
	if mode.starts_with('write-') && args[1] == 'admin' && args.len > 2 && args[2] == 'policy-apply' {
		assert args[3..] == ['c'.repeat(64), policy_fixture_path]
		mut password := [257]u8{}
		mut count := 0
		for count < password.len {
			assert C.read(0, &password[count], 1) == 1
			if password[count] == `\n` { break }; count++
		}
		assert unsafe { tos(&password[0], count) } == 'fixture secret é'
		for index in 0 .. password.len { password[index] = 0 }
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'activate' }))
		flush_stdout()
		// Approval closes stdin. Use a separate explicit barrier after submission.
		release := os.getenv('VINIX_SOFTWARE_POLICY_NAVIGATION_RELEASE')
		for _ in 0 .. 20000 { if os.is_file(release) { break }; time.sleep(time.millisecond) }
		assert os.read_file(release)! == 'release'
		if mode == 'write-failed' { eprintln('Policy review is stale: current configuration changed. Reload and review again.'); exit(23) }
		document := pkgprotocol.PolicyDocument{ format: 1, architecture: 'aarch64', policy: fixture_policy_review().proposed }
		os.write_file(os.getenv('VINIX_SOFTWARE_POLICY_FIXTURE'), json2.encode(document))!
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 }))
		return true
	}
	return false
}

fn wait_for_policy_navigation_output(mut app SoftwareApp, progress bool) {
	for _ in 0 .. 5000 {
		app.poll()
		if (progress && app.progress_seen) || (!progress && app.output.len > 0) { return }
		time.sleep(time.millisecond)
	}
	assert false, 'policy fixture did not reach its output barrier (progress=${progress}, worker=${app.policy_worker}): ${app.status}'
}

fn check_policy_empty_paste(mut app SoftwareApp) {
	path := editor_bytes_text(app.policy_path); storage := app.policy_path.data; capacity := app.policy_path.cap
	status := app.status; page := app.policy_page; section := app.policy_section
	focused := app.focus; selected := app.select_all
	for focus in [false, true]! {
		for selection in [false, true]! {
			app.focus = focus; app.select_all = selection
			app.paste_input('')
			assert editor_bytes_text(app.policy_path) == path && app.policy_path.data == storage && app.policy_path.cap == capacity
			assert app.focus == focus && app.select_all == selection && app.status == status
			assert app.policy_page == page && app.policy_section == section && app.worker == unsafe { nil }
		}
	}
	app.focus = focused; app.select_all = selected
}

fn check_software_policy_navigation() ! {
	receipt := os.temp_dir() + '/vinix-policy-navigation-' + os.getpid().str()
	release := receipt + '.release'
	os.setenv('VINIX_SOFTWARE_POLICY_FIXTURE', receipt, true)
	os.setenv('VINIX_SOFTWARE_POLICY_NAVIGATION_RELEASE', release, true)
	defer {
		os.rm(receipt) or {}; os.rm(release) or {}; os.rm(release + '.pending') or {}
		os.unsetenv('VINIX_SOFTWARE_POLICY_FIXTURE'); os.unsetenv('VINIX_SOFTWARE_POLICY_NAVIGATION')
		os.unsetenv('VINIX_SOFTWARE_POLICY_NAVIGATION_RELEASE')
	}
	mut app := SoftwareApp{ administration_required: true, service_path: os.executable(), output: []u8{cap: 8192}, query: 'kept query'.bytes(), filter: 1 }
	defer { app.close_app() }
	app.handle('software.policy')!; wait_for_software(mut app)
	check_policy_empty_paste(mut app)
	software_repository_text(mut app.policy_path, policy_fixture_path)
	check_policy_empty_paste(mut app)
	for kind in ['list', 'review']! {
		for ending in ['partial', 'complete']! {
			for action in ['software.policy.stop', 'software.policy.cancel', 'escape']! {
				os.setenv('VINIX_SOFTWARE_POLICY_NAVIGATION', kind + '-' + ending, true)
				app.handle(if kind == 'list' { 'software.policy.reload' } else { 'software.policy.review' })!
				pid := app.worker.pid
				wait_for_policy_navigation_output(mut app, false)
				assert app.policy_read_running() && app.prepare_close() && !app.policy_review_ready && !app.admin_prompt
				for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
					tree := app.build(size)!
					assert tree.children.any(it.id == 'software.policy.stop') && tree.children.any(it.text == app.status)
					assert !tree.children.any(it.id in ['software.policy.confirm', 'software.policy.cancel', 'software.policy.back'])
					free_window_tree(tree)
				}
				app.handle('software.policy.read')!; assert !app.policy_reader_mode
				app.handle('software.policy.confirm')!; app.paste_input('/must-not-edit')
				assert editor_bytes_text(app.policy_path) == policy_fixture_path && !os.exists(receipt)
				if action == 'escape' { app.key_input('\x1b') } else { app.handle(action)! }
				assert app.worker == unsafe { nil } && C.kill(pid, 0) != 0 && app.policy_worker == .none && !app.worker_view && !app.worker_review
				assert !app.policy_review_ready && app.policy_pending == '' && app.policy_snapshot.fingerprint == ''
				assert app.output.len == 0 && !app.output_truncated && !app.poll() && app.status.contains('stopped')
				assert editor_bytes_text(app.policy_path) == policy_fixture_path && app.policy_mode && !os.exists(receipt)
				os.unsetenv('VINIX_SOFTWARE_POLICY_NAVIGATION')
				if kind == 'list' {
					assert !app.policy_ready && app.policy_pages.len == 0
					app.handle('software.policy.review')!; assert app.worker == unsafe { nil } && !app.policy_review_ready
					app.handle('software.policy.reload')!; wait_for_software(mut app)
				} else {
					assert app.policy_ready && app.policy_document.policy.allow_firmware && app.policy_pages.all(it.section < 5)
					app.handle('software.policy.review')!; wait_for_software(mut app)
					assert app.policy_review_ready
					app.handle('software.policy.permissions')!; app.handle('software.policy.next')!
					page := app.policy_page; section := app.policy_section
					compact := app.build(ui2.rect(0, 0, 320, 240))!
					assert compact.children.any(it.id == 'software.policy.cancel') && !compact.children.any(it.id == 'software.policy.confirm')
					free_window_tree(compact)
					full := app.build(ui2.rect(0, 0, 640, 610))!
					assert full.children.any(it.id == 'software.policy.confirm') && app.policy_page == page && app.policy_section == section
					free_window_tree(full)
					if action == 'software.policy.cancel' { app.handle(action)! } else { app.key_input('\x1b') }
					assert !app.policy_review_ready && app.policy_pending == '' && app.policy_ready
				}
			}
		}
	}
	// Approval is still a separate cancellable stage before any save starts.
	app.handle('software.policy.review')!; wait_for_software(mut app)
	app.handle('software.policy.confirm')!; assert app.admin_prompt
	approval := app.build(ui2.rect(0, 0, 320, 240))!
	assert approval.children.any(it.id == 'software.admin.cancel'); free_window_tree(approval)
	app.handle('software.admin.cancel')!
	assert app.worker == unsafe { nil } && !app.policy_review_ready && !os.exists(receipt)
	for mode in ['write-complete', 'write-failed']! {
		app.handle('software.policy.review')!; wait_for_software(mut app)
		assert app.policy_review_ready
		os.setenv('VINIX_SOFTWARE_POLICY_NAVIGATION', mode, true)
		app.handle('software.policy.confirm')!
		assert app.admin_prompt && app.worker.args == ['admin', 'policy-apply', 'c'.repeat(64), policy_fixture_path]
		app.key_input('fixture secret é'); app.handle('software.admin.approve')!
		wait_for_policy_navigation_output(mut app, true); pid := app.worker.pid
		assert !app.policy_read_running() && !app.prepare_close() && !app.admin_prompt
		for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
			tree := app.build(size)!
			assert tree.children.any(it.id == 'software.progress') && tree.children.any(it.text == app.status)
			assert !tree.children.any(it.id in ['software.policy.stop', 'software.policy.cancel', 'software.policy.back', 'software.policy.confirm'])
			free_window_tree(tree)
		}
		for action in ['software.policy.stop', 'software.policy.cancel', 'software.policy.back', 'software.policy.reload']! { app.handle(action)! }
		app.handle('software.policy.read')!; assert !app.policy_reader_mode
		app.key_input('\x1b'); app.stop_policy_read(); app.paste_input('/must-not-edit')
		assert app.worker.pid == pid && C.kill(pid, 0) == 0 && !os.exists(receipt) && app.policy_mode
		if mode == 'write-complete' { os.setenv('VINIX_SOFTWARE_POLICY_NAVIGATION', 'list-complete', true) }
		// Publish a complete marker: existence must never expose an empty file
		// while the parent is still writing the release bytes.
		os.write_file(release + '.pending', 'release')!
		os.rename(release + '.pending', release)!
		if mode == 'write-complete' {
			for _ in 0 .. 5000 { app.poll(); if app.policy_worker == .list { break }; time.sleep(time.millisecond) }
			assert app.policy_worker == .list, 'save did not start its reload (worker retired=${app.worker == unsafe { nil }}): ${app.status}'
			wait_for_policy_navigation_output(mut app, false)
			assert app.policy_read_running() && !app.policy_ready && app.policy_result.contains('policy saved') && os.exists(receipt)
			app.handle('software.policy.stop')!
			assert !app.policy_ready && app.policy_pages.len == 0 && app.policy_result.contains('policy saved')
			app.handle('software.policy.review')!; assert app.worker == unsafe { nil }
			os.unsetenv('VINIX_SOFTWARE_POLICY_NAVIGATION'); app.handle('software.policy.reload')!
		}
		wait_for_software(mut app)
		assert !app.policy_review_ready && app.policy_pending == '' && app.prepare_close()
		if mode == 'write-complete' {
			assert app.policy_ready && !app.policy_document.policy.allow_firmware && app.status.contains('policy saved')
			os.rm(receipt)!
		} else {
			assert !app.policy_ready && app.policy_pages.len == 0 && app.status.contains('stale') && app.failure_pages.len > 0
			compact := app.build(ui2.rect(0, 0, 320, 240))!
			assert compact.children.any(it.id == 'software.failure') && compact.children.any(it.id == 'software.policy.back')
			free_window_tree(compact)
			app.handle('software.failure')!; assert app.failure_mode
			app.handle('software.failure.back')!; assert !app.failure_mode && app.policy_mode
			os.unsetenv('VINIX_SOFTWARE_POLICY_NAVIGATION'); app.handle('software.policy.reload')!; wait_for_software(mut app)
		}
		os.rm(release)!; os.unsetenv('VINIX_SOFTWARE_POLICY_NAVIGATION')
	}
	app.handle('software.policy.path')!; app.key_input('\x01'); app.key_input('\x1b')
	assert app.policy_mode && !app.focus && !app.select_all
	app.key_input('\x1b'); assert !app.policy_mode && app.deployment_mode
	assert app.query.bytestr() == 'kept query' && app.filter == 1
	println('Software policy navigation: partial and complete-before-exit read/review Stop/Cancel/Escape, fresh policy requirement, literal retry, compact controls and stable pages, approval cancellation, protected save/progress, stopped post-save reload and failure diagnostics passed')
}

fn check_software_policy_navigation_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		mut document := fixture_policy_document(); mut review := fixture_policy_review()
		document_text := json2.encode(document); review_text := json2.encode(review)
		document.close(); review.close()
		arguments := ['policy-apply']
		defer { unsafe { document_text.free(); review_text.free(); (&array(&arguments)).free() } }
		mut app := SoftwareApp{ policy_mode: true, output: []u8{cap: 8192} }
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.initialize_policy_path(); software_repository_text(mut app.policy_path, policy_fixture_path)
				app.output.clear(); for byte in document_text { app.output << byte }; app.load_policy_document()
				check_policy_empty_paste(mut app)
				policy_reader_cycle(mut app)!
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.policy_pending = policy_fixture_path.clone()
				app.output.clear(); for byte in review_text { app.output << byte }; app.load_policy_review(); assert app.policy_review_ready
				policy_reader_cycle(mut app)!
				for action in ['software.policy.source', 'software.policy.permissions', 'software.policy.impacts']! {
					app.handle_policy(action); app.handle_policy('software.policy.next')
					free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				}
				app.policy_key_input('\x1b'); assert !app.policy_review_ready
				app.capture_failure(arguments, 23)
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.clear_failure(); app.clear_policy()
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'policy navigation retained ${kept} bytes'
		println('Software policy navigation: 1000 document/review/section/page/full/compact/cancel/failure/retirement cycles retain zero tracked bytes')
		println('Software policy reader: 1000 current/review/cache/compact/full/keys/back/cancel/retirement cycles retain zero tracked bytes')
	}
}

fn policy_reader_cycle(mut app SoftwareApp) ! {
	app.handle('software.policy.read')!; assert app.policy_reader_mode
	free_window_tree(app.build(ui2.rect(0, 0, 180, 220))!)
	app.key_input('\x1b[C'); app.key_input('\t')
	anchor := app.policy_compact_page; canonical := app.policy_page
	free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
	free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
	assert app.policy_compact_page == anchor && app.policy_page == canonical
	app.handle('software.policy.confirm')!; assert app.worker == unsafe { nil } && !app.admin_prompt
	app.key_input('\x1b'); assert !app.policy_reader_mode
}
