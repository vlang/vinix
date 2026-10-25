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

// Private deterministic replies do not represent publisher authority.
// Explicit checks and all I/O remain active with -prod.
fn repository_recovery_service(args []string) !bool {
	mode := os.getenv('VINIX_SOFTWARE_REPOSITORY_RECOVERY')
	if mode == '' || args.len < 2 { return false }
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

fn repository_recovery_geometry(mut app SoftwareApp, state string) ! {
	for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 400, 300), ui2.rect(0, 0, 180, 96),
		ui2.rect(0, 0, 180, 129), ui2.rect(0, 0, 180, 130), ui2.rect(0, 0, 180, 167),
		ui2.rect(0, 0, 180, 168), ui2.rect(0, 0, 180, 220), ui2.rect(0, 0, 319, 239)]! {
		tree := app.build(size)!
		defer { free_window_tree(tree) }
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
		repository_recovery_require(tree.children.any(it.text == app.status), 'compact repositories omit status')!
		repository_recovery_require(!tree.children.any(it.id == 'software.repository.confirm'), 'compact repositories expose trust confirmation')!
		mut next_y := 84
		for child in tree.children {
			if child.id in ['software.report.read', 'software.repository.reload', 'software.failure']! { next_y += 38 }
		}
		repository_recovery_require(tree.children.any(it.id == 'software.progress')
			== (app.progress_seen && size.height >= 240 && next_y <= size.height - 110),
			'compact repository progress is absent or overlaps action rows')!
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

fn check_software_repository_recovery() ! {
	repository_recovery_functional()!
	repository_recovery_memory()!
	println('REPOSITORY RECOVERY explicit production-safe checks PASS')
}
