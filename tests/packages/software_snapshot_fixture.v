// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import tools.packages.pkgprotocol

const software_snapshot_fixture_path = '/private/tmp/部署 with spaces; $literal/organization-managed-installed-applications/recovery-records-with-complete-historical-metadata/requested-roots-and-transitive-runtime-data-dependencies/retained-versions-and-publisher-sequence-floors/installed applications and exact historical runtimes.json'
const software_media_fixture_source = '/media/发行 with spaces; $unexpanded'
const software_import_fixture_lock = '/home/test/local release lock.json'
const software_import_fixture_receipt = '/review/已签署 release; $literal.json'

fn software_snapshot_fixture_receipt(path string) pkgprotocol.DeploymentSnapshotSaved {
	return pkgprotocol.DeploymentSnapshotSaved{ generation: if path == '/empty-save.json' { u64(0) } else { u64(7) },
		architecture: if path == '/x86-save.json' { 'x86_64' } else { 'aarch64' }, destination: path,
		sha256: 'd'.repeat(64), roots: if path == '/empty-save.json' { u64(0) } else { u64(2) },
		packages: if path == '/empty-save.json' { u64(0) } else { u64(5) } }
}

fn software_snapshot_service_fixture(args []string) bool {
	if args.len < 3 || args[1] != '--json' { return false }
	if args[2] == 'deployment-media-save' { return software_media_save_service_fixture(args) }
	if args[2] != 'deployment-snapshot-save' { return false }
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

fn software_media_save_fixture_receipt(path string) pkgprotocol.DeploymentMediaSaved {
	return pkgprotocol.DeploymentMediaSaved{ architecture: 'x86_64', destination: path,
		sha256: 'c'.repeat(64), roots: 2, packages: 7 }
}

fn software_media_import_service_fixture() !bool {
	work := os.getenv('VINIX_SOFTWARE_MEDIA_IMPORT_FIXTURE')
	if work == '' { return false }
	mode := os.getenv('VINIX_SOFTWARE_MEDIA_IMPORT_MODE')
	args := os.args[1..]
	if args.len >= 3 && args[0] == 'admin' && args[1] == '--progress' && 'update-media' in args {
		if mode.starts_with('receipt-') {
			assert args == ['admin', '--progress', '--offline', 'update-media', software_media_fixture_source,
				software_import_fixture_receipt, 'a'.repeat(64)]
		} else { assert args == ['admin', '--progress', 'update-media', software_media_fixture_source] }
		mut credential := [2]u8{}
		for index in 0 .. credential.len { assert C.read(0, &credential[index], 1) == 1 }
		assert credential[1] == `\n`
		if credential[0] == `?` { eprintln('Fixture refused administrator approval.'); exit(21) }
		assert credential[0] == `!`
		os.write_file(work + '/approved', mode)!
		if mode == 'receipt-refused' { eprintln('offline repository index differs from the ISO package receipt'); exit(22) }
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{
			phase: 'verify', repository: 'trusted', path: 'index.json' }))
		if mode == 'incomplete' { return true }
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 }))
		flush_stdout()
		if mode == 'late' { eprintln('Fixture refused publication after the progress frame.'); exit(23) }
		if mode in ['hold', 'receipt-hold']! {
			for _ in 0 .. 5000 {
				if os.exists(work + '/release') { return true }
				time.sleep(time.millisecond)
			}
			return error('fixture import was not released')
		}
		return true
	}
	if args == ['--offline', 'view'] {
		os.write_file(work + '/catalog-read', mode)!
		if mode == 'bad-view' { println('incomplete catalog'); return true }
		println(json2.encode(SoftwareView{ format: 1, architecture: 'x86_64', offline: true, rows: [SoftwareRow{
			id: 'editor', name: 'Imported Editor', version: '1.0.0', description: 'Write text', kind: 'native',
			architecture: 'x86_64', repository: 'trusted', public_key: 'a'.repeat(64), license: 'MIT' }] }))
		return true
	}
	if args == ['--offline', '--json', 'deployment-media-save', software_media_fixture_source, software_import_fixture_lock] {
		println(json2.encode(software_media_save_fixture_receipt(software_import_fixture_lock)))
		return true
	}
	if args == ['--offline', 'deployment-add-review', software_import_fixture_lock, 'c'.repeat(64)] {
		review := fixture_review('deploy-add', ['editor'])
		println(json2.encode(pkgprotocol.Review{ ...review, fingerprint: 'e'.repeat(64) }))
		return true
	}
	if args == ['admin', '--progress', '--offline', 'deployment-add-apply', 'e'.repeat(64), software_import_fixture_lock, 'c'.repeat(64)] {
		mut intake := u8(0)
		if C.read(0, &intake, 1) == 1 { return error('fixture unexpectedly received apply approval') }
		return true
	}
	return false
}

fn check_software_media_import() ! {
	work := os.temp_dir() + '/vinix-software-media-import-' + os.getpid().str()
	os.mkdir(work)!
	os.setenv('VINIX_SOFTWARE_MEDIA_IMPORT_FIXTURE', work, true)
	defer {
		os.unsetenv('VINIX_SOFTWARE_MEDIA_IMPORT_FIXTURE')
		os.unsetenv('VINIX_SOFTWARE_MEDIA_IMPORT_MODE')
		os.rmdir_all(work) or {}
	}
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true,
		output: []u8{cap: 8192}, query: 'editor'.bytes() }
	defer { app.close_app() }
	app.handle('software.deployment')!
	app.handle('software.deployment.media-save')!
	wide := app.build(ui2.rect(0, 0, 640, 610))!
	assert wide.children.any(it.id == 'software.snapshot.import' && it.text == 'Import media')
	free_window_tree(wide)
	app.paste_input('relative'); app.handle('software.snapshot.import')!
	assert app.worker == unsafe { nil } && !app.admin_prompt && app.status.contains('absolute media directory')
	app.key_input('\x01'); app.paste_input(software_media_fixture_source)
	app.handle('software.snapshot.import')!
	assert app.admin_prompt && app.worker.args == ['admin', '--progress', 'update-media', software_media_fixture_source]
	app.key_input('!'); app.handle('software.admin.cancel')!
	assert app.worker == unsafe { nil } && app.repository_worker == .none && !app.offline_requested
	assert app.admin_password.all(it == 0) && !os.exists(work + '/approved')
	for mode in ['auth', 'incomplete', 'late']! {
		os.setenv('VINIX_SOFTWARE_MEDIA_IMPORT_MODE', mode, true)
		app.handle('software.snapshot.import')!
		app.key_input(if mode == 'auth' { '?' } else { '!' })
		app.handle('software.admin.approve')!
		wait_for_software(mut app)
		assert app.snapshot_mode && !app.snapshot_ready && app.snapshot_media_source == '' && !app.offline_requested
		assert app.failure_heading.contains('Import offline media') && !os.exists(work + '/catalog-read')
		assert editor_bytes_text(app.deployment_path) == software_media_fixture_source
		if mode == 'incomplete' { assert app.status.contains('without a complete result') }
		if mode == 'late' { assert app.status.contains('refused publication') }
		compact := app.build(ui2.rect(0, 0, 320, 240))!
		deployment_form_geometry(compact, 320, 240)
		assert compact.children.any(it.id == 'software.failure') && compact.children.any(it.id == 'software.snapshot.import')
		free_window_tree(compact)
	}
	os.setenv('VINIX_SOFTWARE_MEDIA_IMPORT_MODE', 'hold', true)
	app.handle('software.snapshot.import')!
	app.key_input('!'); app.handle('software.admin.approve')!
	assert !app.admin_prompt && app.admin_password.all(it == 0)
	for _ in 0 .. 5000 {
		app.poll()
		if app.progress_seen && app.progress_snapshot.phase == 'complete' { break }
		time.sleep(time.millisecond)
	}
	assert app.worker != unsafe { nil } && app.progress_snapshot.phase == 'complete'
	assert app.status.contains('waiting for the service to exit') && !app.offline_requested
	compact := app.build(ui2.rect(0, 0, 320, 240))!
	deployment_form_geometry(compact, 320, 240)
	assert compact.children.any(it.id == 'software.progress')
	assert !compact.children.any(it.id == 'software.snapshot.save' || it.id == 'software.snapshot.import' || it.id == 'software.snapshot.back')
	free_window_tree(compact)
	assert !app.prepare_close()
	app.handle('software.snapshot.back')!; app.handle('software.cancel')!; app.key_input('\x1b')
	app.handle('software.snapshot.save')!; app.handle('software.snapshot.import')!
	assert app.worker != unsafe { nil } && app.repository_worker == .media_import
	assert !os.exists(work + '/catalog-read')
	software_repository_text(mut app.deployment_path, '/retargeted-media')
	os.write_file(work + '/release', '')!
	wait_for_software(mut app)
	assert app.offline && app.offline_requested && app.repository_worker == .none && app.status.contains('Media imported'), app.status
	assert app.snapshot_mode && app.deployment_mode && app.snapshot_media_source == ''
	assert app.rows.len == 1 && app.rows[0].name == 'Imported Editor' && app.query.bytestr() == 'editor'
	assert os.read_file(work + '/catalog-read')! == 'hold'
	assert editor_bytes_text(app.deployment_path) == software_media_fixture_source
	app.handle('software.snapshot.save')!
	assert app.worker == unsafe { nil } && app.snapshot_media_source == software_media_fixture_source
	app.paste_input(software_import_fixture_lock); app.handle('software.snapshot.save')!
	assert app.worker.args == ['--offline', '--json', 'deployment-media-save', software_media_fixture_source, software_import_fixture_lock]
	wait_for_software(mut app)
	assert app.snapshot_ready && app.snapshot_media_saved.destination == software_import_fixture_lock
	app.handle('software.snapshot.review')!
	assert app.worker.args == ['--offline', 'deployment-add-review', software_import_fixture_lock, 'c'.repeat(64)]
	wait_for_software(mut app); assert app.review_ready && app.review == 'deploy-add' && !app.admin_prompt
	app.handle('software.confirm')!
	assert app.admin_prompt && app.worker.args == ['admin', '--progress', '--offline', 'deployment-add-apply',
		'e'.repeat(64), software_import_fixture_lock, 'c'.repeat(64)]
	app.handle('software.admin.cancel')!
	// A saved import remains available if the follow-up catalog read is bad.
	app.offline_requested = false
	os.setenv('VINIX_SOFTWARE_MEDIA_IMPORT_MODE', 'bad-view', true)
	app.handle('software.deployment.media-save')!; app.paste_input(software_media_fixture_source)
	app.handle('software.snapshot.import')!; app.key_input('!'); app.handle('software.admin.approve')!
	wait_for_software(mut app)
	assert app.status.contains('Media imported, but the offline catalog could not be reloaded')
	assert app.snapshot_mode && app.deployment_mode && app.offline_requested && app.repository_worker == .none
	assert app.rows.len == 1 && editor_bytes_text(app.deployment_path) == software_media_fixture_source
	println('Software media import: administrator approval and cancellation, literal frozen source, progress/exit guards, offline catalog reload, failure and offline save/review handoff PASS')
	check_software_media_receipt_import(mut app, work)!
}

fn check_software_media_receipt_import(mut app SoftwareApp, work string) ! {
	for name in ['approved', 'catalog-read', 'release']! { os.rm(work + '/' + name) or {} }
	app.handle('software.snapshot.back')!
	app.handle('software.deployment.media-save')!
	app.paste_input(software_media_fixture_source)
	compact := app.build(ui2.rect(0, 0, 320, 240))!
	deployment_form_geometry(compact, 320, 240)
	assert compact.children.any(it.id == 'software.snapshot.import-receipt' && it.text == 'Import with receipt…')
	free_window_tree(compact)
	app.handle('software.snapshot.import-receipt')!
	for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 640, 610)]! {
		tree := app.build(size)!
		deployment_form_geometry(tree, size.width, size.height)
		assert tree.children.any(it.id == 'software.snapshot.receipt-path') && tree.children.any(it.id == 'software.snapshot.sha256')
		assert !tree.children.any(it.id == 'software.snapshot.save' || it.id == 'software.deployment.path')
		free_window_tree(tree)
	}
	app.paste_input('relative.json'); app.handle('software.snapshot.import')!
	assert app.worker == unsafe { nil } && app.status.contains('absolute path to the ISO')
	app.key_input('\x01'); app.paste_input(software_import_fixture_receipt)
	app.key_input('\x01'); app.paste_input('/bad\nreceipt.json')
	assert editor_bytes_text(app.snapshot_receipt_path) == software_import_fixture_receipt
	app.key_input('\t'); app.paste_input('abc'); app.paste_input('A'); app.paste_input('a'.repeat(62))
	assert editor_bytes_text(app.snapshot_media_sha256) == 'abc'
	app.handle('software.snapshot.import')!
	assert app.worker == unsafe { nil } && app.status.contains('64 lowercase hex')
	digest := 'a'.repeat(64)
	app.key_input('\x01'); app.paste_input(digest)
	os.setenv('VINIX_SOFTWARE_MEDIA_IMPORT_MODE', 'receipt-refused', true)
	app.handle('software.snapshot.import')!
	assert app.admin_prompt && app.worker.args == ['admin', '--progress', '--offline', 'update-media',
		software_media_fixture_source, software_import_fixture_receipt, digest]
	app.handle('software.admin.cancel')!
	assert app.snapshot_receipt && app.worker == unsafe { nil } && !os.exists(work + '/approved')
	app.handle('software.snapshot.import')!
	app.key_input('!'); app.handle('software.admin.approve')!
	software_repository_text(mut app.deployment_path, '/retargeted-media')
	software_repository_text(mut app.snapshot_receipt_path, '/retargeted-receipt.json')
	software_repository_text(mut app.snapshot_media_sha256, 'b'.repeat(64))
	wait_for_software(mut app)
	assert app.snapshot_receipt && app.status.contains('index differs from the ISO package receipt')
	assert editor_bytes_text(app.deployment_path) == software_media_fixture_source
	assert editor_bytes_text(app.snapshot_receipt_path) == software_import_fixture_receipt
	assert editor_bytes_text(app.snapshot_media_sha256) == digest && !os.exists(work + '/catalog-read')
	os.setenv('VINIX_SOFTWARE_MEDIA_IMPORT_MODE', 'receipt-hold', true)
	app.handle('software.snapshot.import')!; app.key_input('!'); app.handle('software.admin.approve')!
	for _ in 0 .. 5000 {
		app.poll()
		if app.progress_seen && app.progress_snapshot.phase == 'complete' { break }
		time.sleep(time.millisecond)
	}
	assert app.worker != unsafe { nil } && app.progress_snapshot.phase == 'complete'
	busy := app.build(ui2.rect(0, 0, 320, 240))!
	deployment_form_geometry(busy, 320, 240)
	assert busy.children.any(it.id == 'software.progress') && !busy.children.any(it.id == 'software.snapshot.back')
	free_window_tree(busy)
	app.handle('software.snapshot.back')!; app.paste_input('/cannot-retarget')
	assert app.snapshot_receipt && !app.prepare_close() && !os.exists(work + '/catalog-read')
	os.write_file(work + '/release', '')!
	wait_for_software(mut app)
	assert !app.snapshot_receipt && app.snapshot_receipt_path.len == 0 && app.snapshot_media_sha256.len == 0
	assert app.snapshot_mode && app.status.contains('Media imported') && os.read_file(work + '/catalog-read')! == 'receipt-hold'
	assert editor_bytes_text(app.deployment_path) == software_media_fixture_source
	app.handle('software.snapshot.save')!
	assert app.snapshot_media_source == software_media_fixture_source && app.snapshot_media_sha256.len == 0
	println('Software receipt import: compact fields, literal authorization arguments, cancellation, refusal and exact offline handoff PASS')
}

fn software_media_save_service_fixture(args []string) bool {
	assert args.len >= 5 && os.args[1] == '--json' && args[3] == software_media_fixture_source
	assert args.len == 5 || (args.len == 6 && args[5] == 'c'.repeat(64))
	path := args[4]
	if path == '/existing-media-lock.json' { eprintln('destination exists'); exit(12) }
	if path == '/snapshot-receipt.json' { print(json2.encode(software_snapshot_fixture_receipt(path))); return true }
	if path == '/oversized-media-lock.json' { print('x'.repeat(32 * 1024 + 1)); return true }
	text := json2.encode(software_media_save_fixture_receipt(if path == '/wrong-media-lock.json' {
		'/different-lock.json'
	} else { path }))
	if path == '/wrong-media-digest.json' { print(text.replace('c'.repeat(64), 'a'.repeat(64))); return true }
	if path == '/partial-media-lock.json' { print(text[..text.len / 2]); return true }
	if path == '/failed-media-lock.json' { print(text); exit(24) }
	print(text[..17]); flush_stdout()
	time.sleep(time.millisecond)
	print(text[17..]); flush_stdout()
	if path == software_snapshot_fixture_path {
		mut release := u8(0)
		assert C.read(0, &release, 1) == 1
	}
	return true
}

fn check_software_media_save() ! {
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true,
		output: []u8{cap: 8192}, query: 'kept media search'.bytes(), selected: 5 }
	defer { app.close_app() }
	app.handle('software.deployment')!
	wide := app.build(ui2.rect(0, 0, 640, 610))!
	assert wide.children.any(it.id == 'software.deployment.media-save')
	free_window_tree(wide)
	free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
	deployment_form_select(mut app, 'software.deployment.media-save')!
	assert app.snapshot_mode && app.snapshot_media && app.focus
	source := app.build(ui2.rect(0, 0, 320, 240))!
	assert source.children.any(it.id == 'software.snapshot.import' && it.text == 'Import media')
	assert source.children.any(it.id == 'software.snapshot.save' && it.text == 'Save media lock')
	deployment_form_geometry(source, 320, 240)
	free_window_tree(source)
	app.paste_input('relative'); app.handle('software.snapshot.save')!
	assert app.worker == unsafe { nil } && app.snapshot_media_source == '' && app.status.contains('absolute media directory')
	app.key_input('\x01'); app.paste_input(software_media_fixture_source)
	app.handle('software.snapshot.save')!
	assert app.snapshot_media_source == software_media_fixture_source && app.deployment_path.len == 0 && app.focus
	app.handle('software.snapshot.save')!
	assert app.worker == unsafe { nil } && app.status.contains('absolute deployment file')
	app.paste_input(software_snapshot_fixture_path)
	save := app.build(ui2.rect(0, 0, 320, 240))!
	assert save.children.any(it.id == 'software.snapshot.save' && it.text == 'Save media lock')
	assert save.children.any(it.id == 'software.snapshot.sha256')
	deployment_form_geometry(save, 320, 240)
	free_window_tree(save)
	app.key_input('\t'); assert app.snapshot_sha256_focus
	app.paste_input('cc'); app.handle('software.snapshot.save')!
	assert app.worker == unsafe { nil } && app.status.contains('64 lowercase hex digits')
	app.key_input('\x01'); app.paste_input('C'.repeat(64)); app.paste_input('c'.repeat(65)); app.paste_input('cc\n')
	assert editor_bytes_text(app.snapshot_media_sha256) == 'cc' && app.select_all
	app.paste_input('c'.repeat(64))
	assert editor_bytes_text(app.deployment_path) == software_snapshot_fixture_path
	app.handle('software.snapshot.save')!
	assert app.worker_snapshot && !app.admin_prompt && !app.prepare_close()
	assert app.worker.args == ['--json', 'deployment-media-save', software_media_fixture_source, software_snapshot_fixture_path, 'c'.repeat(64)]
	for _ in 0 .. 300 {
		app.poll()
		if app.output.len > 0 && app.output.last() == `}` { break }
		time.sleep(time.millisecond)
	}
	assert app.output.len > 0 && app.output.last() == `}` && !app.snapshot_ready && !app.prepare_close()
	app.handle('software.snapshot.back')!; app.handle('software.snapshot.review')!; app.key_input('\x1b')
	assert app.snapshot_media && app.worker_snapshot && !app.snapshot_ready
	software_repository_text(mut app.deployment_path, '/changed-form.json')
	software_repository_text(mut app.snapshot_media_sha256, 'a'.repeat(64))
	assert C.write(app.worker.stdio_fd[0], c'x', 1) == 1
	wait_for_software(mut app)
	assert app.snapshot_ready && app.snapshot_media_saved.destination == software_snapshot_fixture_path
	assert app.snapshot_media_saved.roots == 2 && app.snapshot_media_saved.packages == 7
	check_software_report_reader(mut app)!
	compact := app.build(ui2.rect(0, 0, 320, 240))!
	assert compact.children.any(it.id == 'software.snapshot.review' && it.text == 'Review additions')
	assert compact.children.any(it.id == 'software.report.read')
	deployment_form_geometry(compact, 320, 240)
	free_window_tree(compact)
	app.handle('software.snapshot.export')!
	assert app.snapshot_media && !app.mirror_mode
	app.handle('software.snapshot.review')!
	assert !app.snapshot_mode && app.snapshot_media_source == '' && app.snapshot_media_saved.destination == ''
	assert app.worker.args == ['deployment-add-review', software_snapshot_fixture_path, 'c'.repeat(64)] && !app.admin_prompt
	wait_for_software(mut app)
	assert app.review_ready && app.review == 'deploy-add' && !app.admin_prompt && app.deployment_pending_sha256 == 'c'.repeat(64)
	app.handle('software.cancel')!
	for path in ['/match-audit.json', '/wrong-coverage-lock.json', '/wrong-media-digest.json', '/snapshot-receipt.json', '/wrong-media-lock.json', '/partial-media-lock.json',
		'/failed-media-lock.json', '/oversized-media-lock.json', '/existing-media-lock.json'] {
		app.handle('software.deployment.media-save')!
		app.paste_input(software_media_fixture_source); app.handle('software.snapshot.save')!
		app.paste_input(path)
		if path == '/wrong-media-digest.json' { app.handle('software.snapshot.sha256')!; app.paste_input('c'.repeat(64)) }
		app.handle('software.snapshot.save')!
		wait_for_software(mut app)
		if path in ['/match-audit.json', '/wrong-coverage-lock.json']! {
			assert app.snapshot_ready
			app.handle('software.snapshot.audit')!
			expected := ['--json', 'deployment-add-audit', path, 'c'.repeat(64)]
			assert app.audit_additions && app.worker.args == expected
			wait_for_software(mut app)
			if path == '/match-audit.json' {
				assert app.audit_ready && app.audit_snapshot.matches
				app.handle('software.audit.reload')!; assert app.worker.args == expected
				wait_for_software(mut app)
				app.handle('software.audit.review')!
				assert app.worker.args == ['deployment-add-review', path, 'c'.repeat(64)]
				wait_for_software(mut app); assert app.review_ready
				app.handle('software.cancel')!
			} else {
				assert !app.audit_ready && app.status.contains('different lock SHA-256')
				app.handle('software.audit.review')!; assert app.worker == unsafe { nil }
				app.handle('software.audit.back')!
			}
		} else {
			assert !app.snapshot_ready && app.failure_heading.contains('Save media lock')
			assert app.snapshot_media_saved.destination == '' && app.details_pages.len == 0
			if path == '/wrong-media-digest.json' { assert app.status.contains('different SHA-256') }
			app.handle('software.snapshot.review')!
			assert app.worker == unsafe { nil } && app.review == '' && !app.admin_prompt
			app.handle('software.snapshot.back')!
		}
	}
	assert app.query.bytestr() == 'kept media search' && app.selected == 5
	println('Software media lock: literal paths, compact and wide access, writer guard, strict receipt, additive review and coverage PASS')
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
	app.paste_input(''); assert app.focus && app.select_all && editor_bytes_text(app.deployment_path) == software_snapshot_fixture_path
	app.paste_input('x'.repeat(4097))
	assert app.select_all && editor_bytes_text(app.deployment_path) == software_snapshot_fixture_path
	app.key_input('\x1b')
	assert app.snapshot_mode && !app.focus && !app.select_all
	app.paste_input('\x1b'); app.paste_input('/ignored.json'); app.key_input('ignored')
	assert app.snapshot_mode && editor_bytes_text(app.deployment_path) == software_snapshot_fixture_path
	for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 640, 610)]! {
		tree := app.build(size)!
		assert tree.children.any(it.id == 'software.snapshot.back') && tree.children.any(it.text == app.status)
		assert tree.children.any(it.id == 'software.deployment.path')
		assert tree.children.any(it.id == 'software.snapshot.save')
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
		app.handle('software.report.read')!; assert !app.report_reader_mode
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
	check_software_media_save()!
	check_software_media_import()!
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
	check_software_report_reader(mut app)!
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
		check_software_report_reader(mut app)!
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
		media := json2.encode(software_media_save_fixture_receipt(software_snapshot_fixture_path))
		mut app := SoftwareApp{ deployment_mode: true, output: []u8{cap: 8192} }
		defer { app.close_app() }
		app.initialize_deployment_field()
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for i in 0 .. 2000 {
				media_mode := i % 2 == 1
				app.begin_deployment_snapshot_mode(media_mode)
				if media_mode {
					free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
					free_window_tree(app.build(ui2.rect(0, 0, 900, 660))!)
					app.paste_input(software_media_fixture_source)
					app.handle_deployment_snapshot('software.snapshot.import-receipt')
					app.paste_input(software_import_fixture_receipt)
					app.key_input('\t'); app.paste_input('abc')
					free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
					free_window_tree(app.build(ui2.rect(0, 0, 900, 660))!)
					app.handle_deployment_snapshot('software.snapshot.back')
					app.save_deployment_snapshot()
					app.handle_deployment_snapshot('software.snapshot.sha256')
					app.paste_input('abc')
					app.key_input('\x01'); app.paste_input('BAD\n'); app.key_input('\x7f')
					assert app.snapshot_media_sha256.len == 0
					app.handle_deployment_snapshot('software.deployment.path')
				}
				app.paste_input(software_snapshot_fixture_path); app.key_input('\x01')
				for input in ['\x1b', '\x01', '\x08', '\x7f', '\r', '\n', '/bad\xc2\x85path', '\xff']! {
					app.paste_input(input); assert app.focus && app.select_all && app.snapshot_mode
					assert editor_bytes_text(app.deployment_path) == software_snapshot_fixture_path
				}
				app.key_input('\x1b'); assert app.snapshot_mode && !app.focus && !app.select_all
				app.paste_input('\x1b'); assert app.snapshot_mode
				free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.snapshot_pending = software_snapshot_fixture_path.clone()
				app.output.clear(); for byte in if media_mode { media } else { text } { app.output << byte }
				assert app.load_deployment_snapshot()
				report_reader_cycle(mut app)!
				tree := app.build(ui2.rect(0, 0, 900, 660))!
				free_window_tree(tree)
				app.handle_deployment_snapshot('software.snapshot.next')
				page := app.details_page
				free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				assert app.details_page == page
				app.handle_deployment_snapshot('software.snapshot.previous')
				app.handle_deployment_snapshot('software.snapshot.back')
				// Invalid receipts also release any partially owned metadata.
				app.begin_deployment_snapshot_mode(media_mode)
				app.snapshot_pending = '/wrong.json'.clone()
				assert !app.load_deployment_snapshot()
				app.handle_deployment_snapshot('software.snapshot.back')
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'deployment save UI retained ${kept} bytes'
		println('Software deployment saving: 1000 installed and 1000 media paste/render/receipt/paging/mismatch/retirement cycles retain zero tracked bytes')
	}
}
