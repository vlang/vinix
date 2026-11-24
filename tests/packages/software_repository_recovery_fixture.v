// SPDX-License-Identifier: GPL-2.0-or-later
// Production-safe checks staged beside the actual Software implementation.
module main

import json2
import os
import time
import ui2
import tools.packages.pkgprotocol

fn C.vinix_heap_count() u32

const repository_recovery_url = 'file:///private/tmp/部署 repository; $literal é'
const repository_recovery_key = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

fn repository_recovery_require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn repository_recovery_configuration(id string) pkgprotocol.RepositoryConfiguration {
	return pkgprotocol.RepositoryConfiguration{ format: 1, scope: 'configuration', architecture: 'aarch64',
		repositories: [pkgprotocol.Repository{ id: id, url: repository_recovery_url, public_key: repository_recovery_key }] }
}

fn repository_recovery_fingerprint(id string) string {
	return pkgprotocol.repository_refresh_fingerprint(pkgprotocol.Repository{
		id: id, url: repository_recovery_url, public_key: repository_recovery_key
	})
}

fn repository_recovery_approve_child() ! {
	mut password := [2]u8{}
	repository_recovery_require(C.read(0, unsafe { &password[0] }, password.len) == password.len
		&& password[0] == `x` && password[1] == `\n`, 'administrator child did not receive fixture approval')!
}

fn repository_enrollment_refresh_service(args []string, mode string) ! {
	intent := ['enroll', 'draft', repository_recovery_url, repository_recovery_key]
	if args == ['--offline', 'repo-review', ...intent] {
		println(json2.encode(pkgprotocol.RepositoryReview{ format: 1, architecture: 'aarch64',
			operation: 'enroll', id: 'draft', url: repository_recovery_url, public_key: repository_recovery_key,
			fingerprint: 'd'.repeat(64), index_sha256: 'c'.repeat(64), sequence: 7,
			expires: 2000000000, package_count: 3 }))
		return
	}
	if args == ['admin', '--offline', 'repo-apply', 'd'.repeat(64), ...intent] {
		repository_recovery_approve_child()!
		println('fixture: trust saved')
		return
	}
	if args == ['admin', '--progress', '--offline', 'update', 'draft', repository_recovery_fingerprint('draft')] {
		repository_recovery_approve_child()!
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 }))
		if mode == 'enrollment-refresh-failed' {
			eprintln('remote: no authenticated cached index; run update')
			exit(23)
		}
		return
	}
	if args == ['--offline', '--json', 'repo-config'] {
		configuration := repository_recovery_configuration('draft')
		remote := pkgprotocol.Repository{ id: 'remote', url: 'https://publisher.example/current',
			public_key: repository_recovery_key }
		println(json2.encode(pkgprotocol.RepositoryConfiguration{ ...configuration,
			repositories: [remote, ...configuration.repositories] }))
		return
	}
	return error('unexpected enrollment or refresh argv: ' + args.join(' '))
}

// Private deterministic replies do not represent publisher authority.
// Explicit checks and all I/O remain active with -prod.
fn repository_recovery_service(args []string) !bool {
	mode := os.getenv('VINIX_SOFTWARE_REPOSITORY_RECOVERY')
	if mode == '' || args.len < 2 { return false }
	if mode.starts_with('enrollment-refresh-') {
		repository_enrollment_refresh_service(args[1..], mode)!
		return true
	}
	if mode == 'targeted-approved' {
		repository_recovery_require(args[1..] == ['admin', '--progress', '--offline', 'update', 'field', repository_recovery_fingerprint('field')],
			'wrong administrator refresh arguments')!
		repository_recovery_approve_child()!
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 }))
		return true
	}
	if mode == 'targeted-failed' {
		repository_recovery_require(args[1..] == ['--progress', 'update', 'field', repository_recovery_fingerprint('field')],
			'wrong direct refresh arguments')!
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 }))
		flush_stdout()
		mut release := u8(0)
		repository_recovery_require(C.read(0, unsafe { &release }, 1) == 1 && release == `x`, 'targeted writer barrier was not released')!
		eprintln('remote: no authenticated cached index; run update')
		exit(23)
	}
	if args[1] == 'repo-review' {
		repository_recovery_require(args.len >= 3 && args[2] in ['enroll', 'revoke']!, 'unexpected trust review operation')!
		enroll := args[2] == 'enroll'
		expected := if enroll { [args[0], 'repo-review', 'enroll', 'draft', repository_recovery_url, repository_recovery_key] }
			else { [args[0], 'repo-review', 'revoke', 'draft'] }
		repository_recovery_require(args == expected, 'review child received different literal repository fields')!
		println(json2.encode(pkgprotocol.RepositoryReview{ format: 1, architecture: 'aarch64', operation: args[2],
			id: 'draft', url: repository_recovery_url, public_key: repository_recovery_key,
			previous_url: if enroll { '' } else { repository_recovery_url },
			previous_public_key: if enroll { '' } else { repository_recovery_key }, fingerprint: 'd'.repeat(64),
			index_sha256: if enroll { 'c'.repeat(64) } else { '' }, sequence: if enroll { u64(7) } else { u64(0) },
			expires: if enroll { i64(2000000000) } else { i64(0) }, package_count: if enroll { 3 } else { 0 } }))
		return true
	}
	if args[1] == 'repo-apply' || args[1] == '--progress' {
		if args[1] == 'repo-apply' {
			repository_recovery_require(args.len >= 4, 'short apply argv')!
			expected := if args[3] == 'enroll' {
				[args[0], 'repo-apply', 'd'.repeat(64), 'enroll', 'draft', repository_recovery_url, repository_recovery_key]
			} else { [args[0], 'repo-apply', 'd'.repeat(64), 'revoke', 'draft'] }
			repository_recovery_require(args == expected, 'protected apply child received unexpected argv')!
		} else { repository_recovery_require(args == [args[0], '--progress', 'update'], 'unexpected refresh argv')! }
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'stage', current: 1, total: 2 }))
		flush_stdout()
		mut release := u8(0)
		repository_recovery_require(C.read(0, unsafe { &release }, 1) == 1 && release == `x`, 'protected writer barrier was not released')!
		eprintln('fixture: repository writer stopped after protection checks'); exit(23)
	}
	repository_recovery_require(args == [args[0], '--json', 'repo-config'], 'list child received unexpected argv')!
	text := json2.encode(repository_recovery_configuration('replacement'))
	defer { unsafe { text.free() } }
	if mode == 'invalid' { print('{"format":1}'); return true }
	if mode == 'failed' { eprintln('fixture: configured repositories are temporarily unavailable'); exit(23) }
	repository_recovery_require(mode in ['partial', 'complete', 'success']!, 'unknown repository recovery child mode')!
	if mode == 'success' { print(text); return true }
	length := if mode == 'partial' { 17 } else { text.len }
	print(text[..length]); flush_stdout()
	mut release := u8(0)
	repository_recovery_require(C.read(0, unsafe { &release }, 1) == 1 && release == `x`, 'repository list barrier was not released')!
	if mode == 'partial' { print(text[length..]) }
	return true
}

fn repository_recovery_element(tree ui2.Element, id string) !ui2.Element {
	for child in tree.children { if child.id == id { return child } }
	return error('repository recovery element is absent: ' + id)
}

fn repository_recovery_check_frames(tree ui2.Element, size ui2.Rect) ! {
	for index, child in tree.children {
		frame := child.frame
		repository_recovery_require(frame.x >= 0 && frame.y >= 0 && frame.width > 0 && frame.height > 0
			&& frame.x + frame.width <= size.width && frame.y + frame.height <= size.height,
			'repository recovery element leaves canvas: ' + child.id)!
		for other in tree.children[index + 1..] {
			repository_recovery_require(frame.x + frame.width <= other.frame.x || other.frame.x + other.frame.width <= frame.x
				|| frame.y + frame.height <= other.frame.y || other.frame.y + other.frame.height <= frame.y,
				'repository recovery elements overlap: ' + child.id + '/' + other.id)!
		}
	}
}

fn repository_recovery_geometry(mut app SoftwareApp, state string) ! {
	for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 400, 300), ui2.rect(0, 0, 180, 96),
		ui2.rect(0, 0, 180, 129), ui2.rect(0, 0, 180, 130), ui2.rect(0, 0, 180, 167),
		ui2.rect(0, 0, 180, 168), ui2.rect(0, 0, 180, 220), ui2.rect(0, 0, 319, 239)]! {
		tree := app.build(size)!
		defer { free_window_tree(tree) }
		repository_recovery_check_frames(tree, size)!
		repository_recovery_require(tree.children.any(it.text == app.status), 'compact repositories omit status')!
		repository_recovery_require(!tree.children.any(it.id == 'software.repository.confirm'), 'compact repositories expose trust confirmation')!
		mut next_y := 84
		for child in tree.children {
			if child.id in ['software.report.read', 'software.repository.reload', 'software.failure', 'software.repository.browse']! { next_y += 38 }
		}
		repository_recovery_require(tree.children.any(it.id == 'software.progress')
			== (app.progress_seen && size.height >= 240 && next_y <= size.height - 110),
			'compact repository progress is absent or overlaps action rows')!
		repository_recovery_require(tree.children.any(it.id == 'software.repository.browse')
			== (size.height >= 220 && app.repository_browsable()), 'compact repository browser has the wrong availability')!
		if state in ['stopped', 'failed', 'invalid', 'ready']! {
			_ := repository_recovery_element(tree, 'software.repository.back')!
			repository_recovery_require(tree.children.any(it.id == 'software.repository.reload') == (size.height >= 130),
				'compact repository reload does not follow its minimum height')!
			if size.height >= 130 {
				button := repository_recovery_element(tree, 'software.repository.reload')!
				repository_recovery_require(button.text == 'Reload list' && button.frame.y == 84,
					'compact repository reload has the wrong label or position')!
			}
		} else {
			repository_recovery_require(!tree.children.any(it.id == 'software.repository.reload'),
				'compact repositories expose reload during an operation')!
		}
		if state == 'active' { _ := repository_recovery_element(tree, 'software.repository.stop')! }
		if state == 'review' {
			_ := repository_recovery_element(tree, 'software.repository.cancel')!
			repository_recovery_require(tree.children.any(it.id == 'software.report.read') == (size.height >= 220),
				'compact repository review lost its reader')!
		}
		if state == 'failed' {
			repository_recovery_require(tree.children.any(it.id == 'software.failure') == (size.height >= 168),
				'compact repository failure diagnostics have the wrong minimum height')!
		}
		if state == 'writer' {
			repository_recovery_require(!tree.children.any(it.id in ['software.repository.stop', 'software.repository.cancel',
				'software.repository.back', 'software.report.read']!), 'compact repository writer exposes navigation')!
		}
	}
}

fn repository_recovery_wait(mut app SoftwareApp, expected_output int) ! {
	for _ in 0 .. 5000 {
		app.poll()
		if expected_output > 0 && app.output.len == expected_output && app.worker != unsafe { nil } { return }
		if expected_output == 0 && app.worker == unsafe { nil } { return }
		time.sleep(time.millisecond)
	}
	return error('repository recovery child did not reach expected state')
}

fn repository_recovery_activate(mut app SoftwareApp, id string, width int, height int) ! {
	tree := app.build(ui2.rect(0, 0, width, height))!
	defer { free_window_tree(tree) }
	button := repository_recovery_element(tree, id)!
	app.handle(button.id)!
}

fn repository_recovery_drafts(app &SoftwareApp) ! {
	repository_recovery_require(editor_bytes_text(app.repository_id) == 'draft'
		&& editor_bytes_text(app.repository_url) == repository_recovery_url
		&& editor_bytes_text(app.repository_key) == repository_recovery_key, 'repository read changed literal draft fields')!
}

fn repository_recovery_functional() ! {
	defer { os.unsetenv('VINIX_SOFTWARE_REPOSITORY_RECOVERY') }
	complete := json2.encode(repository_recovery_configuration('replacement'))
	previous := json2.encode(repository_recovery_configuration('previous'))
	defer { unsafe { complete.free(); previous.free() } }
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true, repository_mode: true,
		output: []u8{cap: 8192}, query: 'kept query'.bytes(), selected: 5, filter: 1 }
	defer { app.close_app() }
	app.initialize_repository_fields()
	software_repository_text(mut app.repository_id, 'draft')
	software_repository_text(mut app.repository_url, repository_recovery_url)
	software_repository_text(mut app.repository_key, repository_recovery_key)
	for mode in ['partial', 'complete', 'failed', 'invalid']! {
		app.repository_status.close()
		app.repository_status = pkgprotocol.decode_repository_configuration(previous)!
		app.repository_selected = 0; app.repository_scroll = 0
		os.setenv('VINIX_SOFTWARE_REPOSITORY_RECOVERY', mode, true)
		repository_recovery_activate(mut app, 'software.repository.reload', 320, 240)!
		repository_recovery_require(app.worker != unsafe { nil } && app.worker.args == ['--json', 'repo-config']
			&& app.repository_mode && !app.admin_prompt && app.prepare_close(), 'rendered repository reload did not start a public list read')!
		pid := app.worker.pid
		if mode in ['partial', 'complete']! {
			repository_recovery_wait(mut app, if mode == 'partial' { 17 } else { complete.len })!
			repository_recovery_require(app.worker.is_alive() && app.repository_read_running()
				&& app.repository_status.repositories[0].id == 'previous', 'unfinished child replaced the previous repository list')!
			repository_recovery_geometry(mut app, 'active')!
			app.handle('software.repository.reload')!
			repository_recovery_require(app.worker.pid == pid, 'busy repository read accepted another reload')!
			repository_recovery_activate(mut app, 'software.repository.stop', 320, 240)!
			repository_recovery_require(app.worker == unsafe { nil } && C.kill(pid, 0) != 0
				&& app.repository_worker == .none && !app.worker_view && !app.worker_review
				&& app.output.len == 0 && app.status.contains('stopped'), 'stopped repository child was not reaped and retired')!
		} else {
			repository_recovery_wait(mut app, 0)!
			repository_recovery_require(C.kill(pid, 0) != 0, 'failed repository child was not reaped')!
			repository_recovery_require(if mode == 'failed' { app.failure_pages.len > 0 && app.status.contains('temporarily unavailable') }
				else { app.status.contains('Invalid repository configuration response') }, 'repository failure reached the wrong recovery state')!
		}
		repository_recovery_require(app.repository_status.repositories.len == 1 && app.repository_status.repositories[0].id == 'previous'
			&& app.repository_status.repositories[0].url == repository_recovery_url
			&& app.repository_status.repositories[0].public_key == repository_recovery_key
			&& app.repository_selected == 0 && app.repository_scroll == 0, 'failed/stopped read replaced previous valid configuration')!
		repository_recovery_drafts(&app)!
		repository_recovery_geometry(mut app, if mode in ['partial', 'complete']! { 'stopped' } else { mode })!
		app.progress_seen = true
		repository_recovery_geometry(mut app, if mode in ['partial', 'complete']! { 'stopped' } else { mode })!
		app.progress_seen = false
		os.setenv('VINIX_SOFTWARE_REPOSITORY_RECOVERY', 'success', true)
		repository_recovery_activate(mut app, 'software.repository.reload', 320, 240)!
		repository_recovery_require(app.worker != unsafe { nil } && app.worker.args == ['--json', 'repo-config'] && !app.admin_prompt,
			'rendered recovery button did not launch the fresh list')!
		repository_recovery_wait(mut app, 0)!
		repository_recovery_require(app.repository_status.repositories.len == 1 && app.repository_status.repositories[0].id == 'replacement'
			&& app.repository_selected == -1, 'fresh successful read did not replace the previous list')!
		repository_recovery_drafts(&app)!
		repository_recovery_geometry(mut app, 'ready')!
		repository_recovery_activate(mut app, 'software.repository.enroll', 640, 610)!
		repository_recovery_wait(mut app, 0)!
		repository_recovery_require(app.repository_review_ready && app.repository_operation == 'enroll'
			&& app.repository_pending.id == 'draft', 'recovered list cannot start a fresh literal trust review')!
		repository_recovery_geometry(mut app, 'review')!
		app.handle('software.repository.reload')!
		repository_recovery_require(app.worker == unsafe { nil } && app.repository_review_ready, 'reload interrupted an unaccepted trust review')!
		repository_recovery_activate(mut app, 'software.repository.cancel', 320, 240)!
	}
	// Real accepted enrollment/revocation children and a refresh child.
	// No administrator authentication or persisted trust publication is qualified.
	app.administration_required = false
	for operation in ['enroll', 'revoke', 'refresh']! {
		if operation == 'refresh' {
			app.start(['update'], false); app.repository_worker = .refresh
		} else {
			repository_recovery_activate(mut app, 'software.repository.' + operation, 640, 610)!
			repository_recovery_wait(mut app, 0)!
			repository_recovery_require(app.repository_review_ready, 'protected writer lacks a ready trust review')!
			repository_recovery_activate(mut app, 'software.repository.confirm', 640, 610)!
		}
		for _ in 0 .. 5000 {
			app.poll()
			if app.progress_seen { break }
			time.sleep(time.millisecond)
		}
		repository_recovery_require(app.worker != unsafe { nil } && app.progress_seen && !app.prepare_close()
			&& !app.repository_read_running(), 'protected repository writer did not reach its child barrier')!
		pid := app.worker.pid
		repository_recovery_geometry(mut app, 'writer')!
		for action in ['software.repository.reload', 'software.repository.stop', 'software.repository.cancel',
			'software.repository.back', 'software.report.read']! { app.handle(action)! }
		app.key_input('\x1b'); app.stop_repository_read()
		repository_recovery_require(app.worker.pid == pid && app.worker.is_alive() && app.repository_mode,
			'compact recovery interrupted a protected writer')!
		repository_recovery_require(C.write(app.worker.stdio_fd[0], c'x', 1) == 1, 'cannot release protected writer')!
		repository_recovery_wait(mut app, 0)!
	}
	repository_recovery_require(editor_bytes_text(app.query) == 'kept query' && app.selected == 5 && app.filter == 1,
		'repository recovery changed catalog state')!
	println('REPOSITORY RECOVERY four real child Stop/failure/invalid recovery paths retain configured identities and literal drafts PASS')
	println('REPOSITORY RECOVERY nine compact/tiny canvases, lifecycle guards and nonoverlapping geometry PASS')
}

fn repository_recovery_render_cycle(mut app SoftwareApp) ! {
	for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 400, 300), ui2.rect(0, 0, 180, 96),
		ui2.rect(0, 0, 180, 129), ui2.rect(0, 0, 180, 130), ui2.rect(0, 0, 180, 167),
		ui2.rect(0, 0, 180, 168), ui2.rect(0, 0, 180, 220), ui2.rect(0, 0, 319, 239)]! {
		free_window_tree(app.build(size)!)
	}
}

fn repository_recovery_memory() ! {
	$if track_heap ? {
		C.vinix_heap_begin()
		positive := unsafe { malloc(37) }
		positive_bytes := C.vinix_heap_end(); positive_records := C.vinix_heap_count()
		unsafe { free(positive) }
		repository_recovery_require(positive_bytes == 37 && positive_records == 1, 'heap tracker missed positive control')!
		C.vinix_heap_begin()
		balanced := unsafe { malloc(37) }; unsafe { free(balanced) }
		repository_recovery_require(C.vinix_heap_end() == 0 && C.vinix_heap_count() == 0, 'heap tracker missed balanced free control')!
		mut app := SoftwareApp{ repository_mode: true, output: []u8{cap: 8192}, status: 'Reload configured repositories.' }
		defer { app.close_app() }
		app.initialize_repository_fields()
		software_repository_text(mut app.repository_id, 'draft')
		software_repository_text(mut app.repository_url, repository_recovery_url)
		software_repository_text(mut app.repository_key, repository_recovery_key)
		app.output << 'fixture: configured repositories are temporarily unavailable'.bytes()
		app.capture_failure(['--json', 'repo-config'], 23)
		for _ in 0 .. 2 { repository_recovery_render_cycle(mut app)! }
		C.vinix_heap_begin()
		for _ in 0 .. 1000 { repository_recovery_render_cycle(mut app)! }
		kept := C.vinix_heap_end(); records := C.vinix_heap_count()
		repository_recovery_require(kept == 0 && records == 0, 'compact repository recovery render retained allocations')!
		println('REPOSITORY RECOVERY 1000 cycles / 9000 trees retain 0 bytes / 0 records PASS')
	}
}

fn repository_targeted_refresh() ! {
	defer { os.unsetenv('VINIX_SOFTWARE_REPOSITORY_RECOVERY') }
	mut app := SoftwareApp{ service_path: os.executable(), repository_mode: true,
		administration_required: true, output: []u8{cap: 8192}, query: 'kept query'.bytes(), filter: 1 }
	defer { app.close_app() }
	remote := pkgprotocol.Repository{ id: 'remote', url: 'https://publisher.example/current',
		public_key: repository_recovery_key }
	text := json2.encode(pkgprotocol.RepositoryConfiguration{ format: 1, scope: 'configuration',
		architecture: 'aarch64', repositories: [remote, repository_recovery_configuration('field').repositories[0]] })
	defer { unsafe { text.free() } }
	app.repository_status = pkgprotocol.decode_repository_configuration(text)!
	const_width := 640
	const_height := 610
	action := 'software.repository.refresh'
	metadata_text := software_progress_text(pkgprotocol.Progress{ phase: 'verify', repository: 'field', path: 'index.json' })
	payload_text := software_progress_text(pkgprotocol.Progress{ phase: 'verify', repository: 'field', package: 'example', path: 'bin/app' })
	defer { unsafe { metadata_text.free(); payload_text.free() } }
	repository_recovery_require(metadata_text == 'Verifying signed metadata: field/index.json'
		&& payload_text == 'Verifying example/bin/app…', 'metadata and payload verification have incorrect labels')!
	app.handle(action)!
	repository_recovery_require(app.worker == unsafe { nil }, 'refresh accepted without a selection')!
	repository_recovery_activate(mut app, 'software.row.1', const_width, const_height)!
	for field in ['id', 'url', 'key']! {
		app.handle('software.repository.' + field)!
		app.key_input('\x01')
		app.paste_input('draft')
		tree := app.build(ui2.rect(0, 0, const_width, const_height))!
		present := tree.children.any(it.id == action)
		free_window_tree(tree)
		app.handle(action)!
		repository_recovery_require(!present && app.worker == unsafe { nil }, 'refresh admitted an edited trust draft')!
		repository_recovery_activate(mut app, 'software.row.1', const_width, const_height)!
	}
	repository_recovery_activate(mut app, 'software.offline', const_width, const_height)!
	os.setenv('VINIX_SOFTWARE_REPOSITORY_RECOVERY', 'targeted-approved', true)
	repository_recovery_activate(mut app, action, const_width, const_height)!
	repository_recovery_require(app.admin_prompt && app.repository_worker == .targeted_refresh
		&& app.worker.args == ['admin', '--progress', '--offline', 'update', 'field', repository_recovery_fingerprint('field')],
		'selected offline refresh did not ask for the exact administrator action')!
	pid := app.worker.pid
	repository_recovery_activate(mut app, 'software.admin.cancel', const_width, const_height)!
	repository_recovery_require(app.worker == unsafe { nil } && C.kill(pid, 0) != 0
		&& !app.admin_prompt && app.repository_worker == .none && !app.status.contains('trust was saved'),
		'cancelled targeted approval left a child or incorrect trust status')!
	repository_recovery_activate(mut app, action, const_width, const_height)!
	app.key_input('x')
	repository_recovery_activate(mut app, 'software.admin.approve', const_width, const_height)!
	repository_recovery_wait(mut app, 0)!
	repository_recovery_require(app.status == 'Selected repository refreshed.' && app.repository_mode
		&& app.selected_repository_refresh_id() == 'field' && app.repository_worker == .none,
		'approved refresh lost the selection or returned an incorrect result')!
	repository_recovery_activate(mut app, 'software.offline', const_width, const_height)!
	app.administration_required = false
	os.setenv('VINIX_SOFTWARE_REPOSITORY_RECOVERY', 'targeted-failed', true)
	repository_recovery_activate(mut app, action, const_width, const_height)!
	for _ in 0 .. 5000 {
		app.poll()
		if app.progress_seen { break }
		time.sleep(time.millisecond)
	}
	repository_recovery_require(app.worker != unsafe { nil } && app.status.contains('waiting for the service to exit')
		&& !app.prepare_close(), 'refresh completion escaped the active writer guard')!
	for event in [action, 'software.repository.reload', 'software.offline', 'software.repository.back']! {
		app.handle(event)!
	}
	app.key_input('\x1b')
	repository_recovery_require(app.repository_mode && !app.offline_requested && app.worker.is_alive()
		&& app.worker.args == ['--progress', 'update', 'field', repository_recovery_fingerprint('field')],
		'active refresh allowed navigation or argument changes')!
	repository_recovery_require(C.write(app.worker.stdio_fd[0], c'x', 1) == 1, 'cannot release targeted refresh child')!
	repository_recovery_wait(mut app, 0)!
	repository_recovery_require(app.status.contains('no authenticated cached index')
		&& app.failure_heading == 'Refresh selected repository · exit 23'
		&& app.selected_repository_refresh_id() == 'field' && app.repository_status.repositories[0] == remote
		&& editor_bytes_text(app.query) == 'kept query' && app.filter == 1,
		'failed refresh lost diagnostics, repository identity or search state')!
	println('REPOSITORY REFRESH selected enrolled source, literal arguments, approval, cancellation and guarded failure PASS')
}

fn repository_browse_cycle(mut app SoftwareApp) ! {
	repository_recovery_activate(mut app, 'software.repository.browse', 320, 240)!
	mut tree := app.build(ui2.rect(0, 0, 180, 220))!
	free_window_tree(tree)
	app.handle('software.report.package.next')!
	tree = app.build(ui2.rect(0, 0, 640, 610))!
	free_window_tree(tree)
	app.handle('software.report.back')!
}

fn repository_browse_refresh() ! {
	defer { os.unsetenv('VINIX_SOFTWARE_REPOSITORY_RECOVERY') }
	mut app := SoftwareApp{ service_path: os.executable(), repository_mode: true,
		administration_required: true, offline_requested: true, output: []u8{cap: 8192} }
	defer { app.close_app() }
	app.initialize_repository_fields()
	software_repository_text(mut app.repository_id, 'draft')
	software_repository_text(mut app.repository_url, repository_recovery_url)
	software_repository_text(mut app.repository_key, repository_recovery_key)
	app.repository_focus = 2
	app.select_all = true
	prefix := 'https://publisher.example/部署-é/'
	long_url := prefix + 'a'.repeat(4096 - prefix.len - '🚀'.len) + '🚀'
	defer { unsafe { long_url.free() } }
	remote := pkgprotocol.Repository{ id: 'remote', url: long_url, public_key: 'a'.repeat(64) }
	configuration := repository_recovery_configuration('field')
	text := json2.encode(pkgprotocol.RepositoryConfiguration{ ...configuration, repositories: [remote, ...configuration.repositories] })
	defer { unsafe { text.free() } }
	app.repository_status = pkgprotocol.decode_repository_configuration(text)!

	repository_recovery_activate(mut app, 'software.repository.browse', 320, 240)!
	repository_recovery_require(app.repository_browse_index == 0 && app.report_reader_mode
		&& app.worker == unsafe { nil }, 'compact repository reader opened the wrong source')!
	mut canonical := []u8{cap: 5000}
	mut rendered := []u8{cap: 5000}
	mut compact := []u8{cap: 5000}
	defer { unsafe { canonical.free(); rendered.free(); compact.free() } }
	for page in app.details_pages {
		for line in page.text.split_into_lines() {
			start := if line.starts_with('• ') { '• '.len } else { 2 }
			canonical << line[start..].bytes()
			rendered << line.bytes()
		}
	}
	literal := 'Repository ID: remoteSource URL: ' + long_url + 'Publisher key: ' + remote.public_key
	defer { unsafe { literal.free() } }
	repository_recovery_require(editor_bytes_text(canonical) == literal, 'repository reader lost literal identity bytes')!
	for page, expected in app.details_compact_pages {
		size := ui2.rect(0, 0, 180, 220)
		tree := app.build(size)!
		defer { free_window_tree(tree) }
		repository_recovery_check_frames(tree, size)!
		repository_recovery_require(app.details_compact_page == page && tree.children.any(it.text == 'remote'),
			'compact reader lost its page or repository ID')!
		mut shown := []u8{cap: 48}
		for label in tree.children {
			if label.frame.y >= 118 && label.frame.y < 172 { shown << label.text.bytes() }
		}
		line_bytes := expected.text.replace('\n', '')
		repository_recovery_require(editor_bytes_text(shown) == line_bytes, 'rendered compact page differs from retained text')!
		compact << shown
		unsafe { shown.free(); line_bytes.free() }
		button := repository_recovery_element(tree, 'software.report.next')!
		app.handle(button.id)!
	}
	repository_recovery_require(editor_bytes_text(compact) == editor_bytes_text(rendered),
		'compact pages lost exact source URL or publisher key bytes')!
	for event in ['software.repository.reload', 'software.repository.confirm', 'software.repository.new',
		'software.repository.refresh', 'software.offline']! {
		app.handle(event)!
	}
	repository_recovery_require(app.report_reader_mode && app.worker == unsafe { nil } && app.offline_requested,
		'repository reader admitted an unrelated action')!
	app.key_input('\x1b')
	repository_recovery_require(!app.report_reader_mode && app.repository_browse_index == -1
		&& app.details_pages.len == 0 && app.details_compact_pages.len == 0
		&& app.repository_focus == 2 && app.select_all && app.repository_selected == -1,
		'closing repository details lost editor state or left pages allocated')!
	repository_recovery_drafts(&app)!

	for outcome in ['cancel', 'approve']! {
		os.setenv('VINIX_SOFTWARE_REPOSITORY_RECOVERY', 'targeted-approved', true)
		repository_recovery_activate(mut app, 'software.repository.browse', 320, 240)!
		repository_recovery_activate(mut app, 'software.report.package.next', 320, 240)!
		repository_recovery_require(app.repository_browse_index == 1 && app.details_page == 0,
			'next repository did not show its first identity page')!
		repository_recovery_activate(mut app, 'software.repository.browse.refresh', 320, 240)!
		repository_recovery_require(app.admin_prompt && app.repository_worker == .targeted_refresh
			&& !app.report_reader_mode && app.worker.args == ['admin', '--progress', '--offline', 'update', 'field',
				repository_recovery_fingerprint('field')], 'compact refresh did not bind approval to the displayed source')!
		for size in [ui2.rect(0, 0, 180, 219), ui2.rect(0, 0, 180, 220), ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 640, 610)]! {
			tree := app.build(size)!
			defer { free_window_tree(tree) }
			repository_recovery_check_frames(tree, size)!
			repository_recovery_require(tree.children.any(it.id == 'software.admin.password') == (size.height >= 220)
				&& tree.children.any(it.id == 'software.admin.approve') == (size.height >= 220)
				&& tree.children.any(it.id == 'software.admin.cancel'), 'administrator controls have wrong compact admission')!
		}
		if outcome == 'approve' {
			repository_recovery_activate(mut app, 'software.admin.password', 320, 240)!
			app.key_input('x')
		}
		repository_recovery_activate(mut app, 'software.admin.' + outcome, 320, 240)!
		repository_recovery_wait(mut app, 0)!
		repository_recovery_require(!app.admin_prompt && app.admin_password_len == 0
			&& app.admin_password.all(it == 0) && app.repository_mode
			&& app.status.contains(if outcome == 'approve' { 'Selected repository refreshed.' } else { 'approval cancelled' }),
			'compact approval did not retire its credentials and return to repositories')!
		repository_recovery_drafts(&app)!
	}
	println('REPOSITORY BROWSER compact exact identity, bounded paging, preserved draft and approved or cancelled refresh PASS')

	$if track_heap ? {
		repository_browse_cycle(mut app)!
		C.vinix_heap_begin()
		for _ in 0 .. 64 { repository_browse_cycle(mut app)! }
		kept := C.vinix_heap_end(); records := C.vinix_heap_count()
		repository_recovery_require(kept == 0 && records == 0, 'repository browse cycles retained ${kept} bytes / ${records} records')!
		println('REPOSITORY BROWSER 64 open navigate render close cycles retain 0 bytes / 0 records PASS')
	}
}

fn check_software_repository_recovery() ! {
	repository_recovery_functional()!
	repository_targeted_refresh()!
	repository_refresh_after_enrollment()!
	repository_browse_refresh()!
	repository_recovery_memory()!
	println('REPOSITORY RECOVERY explicit production-safe checks PASS')
}

fn repository_refresh_after_enrollment() ! {
	defer { os.unsetenv('VINIX_SOFTWARE_REPOSITORY_RECOVERY') }
	for outcome in ['success', 'cancel', 'failed']! {
		os.setenv('VINIX_SOFTWARE_REPOSITORY_RECOVERY', 'enrollment-refresh-' + outcome, true)
		mut app := SoftwareApp{ service_path: os.executable(), repository_mode: true,
			administration_required: true, offline_requested: true, output: []u8{cap: 8192} }
		defer { app.close_app() }
		app.initialize_repository_fields()
		software_repository_text(mut app.repository_id, 'draft')
		software_repository_text(mut app.repository_url, repository_recovery_url)
		software_repository_text(mut app.repository_key, repository_recovery_key)
		repository_recovery_activate(mut app, 'software.repository.enroll', 640, 610)!
		repository_recovery_wait(mut app, 0)!
		repository_recovery_require(app.repository_review_ready, 'enrollment did not present its trust review')!
		repository_recovery_activate(mut app, 'software.repository.confirm', 640, 610)!
		repository_recovery_require(app.admin_prompt && app.repository_worker == .enroll,
			'enrollment did not retain its first administrator prompt')!
		app.key_input('x')
		repository_recovery_activate(mut app, 'software.admin.approve', 640, 610)!
		for _ in 0 .. 5000 {
			app.poll()
			if app.repository_worker == .refresh && app.admin_prompt { break }
			time.sleep(time.millisecond)
		}
		repository_recovery_require(app.worker != unsafe { nil } && app.repository_worker == .refresh && app.admin_prompt
			&& app.worker.args == ['admin', '--progress', '--offline', 'update', 'draft', repository_recovery_fingerprint('draft')]
			&& app.status.contains('trust was saved') && app.status.contains('Enter your administrator password')
			&& app.admin_password_len == 0, 'enrollment did not request independent approval for the reviewed repository')!
		if outcome == 'cancel' {
			repository_recovery_activate(mut app, 'software.admin.cancel', 640, 610)!
		} else {
			app.key_input('x')
			repository_recovery_activate(mut app, 'software.admin.approve', 640, 610)!
		}
		repository_recovery_wait(mut app, 0)!
		repository_recovery_require(app.repository_mode && !app.admin_prompt && app.offline_requested
			&& app.repository_status.repositories.len == 2 && app.repository_status.repositories[0].id == 'remote'
			&& app.selected_repository_refresh_id() == 'draft', 'follow-up refresh did not reload the saved enrollment')!
		match outcome {
			'success' {
				repository_recovery_require(app.status == 'Repository trusted and its catalog refreshed.',
					'selected enrollment refresh did not report success')!
			}
			'cancel' {
				repository_recovery_require(app.status.contains('trust was saved') && app.status.contains('approval was cancelled'),
					'cancelled refresh did not report saved trust')!
			}
			else {
				repository_recovery_require(app.status.contains('trust was saved') && app.status.contains('refresh all repositories')
					&& app.status.contains('no authenticated cached index')
					&& app.failure_heading == 'Refresh selected repository · exit 23',
					'failed refresh did not retain saved trust, diagnostic and full refresh guidance')!
			}
		}
	}
	println('REPOSITORY ENROLLMENT separate approval refreshes the reviewed source and retains trust after cancellation or failure PASS')
}
