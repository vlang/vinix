// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import tools.packages.pkgprotocol

fn fixture_cleanup_navigation_review(empty bool) pkgprotocol.CleanupReview {
	return pkgprotocol.CleanupReview{ architecture: 'aarch64', generation: 5000, previous: 4999,
		fingerprint: 'd'.repeat(64), generations: if empty { []u64{} } else { []u64{len: 4096, init: u64(index + 1)} } }
}

fn software_cleanup_navigation_service_fixture(args []string) !bool {
	mode := os.getenv('VINIX_SOFTWARE_CLEANUP_NAVIGATION')
	if mode == '' || args.len < 2 { return false }
	if mode.starts_with('review-') && args[1..] == ['cleanup-review'] {
		text := json2.encode(fixture_cleanup_navigation_review(os.exists(os.getenv('VINIX_SOFTWARE_CLEANUP_RECEIPT'))))
		partial := mode == 'review-partial'
		print(if partial { text[..text.len / 2] } else { text }); flush_stdout()
		mut release := u8(0); assert C.read(0, &release, 1) == 1
		if mode == 'review-failed' { eprintln('Cleanup inventory unavailable: inspect retained generation leases and reload.'); exit(21) }
		if partial { print(text[text.len / 2..]) }
		return true
	}
	if mode.starts_with('apply-') && args[1] == 'admin' && args.len > 2 && args[2] == 'cleanup-apply' {
		assert args[1..] == ['admin', 'cleanup-apply', 'd'.repeat(64)]
		mut password := [257]u8{}
		mut count := 0
		for count < password.len {
			assert C.read(0, &password[count], 1) == 1
			if password[count] == `\n` { break }; count++
		}
		assert unsafe { tos(&password[0], count) } == 'fixture secret é'
		for index in 0 .. password.len { password[index] = 0 }
		println('Retiring the approved obsolete generation set…'); flush_stdout()
		// Credential submission closes stdin. Publish the separate release file
		// by rename so existence always exposes its complete contents.
		release := os.getenv('VINIX_SOFTWARE_CLEANUP_NAVIGATION_RELEASE')
		for _ in 0 .. 20000 { if os.is_file(release) { break }; time.sleep(time.millisecond) }
		assert os.read_file(release)! == 'release'
		if mode == 'apply-failed' { eprintln('Generation cleanup review is stale: eligible set changed. Reload and review again.'); exit(29) }
		os.write_file(os.getenv('VINIX_SOFTWARE_CLEANUP_RECEIPT'), 'reviewed generations only')!
		println('Obsolete generation cleanup completed.')
		return true
	}
	return false
}

fn wait_for_cleanup_navigation_output(mut app SoftwareApp) {
	mut minimum := 1
	if app.cleanup_review_running() {
		mut review := fixture_cleanup_navigation_review(os.exists(os.getenv('VINIX_SOFTWARE_CLEANUP_RECEIPT')))
		text := json2.encode(review)
		minimum = if os.getenv('VINIX_SOFTWARE_CLEANUP_NAVIGATION') == 'review-partial' { text.len / 2 } else { text.len }
		review.close(); unsafe { text.free() }
	}
	for _ in 0 .. 5000 {
		app.poll()
		if app.output.len >= minimum { return }
		time.sleep(time.millisecond)
	}
	assert false, 'cleanup fixture did not reach its output barrier: ${app.status}'
}

fn check_software_cleanup_navigation() ! {
	receipt := os.temp_dir() + '/vinix-cleanup-navigation-' + os.getpid().str()
	release := receipt + '.release'
	os.setenv('VINIX_SOFTWARE_CLEANUP_RECEIPT', receipt, true)
	os.setenv('VINIX_SOFTWARE_CLEANUP_NAVIGATION_RELEASE', release, true)
	defer {
		os.rm(receipt) or {}; os.rm(release) or {}; os.rm(release + '.pending') or {}
		os.unsetenv('VINIX_SOFTWARE_CLEANUP_RECEIPT'); os.unsetenv('VINIX_SOFTWARE_CLEANUP_NAVIGATION')
		os.unsetenv('VINIX_SOFTWARE_CLEANUP_NAVIGATION_RELEASE')
	}
	mut app := SoftwareApp{ administration_required: true, service_path: os.executable(),
		output: []u8{cap: 128 * 1024}, query: 'kept query'.bytes(), filter: 2, selected: 0,
		rows: [SoftwareRow{ id: 'editor', name: 'Editor', installed_version: '1.0.0' }] }
	defer { app.close_app() }
	app.handle('software.cleanup')!; wait_for_software(mut app)
	for ending in ['partial', 'complete']! {
		for action in ['software.cleanup.stop', 'software.cleanup.cancel', 'escape']! {
			os.setenv('VINIX_SOFTWARE_CLEANUP_NAVIGATION', 'review-' + ending, true)
			app.handle('software.cleanup.reload')!; pid := app.worker.pid
			wait_for_cleanup_navigation_output(mut app)
			assert app.cleanup_review_running() && !app.cleanup_ready && app.cleanup_snapshot.fingerprint == '' && app.prepare_close() && !app.admin_prompt
			for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
				tree := app.build(size)!
				assert tree.children.any(it.id == 'software.cleanup.stop') && tree.children.any(it.text == app.status)
				assert !tree.children.any(it.id in ['software.cleanup.confirm', 'software.cleanup.back', 'software.cleanup.reload'])
				free_window_tree(tree)
			}
			for event in ['software.cleanup.confirm', 'software.cleanup.back', 'software.cleanup.reload', 'software.cleanup.down', 'software.report.read']! { app.handle(event)! }
			assert !app.report_reader_mode && app.details_pages.len == 0 && app.details_compact_pages.len == 0
			app.paste_input('\x1b'); assert app.worker.pid == pid
			if action == 'escape' { app.key_input('\x1b') } else { app.handle(action)! }
			assert app.worker == unsafe { nil } && C.kill(pid, 0) != 0 && app.cleanup_worker == .none && !app.worker_view && !app.worker_review
			assert app.output.len == 0 && !app.output_truncated && !app.poll() && app.cleanup_mode && app.status.contains('stopped')
			assert !app.cleanup_ready && app.cleanup_snapshot.fingerprint == '' && app.cleanup_snapshot.generations.len == 0 && !os.exists(receipt)
			app.handle('software.cleanup.confirm')!; assert app.worker == unsafe { nil } && !app.admin_prompt
			compact := app.build(ui2.rect(0, 0, 320, 240))!
			assert compact.children.any(it.id == 'software.cleanup.back') && compact.children.any(it.id == 'software.cleanup.reload')
			free_window_tree(compact)
			os.unsetenv('VINIX_SOFTWARE_CLEANUP_NAVIGATION'); app.handle('software.cleanup.reload')!; wait_for_software(mut app)
			assert app.cleanup_ready && app.cleanup_snapshot.generations.len == 30
		}
	}
	// Admit a complete, maximum-sized proposal only after worker exit.
	os.setenv('VINIX_SOFTWARE_CLEANUP_NAVIGATION', 'review-complete', true)
	app.handle('software.cleanup.reload')!; wait_for_cleanup_navigation_output(mut app)
	assert !app.cleanup_ready && app.cleanup_snapshot.generations.len == 0
	app.worker.stdin_write('x'); wait_for_software(mut app)
	assert app.cleanup_ready && app.cleanup_snapshot.generations.len == 4096
	free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); app.handle('software.cleanup.down')!
	assert app.cleanup_scroll == 7
	for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 900, 900), ui2.rect(0, 0, 640, 610)]! {
		tree := app.build(size)!
		assert app.cleanup_scroll == 7
		if size.width >= 640 { assert tree.children.any(it.text == 'Remove generation 8') }
		else { assert !tree.children.any(it.id == 'software.cleanup.confirm') }
		free_window_tree(tree)
	}
	check_cleanup_report_content(&app); check_software_report_reader(mut app)!
	assert app.cleanup_scroll == 7 && app.cleanup_snapshot.generations.len == 4096
	os.setenv('VINIX_SOFTWARE_CLEANUP_NAVIGATION', 'apply-complete', true)
	app.handle('software.cleanup.confirm')!; assert app.admin_prompt
	app.stop_cleanup_review(); assert app.admin_prompt && app.worker != unsafe { nil }
	app.handle('software.admin.cancel')!
	assert !app.admin_prompt && app.worker == unsafe { nil } && !app.cleanup_ready && !os.exists(receipt)
	app.handle('software.cleanup.confirm')!; assert app.worker == unsafe { nil }
	for mode in ['apply-failed', 'apply-complete']! {
		os.unsetenv('VINIX_SOFTWARE_CLEANUP_NAVIGATION'); app.handle('software.cleanup.reload')!; wait_for_software(mut app)
		os.setenv('VINIX_SOFTWARE_CLEANUP_NAVIGATION', mode, true)
		app.handle('software.cleanup.confirm')!
		assert app.admin_prompt && app.worker.args == ['admin', 'cleanup-apply', 'd'.repeat(64)]
		app.key_input('fixture secret é'); app.handle('software.admin.approve')!
		wait_for_cleanup_navigation_output(mut app); pid := app.worker.pid
		assert !app.admin_prompt && !app.cleanup_review_running() && !app.prepare_close() && app.admin_password.all(it == 0)
		for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
			tree := app.build(size)!
			assert tree.children.any(it.text == app.status)
			assert !tree.children.any(it.id in ['software.cleanup.stop', 'software.cleanup.confirm', 'software.cleanup.back', 'software.cleanup.reload', 'software.failure'])
			free_window_tree(tree)
		}
		for event in ['software.cleanup.stop', 'software.cleanup.cancel', 'software.cleanup.back', 'software.cleanup.reload',
			'software.cleanup.confirm', 'software.cleanup.down', 'software.report.read', 'software.cancel', 'software.install']! { app.handle(event)! }
		assert !app.report_reader_mode && app.details_pages.len == 0 && app.details_compact_pages.len == 0
		app.key_input('\x1b'); app.stop_cleanup_review(); app.paste_input('must not edit')
		assert app.worker.pid == pid && C.kill(pid, 0) == 0 && app.cleanup_mode && !os.exists(receipt)
		if mode == 'apply-complete' { os.setenv('VINIX_SOFTWARE_CLEANUP_NAVIGATION', 'review-complete', true) }
		os.write_file(release + '.pending', 'release')!; os.rename(release + '.pending', release)!
		if mode == 'apply-complete' {
			for _ in 0 .. 5000 { app.poll(); if app.cleanup_worker == .review { break }; time.sleep(time.millisecond) }
			assert app.cleanup_worker == .review && !app.cleanup_ready && app.cleanup_result.contains('Cleanup finished')
			wait_for_cleanup_navigation_output(mut app); app.handle('software.cleanup.stop')!
			assert app.cleanup_result.contains('Cleanup finished') && !app.cleanup_ready && app.cleanup_snapshot.fingerprint == ''
			// A failed subsequent reload must not consume the completed result.
			os.setenv('VINIX_SOFTWARE_CLEANUP_NAVIGATION', 'review-failed', true)
			app.handle('software.cleanup.reload')!; wait_for_cleanup_navigation_output(mut app)
			app.worker.stdin_write('x'); wait_for_software(mut app)
			assert !app.cleanup_ready && app.cleanup_result.contains('Cleanup finished') && app.failure_pages.len > 0
			os.unsetenv('VINIX_SOFTWARE_CLEANUP_NAVIGATION'); app.handle('software.cleanup.reload')!
		}
		wait_for_software(mut app)
		if mode == 'apply-failed' {
			assert !app.cleanup_ready && app.cleanup_snapshot.fingerprint == '' && app.status.contains('stale') && app.failure_pages.len > 0
			compact := app.build(ui2.rect(0, 0, 320, 240))!
			assert compact.children.any(it.id == 'software.failure') && compact.children.any(it.id == 'software.cleanup.reload')
			free_window_tree(compact)
			app.handle('software.failure')!; app.key_input('\x1b'); assert !app.failure_mode && app.cleanup_mode
		} else {
			assert app.cleanup_ready && app.cleanup_snapshot.generations.len == 0 && app.cleanup_result == '' && app.status.contains('Cleanup finished')
			assert os.read_file(receipt)! == 'reviewed generations only'
			app.handle('software.cleanup.confirm')!; assert app.worker == unsafe { nil } && !app.admin_prompt
			app.handle('software.cleanup.reload')!; wait_for_software(mut app)
			assert app.cleanup_ready && !app.status.contains('Cleanup finished')
		}
		os.rm(release)!; os.unsetenv('VINIX_SOFTWARE_CLEANUP_NAVIGATION')
	}
	app.key_input('\x1b')
	assert !app.cleanup_mode && app.cleanup_snapshot.generations.len == 0 && app.cleanup_result == ''
	assert app.query.bytestr() == 'kept query' && app.filter == 2 && app.selected == 0
	println('Software cleanup navigation: partial and complete-before-exit Stop/Cancel/Escape, fresh review requirement, 4096-generation admission and stable resize anchor, compact diagnostics, approval cancellation, protected deletion, stopped/failed post-cleanup reload and retained result passed')
}

fn check_software_cleanup_navigation_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		mut review := fixture_cleanup_navigation_review(false); mut empty := fixture_cleanup_navigation_review(true)
		text := json2.encode(review); empty_text := json2.encode(empty)
		review.close(); empty.close()
		arguments := ['cleanup-apply']
		defer { unsafe { text.free(); empty_text.free(); (&array(&arguments)).free() } }
		mut app := SoftwareApp{ cleanup_mode: true, output: []u8{cap: 128 * 1024} }
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.cleanup_mode = true
				app.output.clear(); for byte in text { app.output << byte }; app.load_cleanup_review()
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); app.handle_cleanup('software.cleanup.down')
				anchor := app.cleanup_scroll
				free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!); free_window_tree(app.build(ui2.rect(0, 0, 900, 1200))!)
				assert app.cleanup_scroll == anchor
				report_reader_cycle(mut app)!; assert app.cleanup_scroll == anchor
				app.capture_failure(arguments, 29); app.progress_seen = true
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.progress_seen = false; app.clear_failure(); app.clear_cleanup_review()
				app.cleanup_result = 'Cleanup finished fixture result.'.clone()
				app.output.clear(); for byte in empty_text { app.output << byte }; app.load_cleanup_review()
				assert app.cleanup_ready && app.cleanup_result == '' && app.status.contains('Cleanup finished')
				report_reader_cycle(mut app)!
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.cleanup_key_input('\x1b'); assert !app.cleanup_mode
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'cleanup navigation retained ${kept} bytes'
		println('Software cleanup navigation: 1000 4096-generation/empty review/full/compact/resize/failure/progress/result/back/retirement cycles retain zero tracked bytes')
		println('Software cleanup reader: 1000 maximum/empty review/read/resize/back/retirement cycles retain zero tracked bytes')
	}
}
