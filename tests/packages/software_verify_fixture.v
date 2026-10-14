// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import tools.packages.pkgprotocol

fn software_verify_service_fixture(args []string) bool {
	if args.len != 2 || args[1] != 'verify' { return false }
	assert os.args[1..] == ['--progress', 'verify']
	mode := os.getenv('VINIX_SOFTWARE_VERIFY_MODE')
	first := pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'verify' }) + '\n'
	print(first[..8]); flush_stdout(); time.sleep(10 * time.millisecond); print(first[8..])
	println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'verify', package: 'editor', repository: 'trusted', path: 'bin/editor' }))
	flush_stdout()
	if mode == 'slow' { time.sleep(3 * time.second); return true }
	if mode == 'failed' { eprintln('editor: installed payload verification failed: bin/editor; use Repair / install'); exit(23) }
	if mode == 'incomplete' { return true }
	if mode == 'oversized' { println('uninteresting listing '.repeat(800)) }
	println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 }))
	if mode == 'trailing' { println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'verify', package: 'editor', path: 'bin/editor' })) }
	println('Installed package files and launchers verified.')
	if mode == 'late-failure' { eprintln('storage read failed after the completion frame'); exit(24) }
	return true
}

fn check_software_verify() ! {
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true,
		output: []u8{cap: 8192}, query: []u8{cap: 256}, selected: 0, filter: 1,
		catalog_error: 'catalog expired'.clone(), update_error: 'publisher revoked'.clone(),
		rows: [SoftwareRow{ id: 'editor', name: 'Editor', requested: true, installed_version: '1.0.0' }] }
	defer { os.unsetenv('VINIX_SOFTWARE_VERIFY_MODE'); app.close_app() }
	for mode in ['healthy', 'failed', 'incomplete', 'trailing', 'late-failure', 'oversized'] {
		os.setenv('VINIX_SOFTWARE_VERIFY_MODE', mode, true)
		tree := app.build(ui2.rect(0, 0, 640, 610))!
		assert tree.children.any(it.id == 'software.verify' && it.text == 'Verify installed')
		details := tree.children.filter(it.id == 'software.details')[0]
		verify := tree.children.filter(it.id == 'software.verify')[0]
		assert details.frame.x + details.frame.width <= verify.frame.x
		free_window_tree(tree)
		app.handle('software.verify')!
		assert app.worker_verify && app.worker.args == ['--progress', 'verify'] && !app.admin_prompt && app.prepare_close()
		pid := app.worker.pid; app.handle('software.verify')!; assert app.worker.pid == pid
		wait_for_software(mut app)
		assert app.worker == unsafe { nil } && app.rows.len == 1 && app.selected == 0 && app.filter == 1
		assert app.catalog_error == 'catalog expired' && app.update_error == 'publisher revoked'
		if mode in ['healthy', 'oversized'] {
			assert app.progress_seen && app.progress_snapshot.phase == 'complete'
			assert app.status.contains('files and launchers verified') && app.status.contains('policy still apply')
		} else {
			assert app.failure_pages.len > 0 && app.failure_heading.starts_with('Verify installed software')
			assert !app.status.contains('files and launchers verified')
			if mode in ['incomplete', 'trailing'] { assert app.worker_failed && app.failure_heading.contains('incomplete response') }
			if mode == 'failed' { assert app.status.contains('Repair / install') && app.failure_heading.contains('exit 23') }
			if mode == 'late-failure' { assert app.status.contains('storage read failed') }
			app.handle('software.failure')!; assert app.failure_mode
			app.handle('software.failure.back')!; assert !app.failure_mode
		}
	}
	app.begin_review('install', ['editor']); wait_for_software(mut app)
	assert app.review_ready
	review := app.build(ui2.rect(0, 0, 640, 610))!; assert !review.children.any(it.id == 'software.verify'); free_window_tree(review)
	app.handle('software.verify')!; assert app.worker == unsafe { nil } && app.review_ready
	app.handle('software.cancel')!
	os.setenv('VINIX_SOFTWARE_VERIFY_MODE', 'slow', true); app.handle('software.verify')!
	for _ in 0 .. 500 { app.poll(); if app.progress_seen { break }; time.sleep(time.millisecond) }
	assert app.worker != unsafe { nil } && app.progress_seen && app.status.contains('Verifying')
	pid := app.worker.pid; assert app.prepare_close(); app.close_app(); assert C.kill(pid, 0) != 0
	println('Software Verify: visible control, no administrator/catalog dependency, streamed progress, stable selection, incomplete/failure retention, review isolation and safe close PASS')
}
