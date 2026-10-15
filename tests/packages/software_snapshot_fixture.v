// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import tools.packages.pkgprotocol

const software_snapshot_fixture_path = '/private/tmp/部署 with spaces; $literal/organization-managed-installed-applications/recovery-records-with-complete-historical-metadata/requested-roots-and-transitive-runtime-data-dependencies/retained-versions-and-publisher-sequence-floors/installed applications and exact historical runtimes.json'

fn software_snapshot_fixture_receipt(path string) pkgprotocol.DeploymentSnapshotSaved {
	return pkgprotocol.DeploymentSnapshotSaved{ generation: if path == '/empty-save.json' { u64(0) } else { u64(7) },
		architecture: if path == '/x86-save.json' { 'x86_64' } else { 'aarch64' }, destination: path,
		sha256: 'd'.repeat(64), roots: if path == '/empty-save.json' { u64(0) } else { u64(2) },
		packages: if path == '/empty-save.json' { u64(0) } else { u64(5) } }
}

fn software_snapshot_service_fixture(args []string) bool {
	if args.len < 3 || args[1] != '--json' || args[2] != 'deployment-snapshot-save' { return false }
	assert args.len == 4 && os.args[1] == '--json'
	path := args[3]
	if path == '/existing-save.json' { eprintln('destination already exists; existing file preserved'); exit(1) }
	if path == '/published-save.json' { eprintln('deployment snapshot saved, but the parent directory could not be flushed'); exit(1) }
	if path == '/silent-save.json' { exit(1) }
	if path == '/huge-save.json' { print('x'.repeat(32 * 1024 + 1)); return true }
	text := json2.encode(software_snapshot_fixture_receipt(if path == '/wrong-path-save.json' { '/different.json' } else { path }))
	if path == '/bad-save.json' { print(text.replace('"format":1', '"format":2')); return true }
	if path == '/partial-save.json' { print(text[..text.len / 2]); return true }
	if path == '/failed-save.json' { print(text); exit(23) }
	print(text[..17]); flush_stdout()
	if path == '/partial-barrier-save.json' {
		mut release := u8(0); assert C.read(0, &release, 1) == 1
	}
	time.sleep(if path == '/slow-save.json' { 80 * time.millisecond } else { time.millisecond })
	print(text[17..]); flush_stdout()
	if path in ['/complete-barrier-save.json', '/late-failed-save.json']! {
		mut release := u8(0); assert C.read(0, &release, 1) == 1
		if path == '/late-failed-save.json' { eprintln('Saved, but directory flush failed. Inspect the destination before retrying.'); exit(24) }
	}
	return true
}

fn check_software_snapshot_navigation() ! {
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true,
		output: []u8{cap: 8192}, query: 'kept query'.bytes(), selected: 5, filter: 1 }
	defer { app.close_app() }
	app.handle('software.deployment')!; app.handle('software.deployment.snapshot')!
	app.paste_input(software_snapshot_fixture_path); app.key_input('\x01')
	for input in ['\x1b', '\x01', '\x08', '\x7f', '\r', '\n', 'bad\x00path', '/bad\xc2\x85path', '\xff']! {
		app.paste_input(input)
		assert app.snapshot_mode && app.focus && app.select_all
		assert editor_bytes_text(app.deployment_path) == software_snapshot_fixture_path
		assert app.worker == unsafe { nil } && app.status.contains('field was kept intact')
	}
	app.paste_input('x'.repeat(4097))
	assert app.select_all && editor_bytes_text(app.deployment_path) == software_snapshot_fixture_path
	app.key_input('\x1b')
	assert app.snapshot_mode && !app.focus && !app.select_all
	app.paste_input('\x1b'); app.paste_input('/ignored.json'); app.key_input('ignored')
	assert app.snapshot_mode && editor_bytes_text(app.deployment_path) == software_snapshot_fixture_path
	for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 640, 610)]! {
		tree := app.build(size)!
		assert tree.children.any(it.id == 'software.snapshot.back') && tree.children.any(it.text == app.status)
		assert tree.children.any(it.id == 'software.deployment.path') == (size.width >= 640)
		assert editor_bytes_text(app.deployment_path) == software_snapshot_fixture_path && !app.focus
		free_window_tree(tree)
	}
	app.handle('software.deployment.path')!; app.key_input('\x01'); app.paste_input('/new é🚀; $literal.json')
	assert editor_bytes_text(app.deployment_path) == '/new é🚀; $literal.json' && !app.select_all
	app.key_input('\x7f'); assert editor_bytes_text(app.deployment_path) == '/new é🚀; $literal.jso'
	app.key_input('\r'); assert app.snapshot_mode && !app.focus
	app.key_input('\x1b'); assert !app.snapshot_mode && app.deployment_mode
	app.handle('software.deployment.snapshot')!; assert app.deployment_path.len == 0 && app.focus
	app.key_input('\x1b'); assert app.snapshot_mode && !app.focus
	app.key_input('\x1b'); assert !app.snapshot_mode
	for path in ['/partial-barrier-save.json', '/complete-barrier-save.json', '/late-failed-save.json']! {
		app.handle('software.deployment.snapshot')!; app.paste_input(path); app.handle('software.snapshot.save')!
		expected := json2.encode(software_snapshot_fixture_receipt(path))
		for _ in 0 .. 5000 {
			app.poll()
			if app.output.len == (if path == '/partial-barrier-save.json' { 17 } else { expected.len }) { break }
			time.sleep(time.millisecond)
		}
		assert app.worker != unsafe { nil } && app.worker.is_alive()
		assert app.output.len == (if path == '/partial-barrier-save.json' { 17 } else { expected.len })
		unsafe { expected.free() }
		pid := app.worker.pid
		assert app.worker_snapshot && app.worker_view && !app.snapshot_ready && app.details_pages.len == 0
		assert app.worker.args == ['--json', 'deployment-snapshot-save', path] && !app.admin_prompt
		assert !app.prepare_close()
		for event in ['software.snapshot.back', 'software.snapshot.another', 'software.snapshot.save', 'software.snapshot.audit',
			'software.snapshot.review', 'software.snapshot.export', 'software.deployment.path', 'software.deployment.stop',
			'software.cancel', 'software.verify.stop', 'software.failure']! { app.handle(event)! }
		for input in ['\x1b', '\r', '\x01', '\x08', '/changed.json']! { app.key_input(input); app.paste_input(input) }
		assert app.worker.pid == pid && app.worker.is_alive() && app.snapshot_mode && !app.snapshot_ready
		assert app.snapshot_pending == path && editor_bytes_text(app.deployment_path) == path && !app.focus && !app.select_all
		for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 900, 660)]! {
			tree := app.build(size)!
			assert tree.children.any(it.text == app.status)
			assert !tree.children.any(it.id in ['software.snapshot.back', 'software.snapshot.save', 'software.snapshot.audit', 'software.snapshot.review', 'software.snapshot.export', 'software.failure'])
			if size.width < 640 { assert tree.children.any(it.text == 'Wait for saving to finish.') }
			free_window_tree(tree)
		}
		app.worker.stdin_write('x'); wait_for_software(mut app)
		assert app.prepare_close() && !app.worker_snapshot
		if path == '/late-failed-save.json' {
			assert !app.snapshot_ready && app.details_pages.len == 0 && app.failure_pages.len > 0
			assert app.status.contains('Inspect the destination')
			compact := app.build(ui2.rect(0, 0, 320, 240))!
			assert compact.children.any(it.id == 'software.failure') && compact.children.any(it.text == app.status)
			for element in compact.children { assert element.frame.y + element.frame.height <= 240 }
			free_window_tree(compact)
			app.handle('software.failure')!; app.key_input('\x1b'); assert app.snapshot_mode && !app.failure_mode
		} else {
			assert app.snapshot_ready && app.snapshot_saved.destination == path
			app.handle('software.snapshot.next')!; page := app.details_page
			app.paste_input('\x1b'); app.paste_input('/must-not-edit.json')
			assert app.snapshot_mode && app.snapshot_saved.destination == path
			compact := app.build(ui2.rect(0, 0, 320, 240))!
			assert compact.children.any(it.id == 'software.snapshot.back') && compact.children.any(it.text == app.status)
			assert !compact.children.any(it.id == 'software.snapshot.review' || it.id == 'software.snapshot.export')
			free_window_tree(compact)
			full := app.build(ui2.rect(0, 0, 900, 660))!; free_window_tree(full)
			assert app.details_page == page && app.snapshot_pending == path
		}
		app.key_input('\x1b'); assert !app.snapshot_mode && app.deployment_mode
	}
	assert app.query.bytestr() == 'kept query' && app.selected == 5 && app.filter == 1
	println('Software save navigation: literal paste/control refusal, focus-first Escape, full/compact status/failure, frozen receipt paging, partial/complete-before-exit writer guards and late failure PASS')
}

fn check_software_snapshot() ! {
	check_software_snapshot_navigation()!
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true,
		output: []u8{cap: 8192}, query: []u8{cap: 256}, selected: 5, filter: 1 }
	defer { app.close_app() }
	app.query << 'kept search'.bytes()
	app.handle('software.deployment')!
	form := app.build(ui2.rect(0, 0, 640, 610))!
	assert form.children.any(it.id == 'software.deployment.snapshot')
	software_repository_text(mut app.deployment_path, '/existing-lock.json')
	app.handle('software.deployment.snapshot')!
	assert app.snapshot_mode && app.deployment_path.len == 0 && app.focus
	app.handle('software.snapshot.save')!
	assert app.worker == unsafe { nil } && app.status.contains('absolute')
	app.paste_input(software_snapshot_fixture_path)
	app.paste_input('\n'); assert editor_bytes_text(app.deployment_path) == software_snapshot_fixture_path
	app.handle('software.deployment.path')!
	app.paste_input('bad\x00path'); assert editor_bytes_text(app.deployment_path) == software_snapshot_fixture_path
	app.key_input('\x01'); app.paste_input('x'.repeat(4097))
	assert editor_bytes_text(app.deployment_path) == software_snapshot_fixture_path
	app.handle('software.snapshot.save')!
	assert app.worker_snapshot && !app.prepare_close() && !app.admin_prompt
	assert app.worker.args == ['--json', 'deployment-snapshot-save', software_snapshot_fixture_path]
	app.handle('software.snapshot.back')!; app.key_input('\x1b')
	app.handle('software.snapshot.audit')!; app.handle('software.snapshot.save')!
	assert app.snapshot_mode && !app.snapshot_ready && app.worker_snapshot
	software_repository_text(mut app.deployment_path, '/changed-form.json')
	wait_for_software(mut app)
	assert app.snapshot_ready && app.snapshot_saved.destination == software_snapshot_fixture_path
	assert app.snapshot_saved.generation == 7 && app.snapshot_saved.roots == 2 && app.snapshot_saved.packages == 5
	assert app.prepare_close() && app.failure_pages.len == 0
	facts := app.details_pages.map(it.text).join('\n').replace('\n  ', '')
	assert facts.contains(software_snapshot_fixture_path) && facts.contains('d'.repeat(64)) && facts.contains('Installed generation: 7')
	assert facts.contains('Requested applications: 2') && facts.contains('Packages including runtimes: 5')
	wide := app.build(ui2.rect(0, 0, 900, 660))!
	assert wide.children.any(it.id == 'software.snapshot.audit') && wide.children.any(it.id == 'software.snapshot.review')
	app.handle('software.snapshot.next')!; assert app.details_page == 1
	app.handle('software.snapshot.previous')!; assert app.details_page == 0
	app.handle('software.snapshot.audit')!
	assert !app.snapshot_mode && !app.snapshot_ready && app.snapshot_pending == '' && app.snapshot_saved.destination == ''
	assert app.audit_mode && app.worker.args == ['--json', 'deployment-audit', software_snapshot_fixture_path]
	wait_for_software(mut app)
	app.handle('software.audit.back')!
	// Both supported architectures and an empty installed generation are valid.
	for path in ['/x86-save.json', '/empty-save.json'] {
		app.handle('software.deployment.snapshot')!
		app.paste_input(path); app.handle('software.snapshot.save')!; wait_for_software(mut app)
		assert app.snapshot_ready
		if path == '/empty-save.json' { assert app.snapshot_saved.packages == 0 && app.snapshot_saved.generation == 0 }
		else { assert app.snapshot_saved.architecture == 'x86_64' }
		if path == '/x86-save.json' {
			software_repository_text(mut app.deployment_path, '/changed-again.json')
			app.handle('software.snapshot.review')!
			assert !app.snapshot_mode && app.deployment_pending == path && app.worker.args == ['deployment-review', path]
			assert !app.admin_prompt
			wait_for_software(mut app); assert app.review_ready
			app.handle('software.cancel')!
		} else {
			app.handle('software.snapshot.another')!
			assert !app.snapshot_ready && app.snapshot_pending == '' && app.deployment_path.len == 0 && app.details_pages.len == 0
			app.handle('software.snapshot.back')!
		}
	}
	for path in ['/bad-save.json', '/partial-save.json', '/wrong-path-save.json', '/failed-save.json', '/huge-save.json', '/existing-save.json', '/published-save.json', '/silent-save.json'] {
		app.handle('software.deployment.snapshot')!; app.paste_input(path)
		app.handle('software.snapshot.save')!; wait_for_software(mut app)
		assert !app.snapshot_ready && app.snapshot_saved.destination == '' && app.details_pages.len == 0
		assert app.failure_pages.len > 0 && app.failure_heading.contains('Save installed deployment')
		if path == '/published-save.json' { assert app.status.contains('saved, but') && app.status.contains('flushed') }
		if path == '/existing-save.json' { assert app.status.contains('preserved') }
		if path in ['/partial-save.json', '/wrong-path-save.json', '/silent-save.json', '/huge-save.json'] { assert app.status.contains('may exist') }
		app.handle('software.snapshot.review')!; assert app.review == '' && app.worker == unsafe { nil }
		app.handle('software.failure')!; assert app.failure_mode
		app.key_input('\x1b'); assert !app.failure_mode && app.snapshot_mode
		compact := app.build(ui2.rect(0, 0, 480, 340))!
		assert compact.children.any(it.id == 'software.snapshot.back') && compact.children.any(it.id == 'software.failure')
		app.key_input('\x1b'); assert !app.snapshot_mode && app.deployment_mode && app.snapshot_pending == ''
	}
	app.handle('software.deployment.snapshot')!; app.paste_input('/slow-save.json')
	app.handle('software.snapshot.save')!
	for _ in 0 .. 50 { app.poll(); if app.output.len > 0 { break }; time.sleep(time.millisecond) }
	assert app.worker != unsafe { nil } && !app.snapshot_ready && !app.prepare_close()
	compact := app.build(ui2.rect(0, 0, 480, 340))!
	assert !compact.children.any(it.id == 'software.snapshot.back' || it.id == 'software.snapshot.save')
	app.handle('software.snapshot.back')!; app.handle('software.deployment.back')!
	app.paste_input('/must-not-edit.json')
	assert app.snapshot_mode && editor_bytes_text(app.deployment_path) == '/slow-save.json'
	wait_for_software(mut app); assert app.snapshot_ready
	app.handle('software.snapshot.back')!
	assert app.query.bytestr() == 'kept search' && app.selected == 5 && app.filter == 1
	println('Software deployment saving: literal ordinary argv, bounded complete receipt, destination binding, both architectures, empty generation, close guard, fresh audit/review, diagnostics and compact navigation passed')
}

fn check_software_snapshot_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		text := json2.encode(software_snapshot_fixture_receipt(software_snapshot_fixture_path))
		mut app := SoftwareApp{ deployment_mode: true, output: []u8{cap: 8192} }
		defer { app.close_app() }
		app.initialize_deployment_field()
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.begin_deployment_snapshot()
				app.paste_input(software_snapshot_fixture_path); app.key_input('\x01')
				for input in ['\x1b', '\x01', '\x08', '\x7f', '\r', '\n', '/bad\xc2\x85path', '\xff']! {
					app.paste_input(input); assert app.focus && app.select_all && app.snapshot_mode
					assert editor_bytes_text(app.deployment_path) == software_snapshot_fixture_path
				}
				app.key_input('\x1b'); assert app.snapshot_mode && !app.focus && !app.select_all
				app.paste_input('\x1b'); assert app.snapshot_mode
				free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.snapshot_pending = software_snapshot_fixture_path.clone()
				app.output.clear(); for byte in text { app.output << byte }
				assert app.load_deployment_snapshot()
				tree := app.build(ui2.rect(0, 0, 900, 660))!
				free_window_tree(tree)
				app.handle_deployment_snapshot('software.snapshot.next')
				page := app.details_page
				free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				assert app.details_page == page
				app.handle_deployment_snapshot('software.snapshot.previous')
				app.handle_deployment_snapshot('software.snapshot.back')
				// Invalid receipts also release any partially owned metadata.
				app.begin_deployment_snapshot()
				app.snapshot_pending = '/wrong.json'.clone()
				assert !app.load_deployment_snapshot()
				app.handle_deployment_snapshot('software.snapshot.back')
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'deployment save UI retained ${kept} bytes'
		println('Software deployment saving: 1000 literal paste/control refusal/blur/full/compact/receipt/paging/mismatch/retirement cycles retain zero tracked bytes')
	}
}
