// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import ui2
import tools.packages.pkgprotocol

fn software_metadata_service_fixture(args []string) bool {
	if args[1] != 'review' { return false }
	mode := os.getenv('VINIX_SOFTWARE_METADATA_FIXTURE')
	defer { unsafe { mode.free() } }
	if mode == '' { return false }
	assert args[2..] == ['install', 'editor']
	text := json2.encode(fixture_review('install', ['editor']))
	defer { unsafe { text.free() } }
	println(match mode {
		'missing' { text.replace('"firmware":false,', '') }
		'duplicate' { text.replace('"firmware":false', '"firmware":true,"firm\\u0077are":false') }
		else { panic('unknown metadata fixture') }
	})
	return true
}

fn check_software_metadata() ! {
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true, output: []u8{cap: 8192} }
	defer { os.unsetenv('VINIX_SOFTWARE_METADATA_FIXTURE'); app.close_app() }
	for mode in ['missing', 'duplicate'] {
		os.setenv('VINIX_SOFTWARE_METADATA_FIXTURE', mode, true)
		app.begin_review('install', ['editor']); wait_for_software(mut app)
		assert !app.review_ready && app.review_snapshot.rows.len == 0 && app.review == ''
		assert app.status.contains('invalid package review') && app.worker == unsafe { nil } && !app.admin_prompt
		app.handle('software.confirm')!
		assert app.worker == unsafe { nil } && !app.admin_prompt
	}
	println('Software metadata review: missing firmware and escaped duplicate flags refuse confirmation before administrator approval')
}

fn metadata_fixture_output(mut app SoftwareApp, text string) {
	app.output.clear()
	for byte in text { app.output << byte }
}

fn metadata_fixture_review(mut app SoftwareApp, kind int, text string) {
	metadata_fixture_output(mut app, text)
	app.review = if kind == 0 { 'install'.clone() } else { 'mirror'.clone() }
	if kind < 2 { app.review_names = ['editor'.clone()] }
	if kind > 0 { app.mirror_pending = '/media/new export'.clone() }
	if kind == 2 { app.mirror_lock_pending = '/company/apps.json'.clone() }
	app.load_review()
}

fn check_software_metadata_memory() ! {
	$if !track_heap ? { return error('compile metadata memory fixture with -d track_heap') }
	$if track_heap ? {
		base := fixture_review('install', ['editor'])
		export := pkgprotocol.Review{ ...base, operation: 'mirror', generation: 0,
			rows: base.rows.map(pkgprotocol.ReviewPackage{ ...it, action: 'export' }) }
		mirror := pkgprotocol.MirrorReview{ format: 1, input_destination: '/media/new export', destination: '/media/new export', review: export }
		texts := [json2.encode(base), json2.encode(mirror), json2.encode(pkgprotocol.DeploymentMirrorReview{ format: 1,
			deployment: '/company/apps.json', deployment_sha256: 'd'.repeat(64), mirror: mirror })]
		mut invalid := []string{cap: 3}
		for text in texts { invalid << text.replace('"name":"Runtime"', '"name":"\\ud800"') }
		repository := pkgprotocol.RepositoryReview{ format: 1, architecture: 'aarch64', operation: 'enroll', id: 'fixture',
			url: 'https://example.invalid/' + 'long-é-'.repeat(32), public_key: 'b'.repeat(64), fingerprint: 'a'.repeat(64),
			index_sha256: 'c'.repeat(64), sequence: 7, expires: 2000000000, package_count: 1 }
		repository_text := json2.encode(repository)
		repository_invalid := repository_text.replace('"remembered_sequence":0', '"remembered_sequence":null')
		status := json2.encode(pkgprotocol.RepositoryStatus{ format: 1, architecture: 'aarch64', repositories: [pkgprotocol.Repository{
			id: repository.id, url: repository.url, public_key: repository.public_key }], history: [] })
		status_invalid := status.replace('"history":[]', '"history":[{"id":"partial"}]')
		mut app := SoftwareApp{ output: []u8{cap: 8192} }
		unsafe { app.output.flags |= .noslices }
		app.initialize_repository_fields()
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				for kind, text in texts {
					metadata_fixture_review(mut app, kind, text)
					assert app.review_ready
					free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
					app.clear_review()
					metadata_fixture_review(mut app, kind, invalid[kind])
					assert !app.review_ready && app.review_snapshot.rows.len == 0
				}
				metadata_fixture_output(mut app, status); app.load_repositories()
				metadata_fixture_output(mut app, status_invalid); app.load_repositories()
				assert app.repository_status.repositories.len == 1
				app.repository_status.close()
				app.repository_mode = true
				app.repository_operation = 'enroll'.clone()
				app.repository_pending = pkgprotocol.Repository{ id: repository.id.clone(), url: repository.url.clone(), public_key: repository.public_key.clone() }
				metadata_fixture_output(mut app, repository_text); app.load_repository_review()
				assert app.repository_review_ready
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
				app.clear_repository_review()
				app.repository_operation = 'enroll'.clone()
				app.repository_pending = pkgprotocol.Repository{ id: repository.id.clone(), url: repository.url.clone(), public_key: repository.public_key.clone() }
				metadata_fixture_output(mut app, repository_invalid); app.load_repository_review()
				assert !app.repository_review_ready
				app.repository_mode = false
			}
			unsafe { app.status.free() }; app.status = ''
		}
		kept := C.vinix_heap_end()
		app.close_app()
		assert kept == 0, 'Software metadata workflows retained ${kept} bytes'
		println('Software package/trust/offline metadata: 1000 valid/partial-invalid review, page/redraw/cancel/retire cycles retain zero tracked bytes')
	}
}
