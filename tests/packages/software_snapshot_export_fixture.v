// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import ui2
import tools.packages.pkgprotocol

fn software_snapshot_export_review(path string, changed bool) pkgprotocol.DeploymentMirrorReview {
	base := fixture_review('mirror', ['editor'])
	return pkgprotocol.DeploymentMirrorReview{ format: 1, deployment: path,
		deployment_sha256: if changed { 'e'.repeat(64) } else { 'd'.repeat(64) },
		mirror: pkgprotocol.MirrorReview{ format: 1, input_destination: mirror_fixture_destination,
			destination: mirror_fixture_destination, cache_needed: 1024, cache_available: 65536, shared_disk: true,
			review: pkgprotocol.Review{ ...base, generation: 0, fingerprint: 'd'.repeat(64),
				rows: base.rows.map(pkgprotocol.ReviewPackage{ ...it, version: '1.0.0', installed_version: '', action: 'export' }) } } }
}

fn check_software_snapshot_export() ! {
	receipt := os.temp_dir() + '/vinix-software-snapshot-export-' + os.getpid().str()
	os.setenv('VINIX_SOFTWARE_MIRROR_FIXTURE', receipt, true)
	defer { os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_MIRROR_FIXTURE') }
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true,
		output: []u8{cap: 8192}, query: []u8{cap: 256}, selected: -1, filter: 1 }
	defer { app.close_app() }
	app.query << 'kept search'.bytes()
	app.handle('software.deployment')!; app.handle('software.deployment.snapshot')!
	app.paste_input(software_snapshot_fixture_path); app.handle('software.snapshot.save')!
	app.handle('software.snapshot.export')!
	assert app.snapshot_mode && app.worker_snapshot && !app.mirror_mode
	wait_for_software(mut app)
	assert app.snapshot_ready && !app.admin_prompt
	assert app.build(ui2.rect(0, 0, 640, 610))!.children.any(it.id == 'software.snapshot.export')
	software_repository_text(mut app.deployment_path, '/wrong-form.json')
	app.initialize_mirror_field()
	software_repository_text(mut app.mirror_path, '/old-destination')
	app.handle('software.snapshot.export')!
	assert app.mirror_mode && app.mirror_locked && !app.mirror_all && !app.snapshot_mode && !app.deployment_mode
	assert app.mirror_source == software_snapshot_fixture_path && app.mirror_source_sha256 == 'd'.repeat(64)
	assert app.snapshot_pending == '' && app.snapshot_saved.destination == '' && app.details_pages.len == 0
	assert app.worker == unsafe { nil } && !app.review_ready && app.mirror_path.len == 0 && !os.exists(receipt)
	form := app.build(ui2.rect(0, 0, 640, 610))!
	assert !form.children.any(it.id == 'software.mirror.lock' || it.id == 'software.mirror.scope')
	app.handle('software.mirror.review')!
	assert app.worker == unsafe { nil } && app.status.contains('absolute new directory')
	app.handle('software.mirror.scope')!; assert app.mirror_locked && !app.mirror_all
	app.handle('software.mirror.lock')!; assert !app.mirror_lock_focus
	app.paste_input(mirror_fixture_destination)
	// The source editor storage cannot replace the captured receipt identity.
	software_repository_text(mut app.mirror_lock_path, '/wrong-source')
	for attempt in 0 .. 2 {
		app.handle('software.mirror.review')!
		assert app.worker.args == ['mirror-deployment-review', mirror_fixture_destination, software_snapshot_fixture_path]
		assert app.worker_review && app.prepare_close() && !app.admin_prompt
		app.handle('software.confirm')!; assert !os.exists(receipt)
		wait_for_software(mut app)
		assert app.review_ready && app.mirror_details && app.mirror_lock_sha256 == 'd'.repeat(64)
		assert app.review_names == ['editor'] && app.review_snapshot.rows.all(it.version == '1.0.0')
		mirror_reader_cycle(mut app, false)!
		app.handle('software.confirm')!; assert app.worker == unsafe { nil }
		app.handle('software.mirror.packages')!; assert app.mirror_details
		for app.mirror_seen + 1 < app.mirror_pages.len { app.handle('software.mirror.next')! }
		app.handle('software.mirror.packages')!; assert !app.mirror_details
		app.handle('software.row.1')!
		tree := app.build(ui2.rect(0, 0, 900, 660))!
		assert tree.children.any(it.text.contains('runtime-publisher'))
		assert tree.children.any(it.text.contains('Vendor-EULA (proprietary)') && it.text.contains('firmware'))
		assert tree.children.any(it.text.contains('Permissions: network, process'))
		if attempt == 0 {
			app.handle('software.cancel')!
			assert !app.review_ready && app.mirror_pages.len == 0 && app.mirror_lock_pending == ''
			assert app.mirror_source == software_snapshot_fixture_path && app.mirror_source_sha256 == 'd'.repeat(64)
		}
	}
	software_repository_text(mut app.mirror_path, '/changed-destination')
	software_repository_text(mut app.mirror_lock_path, '/changed-source')
	app.handle('software.confirm')!
	assert app.admin_prompt && app.worker_mirror && !os.exists(receipt)
	assert app.worker.args == ['admin', '--progress', 'mirror-deployment-apply', 'd'.repeat(64), mirror_fixture_destination, software_snapshot_fixture_path]
	app.paste_input('fixture secret é'); app.handle('software.admin.approve')!
	assert !app.admin_prompt && !app.prepare_close()
	wait_for_software(mut app)
	assert app.progress_seen && app.status.contains('/_deployment.json')
	assert json2.decode[[]string](os.read_file(receipt)!)! == ['d'.repeat(64), mirror_fixture_destination, software_snapshot_fixture_path]
	os.rm(receipt)!
	app.handle('software.mirror.back')!
	assert !app.mirror_mode && app.mirror_source == '' && app.mirror_source_sha256 == ''
	assert app.query.bytestr() == 'kept search' && app.selected == -1 && app.filter == 1
	// Changed bytes refuse before package confirmation; errors keep the pin so
	// retry cannot silently fall back to catalog resolution or a different lock.
	for path in ['/changed-saved-export.json', '/missing-lock', '/wrong-source'] {
		app.handle('software.deployment')!; app.handle('software.deployment.snapshot')!
		app.paste_input(path); app.handle('software.snapshot.save')!; wait_for_software(mut app)
		app.handle('software.snapshot.export')!; app.paste_input(mirror_fixture_destination)
		app.handle('software.mirror.review')!; wait_for_software(mut app)
		assert !app.review_ready && app.review == '' && app.mirror_pages.len == 0 && !os.exists(receipt)
		assert app.mirror_source == path && app.mirror_source_sha256 == 'd'.repeat(64)
		if path == '/changed-saved-export.json' { assert app.status.contains('file changed') && app.status.contains('new snapshot') }
		if path == '/missing-lock' { assert app.status.contains('unreadable') }
		app.handle('software.confirm')!; assert app.worker == unsafe { nil }
		app.handle('software.mirror')!
		assert app.mirror_source == '' && app.mirror_source_sha256 == ''
		assert app.build(ui2.rect(0, 0, 640, 610))!.children.any(it.id == 'software.mirror.scope')
		app.handle('software.mirror.back')!
	}
	app.handle('software.deployment')!; app.handle('software.deployment.snapshot')!
	app.paste_input('/empty-save.json'); app.handle('software.snapshot.save')!; wait_for_software(mut app)
	assert app.snapshot_ready && app.snapshot_saved.packages == 0
	assert !app.build(ui2.rect(0, 0, 640, 610))!.children.any(it.id == 'software.snapshot.export')
	app.handle('software.snapshot.export')!; assert app.snapshot_mode && !app.mirror_mode
	println('Software saved deployment export: frozen source/digest, explicit new destination, no catalog selection, full path/package/license review, administrator apply, progress, changed-source refusal, retry and retirement passed')
}

fn check_software_snapshot_export_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		good := json2.encode(software_snapshot_export_review(software_snapshot_fixture_path, false))
		changed := json2.encode(software_snapshot_export_review(software_snapshot_fixture_path, true))
		mut app := SoftwareApp{ output: []u8{cap: 8192} }
		app.initialize_mirror_field()
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				for mismatched in [false, true]! {
					app.snapshot_ready = true; app.snapshot_mode = true
					app.snapshot_pending = software_snapshot_fixture_path.clone()
					app.snapshot_saved = software_snapshot_fixture_receipt(software_snapshot_fixture_path)
					app.handle_deployment_snapshot('software.snapshot.export')
					app.review = 'mirror'.clone()
					app.mirror_pending = mirror_fixture_destination.clone()
					app.mirror_lock_pending = app.mirror_source.clone()
					app.output.clear()
					for byte in if mismatched { changed } else { good } { app.output << byte }
					app.load_review()
					assert app.review_ready != mismatched
					if !mismatched {
						mirror_reader_cycle(mut app, false)!
						free_window_tree(app.build(ui2.rect(0, 0, 900, 660))!)
						for app.mirror_seen + 1 < app.mirror_pages.len { app.handle_mirror('software.mirror.next') }
						app.handle_mirror('software.mirror.packages')
						free_window_tree(app.build(ui2.rect(0, 0, 900, 660))!)
						app.clear_review()
					}
					free_window_tree(app.build(ui2.rect(0, 0, 900, 660))!)
					app.handle_mirror('software.mirror.back')
				}
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'saved deployment export retained ${kept} bytes'
		println('Software saved deployment export: 1000 handoff, decode, path/package render, digest mismatch and retirement cycles retain zero tracked bytes')
		println('Software saved export reader: 1000 frozen-source/read/page/resize/ignored-publish/Back/cache-retirement cycles retain zero tracked bytes')
	}
}
