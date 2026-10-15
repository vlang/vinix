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
	if mode == 'failed' { eprintln('editor: installed payload verification failed: bin/editor; use Repair installed or vinix-package repair'); exit(23) }
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
			if mode == 'failed' { assert app.status.contains('vinix-package repair') && app.failure_heading.contains('exit 23') }
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

fn check_software_repair() ! {
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true,
		query: []u8{cap: 256}, output: []u8{cap: 8192}, matching: [0], selected: 0, filter: 1,
		catalog_error: 'catalog expired'.clone(), rows: [SoftwareRow{ id: 'runtime', name: 'Runtime',
			installed_version: '1.0.0', kind: 'runtime', updatable: true, update_action: 'update' }] }
	defer { app.close_app() }
	tree := app.build(ui2.rect(0, 0, 640, 610))!
	assert tree.children.any(it.id == 'software.repair' && it.text == 'Repair installed')
	assert tree.children.any(it.id == 'software.install' && it.text == 'Review updates')
	assert tree.children.any(it.id == 'software.row.0')
	repair := tree.children.filter(it.id == 'software.repair')[0]
	for element in tree.children {
		if element.id.starts_with('software.row.') { assert element.frame.y + element.frame.height < repair.frame.y }
	}
	free_window_tree(tree)
	app.handle('software.repair')!
	assert app.worker_review && !app.admin_prompt && app.worker.args == ['review', 'repair'] && app.prepare_close()
	pid := app.worker.pid; app.handle('software.repair')!; assert app.worker.pid == pid
	wait_for_software(mut app)
	assert app.review_ready && app.review_snapshot.operation == 'repair' && app.review_snapshot.names.len == 0
	assert app.review_snapshot.rows.all(it.version == it.installed_version)
	assert app.status.contains('preserves installed versions')
	review := app.build(ui2.rect(0, 0, 640, 610))!
	assert review.children.any(it.id == 'software.row.1' && it.text == 'repair: Runtime')
	assert !review.children.any(it.id == 'software.repair' || it.id == 'software.install')
	free_window_tree(review)
	app.handle('software.details')!
	assert 'Package action: repair' in details_fixture_values(&app, 0)
	app.handle('software.repair')!; assert app.details_mode && app.worker == unsafe { nil }
	app.handle('software.details.back')!
	app.handle('software.repair')!; assert app.worker == unsafe { nil } && app.review_ready
	app.selected = -1
	app.handle('software.confirm')!
	assert app.admin_prompt && app.worker.args == ['admin', '--progress', 'apply', 'c'.repeat(64), 'repair']
	app.key_input('fixture secret é'); app.key_input('\r')
	assert !app.admin_prompt && app.admin_password.all(it == 0) && !app.prepare_close()
	wait_for_software(mut app)
	assert app.worker == unsafe { nil } && app.review == ''
	println('Software repair: installed dependency control, exact-version closure disclosure, read-only review, duplicate/modal isolation, frozen confirmation and reviewed administrator apply PASS')
}

fn check_software_repair_memory() ! {
	$if !track_heap ? { return error('compile repair memory fixture with -d track_heap') }
	$if track_heap ? {
		text := json2.encode(fixture_review('repair', []))
		mut app := SoftwareApp{ query: []u8{cap: 256}, output: text.bytes() }
		defer { app.close_app(); unsafe { text.free() } }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.review = 'repair'.clone()
				app.load_review()
				assert app.review_ready && app.review_snapshot.rows.all(it.version == it.installed_version)
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
				app.clear_review()
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end()
		assert kept == 0, 'repair reviews retained ${kept} bytes'
		println('Software repair: 1000 decode/disclose/render/cancel cycles retain zero tracked bytes PASS')
	}
}
