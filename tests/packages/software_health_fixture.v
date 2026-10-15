// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import desktop.packagecore
import tools.packages.pkgprotocol

fn software_health_fixture() pkgprotocol.HealthReport {
	mut rows := []pkgprotocol.PackageHealth{cap: 32}
	for index in 0 .. 32 {
		number := index.str()
		rows << pkgprotocol.PackageHealth{ id: 'app-' + if index < 10 { '0' + number } else { number },
			name: (if index == 5 { 'Zephyr ' } else { '' }) + 'Health é🚀 '.repeat(12),
			version: if index == 7 { '1.2.3' } else { '1.0.0' }, kind: if index == 2 { 'runtime' } else if index == 8 { 'data' } else { 'native' },
			repository: if index == 4 { 'organization-mirror' } else { 'publisher-' + 'a'.repeat(110) },
			public_key: if index == 6 { 'b'.repeat(64) } else { 'a'.repeat(64) },
			issue: match index { 1 { 'payload' } 2 { 'namespace' } 3 { 'registration' } else { '' } },
			diagnostic: if index in [1, 2, 3]! { 'A complete diagnostic é🚀 '.repeat(10) } else { '' } }
	}
	return pkgprotocol.HealthReport{ generation: 7, architecture: 'aarch64', rows: rows }
}

fn software_health_service_fixture(args []string) bool {
	if args.len != 4 || args[1..] != ['--json', '--progress', 'health'] { return false }
	mode := os.getenv('VINIX_SOFTWARE_HEALTH_MODE')
	defer { unsafe { mode.free() } }
	if mode == 'failed' { eprintln('Installed state is unavailable; restore storage before retrying.'); exit(23) }
	report := if mode == 'empty' { pkgprotocol.HealthReport{ architecture: 'aarch64' } } else { software_health_fixture() }
	if mode != 'no-progress' {
		first := pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'verify' }) + '\n'
		eprint(first[..8]); flush_stderr()
		if mode == 'barrier-partial' { health_fixture_barrier() }
		time.sleep(5 * time.millisecond); eprint(first[8..]); flush_stderr()
		for index, row in report.rows {
			if mode == 'wrong-count' && index == report.rows.len - 1 { break }
			eprintln(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'verify', package: row.id, repository: row.repository }))
			flush_stderr()
			if mode == 'slow' && index == 1 { time.sleep(3 * time.second) }
			if mode == 'barrier-live' && index == 1 { health_fixture_barrier() }
		}
		if mode == 'malformed-progress' { eprintln(pkgprotocol.progress_prefix + '{broken}') }
		if mode == 'partial-progress' { eprint(pkgprotocol.progress_prefix + '{}'); flush_stderr() }
		if mode == 'oversized-progress' { eprintln('unframed diagnostic '.repeat(500)) }
		if mode == 'flood' { for _ in 0 .. 500 { eprintln('A retained failure after many stderr pipe chunks.') } }
		if mode !in ['incomplete', 'partial-progress'] {
			last := pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 })
			eprintln(last)
			if mode == 'duplicate-complete' { eprintln(last) }
			if mode == 'reordered' { eprintln(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'verify' })) }
		}
		flush_stderr()
	}
	text := json2.encode(report)
	defer { unsafe { text.free() } }
	println(match mode {
		'missing' { text.replace(',"diagnostic":""', '') }
		'duplicate' { text.replace('"generation":7', '"generation":7,"generat\\u0069on":7') }
		'type' { text.replace('"issue":"payload"', '"issue":true') }
		'trailing' { text + '{}' }
		else { text }
	})
	flush_stdout()
	if mode in ['barrier-complete', 'barrier-late-failure']! { health_fixture_barrier() }
	if mode in ['late-failure', 'barrier-late-failure']! { eprintln('Storage read failed after the completion frame.'); exit(24) }
	return true
}

fn health_fixture_barrier() {
	mut release := u8(0); assert C.read(0, &release, 1) == 1
}

fn wait_for_health_barrier(mut app SoftwareApp, mode string) {
	for _ in 0 .. 5000 {
		app.poll()
		if mode == 'barrier-partial' && app.progress_pending.len == 8 { return }
		if mode == 'barrier-live' && app.health_progress_packages == 2 { return }
		if mode in ['barrier-complete', 'barrier-late-failure']! && app.progress_snapshot.phase == 'complete' && app.output.len > 0 { return }
		time.sleep(time.millisecond)
	}
	assert false, 'health fixture did not reach its output barrier (${mode}): ${app.status}'
}

fn check_software_health_navigation() ! {
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true,
		query: 'catalog-search'.bytes(), output: []u8{cap: 8192}, matching: [0], selected: 0, filter: 1,
		health_query: 'APP-02'.bytes(), health_issues_only: true,
		catalog_error: 'catalog unavailable'.clone(), rows: [SoftwareRow{ id: 'editor', name: 'Editor', installed_version: '1.0.0' }] }
	defer { os.unsetenv('VINIX_SOFTWARE_HEALTH_MODE'); app.close_app() }
	os.setenv('VINIX_SOFTWARE_HEALTH_MODE', 'failed', true)
	app.handle('software.health')!; wait_for_software(mut app)
	assert !app.health_ready && app.failure_pages.len > 0 && app.status.contains('restore storage')
	for mode in ['barrier-partial', 'barrier-live', 'barrier-complete']! {
		for action in ['software.health.stop', 'software.cancel', 'escape']! {
			os.setenv('VINIX_SOFTWARE_HEALTH_MODE', mode, true)
			app.handle('software.health.reload')!; wait_for_health_barrier(mut app, mode)
			pid := app.worker.pid
			assert app.worker_health && app.worker_view && app.prepare_close() && !app.admin_prompt
			assert app.worker.args == ['--json', '--progress', 'health']
			assert !app.health_ready && app.health_snapshot.rows.len == 0 && app.details_pages.len == 0
			if mode == 'barrier-complete' { assert app.status.contains('waiting for the service to exit') }
			for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
				tree := app.build(size)!
				assert tree.children.any(it.id == 'software.health.stop') && tree.children.any(it.text == app.status)
				assert tree.children.any(it.id == 'software.progress') == (mode != 'barrier-partial')
				assert !tree.children.any(it.id in ['software.health.back', 'software.health.reload', 'software.health.repair', 'software.failure'])
				free_window_tree(tree)
			}
			for event in ['software.health.back', 'software.health.reload', 'software.health.repair', 'software.health.issues',
				'software.health.search', 'software.failure', 'software.install', packagecore.request_prefix + '{"id":"editor"}'] {
				app.handle(event)!
			}
			app.paste_input('\x1b'); app.key_input('must not edit')
			assert app.worker.pid == pid && app.worker.is_alive() && app.launch_request == ''
			if action == 'escape' { app.key_input('\x1b') } else { app.handle(action)! }
			assert app.worker == unsafe { nil } && C.kill(pid, 0) != 0 && !app.worker_health && !app.poll()
			assert !app.health_ready && app.health_snapshot.rows.len == 0 && app.health_progress_packages == 0
			assert !app.progress_seen && app.progress_pending.len == 0 && !app.progress_skip && app.health_errors.len == 0
			assert app.output.len == 0 && !app.output_truncated && app.status.contains('Inspection stopped')
			assert app.health_query.bytestr() == 'APP-02' && app.health_issues_only && app.failure_pages.len > 0
			compact := app.build(ui2.rect(0, 0, 320, 240))!
			assert compact.children.any(it.id == 'software.health.back') && compact.children.any(it.id == 'software.health.reload')
			assert compact.children.any(it.id == 'software.failure') && compact.children.any(it.text == app.status)
			for element in compact.children {
				assert element.frame.x >= 0 && element.frame.x + element.frame.width <= 320
				assert element.frame.y >= 0 && element.frame.y + element.frame.height <= 240
			}
			free_window_tree(compact)
			app.handle('software.failure')!; app.key_input('\x1b'); assert !app.failure_mode && app.health_mode
		}
	}
	for mode in ['barrier-late-failure', 'barrier-complete']! {
		os.setenv('VINIX_SOFTWARE_HEALTH_MODE', mode, true)
		app.handle('software.health.reload')!; wait_for_health_barrier(mut app, mode)
		assert !app.health_ready && app.status.contains('waiting for the service to exit')
		app.worker.stdin_write('x'); wait_for_software(mut app)
		if mode == 'barrier-late-failure' {
			assert !app.health_ready && app.health_snapshot.rows.len == 0 && app.status.contains('Storage read failed')
			assert app.failure_pages.len > 0
		} else {
			assert app.health_ready && app.health_matching == [2] && app.health_selected == 2
			assert app.health_snapshot.rows.len == 32 && app.health_summary.contains('3 with issues')
			app.handle('software.health.stop')!; app.handle('software.cancel')!
			assert app.health_ready && app.health_snapshot.rows.len == 32
		}
	}
	health_fixture_query(mut app, '')!; app.handle('software.health.issues')!
	full := app.build(ui2.rect(0, 0, 640, 610))!; free_window_tree(full)
	app.handle('software.health.down')!; app.handle('software.row.2')!; app.handle('software.health.next')!
	selected := app.health_selected; scroll := app.health_scroll; page := app.details_page
	assert scroll > 0 && page > 0
	app.handle('software.health.search')!; app.key_input('\x01')
	for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 240, 280), ui2.rect(0, 0, 900, 660)]! {
		tree := app.build(size)!
		assert tree.children.any(it.text == app.status) && tree.children.any(it.text == app.health_summary)
		assert tree.children.any(it.id == 'software.health.reload') && tree.children.any(it.id == 'software.failure')
		if size.width < 640 { assert !tree.children.any(it.id == 'software.health.search' || it.id == 'software.health.repair') }
		for element in tree.children {
			assert element.frame.x >= 0 && element.frame.x + element.frame.width <= size.width
			assert element.frame.y >= 0 && element.frame.y + element.frame.height <= size.height
		}
		free_window_tree(tree)
		assert app.health_selected == selected && app.health_scroll == scroll && app.details_page == page
		assert app.health_focus && app.health_select_all && app.health_query.len == 0 && !app.health_issues_only
	}
	app.key_input('\x1b'); assert app.health_mode && !app.health_focus && !app.health_select_all
	os.setenv('VINIX_SOFTWARE_HEALTH_MODE', 'empty', true)
	app.handle('software.health.reload')!; wait_for_software(mut app)
	assert app.health_ready && app.health_snapshot.rows.len == 0
	compact := app.build(ui2.rect(0, 0, 320, 240))!
	assert compact.children.any(it.text == app.health_summary) && !compact.children.any(it.id == 'software.health.repair')
	free_window_tree(compact)
	app.key_input('\x1b'); assert !app.health_mode && app.health_query.len == 0 && app.details_pages.len == 0
	assert app.query.bytestr() == 'catalog-search' && app.matching == [0] && app.selected == 0 && app.filter == 1
	assert app.rows.len == 1 && app.catalog_error == 'catalog unavailable'
	println('Software health navigation: partial/live/complete-before-exit Stop/Cancel/Escape, compact reload/status/progress/summary/failure, frozen search/filter/selection/paging, late failure and fresh retry PASS')
}

fn health_fixture_query(mut app SoftwareApp, query string) ! {
	app.handle('software.health.search')!
	app.key_input('\x01')
	// Select-all/backspace also permits a deliberately empty query.
	app.key_input('\x08')
	app.paste_input(query)
	assert editor_bytes_text(app.health_query) == query && app.worker == unsafe { nil }
}

fn check_health_filters(mut app SoftwareApp) ! {
	for query, indices in {
		'APP-23': [23], 'ZEPHYR': [5], '1.2.3': [7], 'RUNTIME': [2], 'DATA': [8],
		'ORGANIZATION-MIRROR': [4], 'BBBBBBBBBBBBBBBB': [6],
		'PAYLOAD': [1], 'NAMESPACE': [2], 'LAUNCHER': [3],
		'COMPLETE DIAGNOSTIC É🚀': [1, 2, 3],
	} {
		health_fixture_query(mut app, query)!
		assert app.health_matching == indices, query
		assert app.health_selected in indices && app.health_scroll == 0
		assert app.health_snapshot.rows[app.health_selected].id == 'app-' + (if app.health_selected < 10 { '0' } else { '' }) + app.health_selected.str()
	}
	health_fixture_query(mut app, 'APP-23')!
	health_fixture_query(mut app, '')!
	assert app.health_matching.len == 32 && app.health_selected == 23
	assert 23 in app.health_matching[app.health_scroll..app.health_scroll + app.page_rows]
	app.handle('software.health.issues')!
	assert app.health_issues_only && app.health_matching == [1, 2, 3] && app.health_selected == 1 && app.health_scroll == 0
	health_fixture_query(mut app, 'app-02')!
	app.handle('software.health.reload')!
	assert !app.health_ready && app.health_snapshot.rows.len == 0 && app.details_pages.len == 0
	assert editor_bytes_text(app.health_query) == 'app-02' && app.health_issues_only
	app.key_input('blocked'); app.paste_input('blocked'); app.handle('software.health.issues')!
	assert editor_bytes_text(app.health_query) == 'app-02' && app.health_issues_only
	wait_for_software(mut app)
	assert app.health_matching == [2] && app.health_selected == 2 && app.health_summary.contains('32 packages inspected')
	health_fixture_query(mut app, 'no such package')!
	assert app.health_matching.len == 0 && app.health_selected == -1 && app.details_pages.len == 0
	assert app.health_results == 'Showing 0 of 32' && app.health_summary.contains('3 with issues')
	empty := app.build(ui2.rect(0, 0, 640, 610))!
	assert empty.children.any(it.text == 'No packages match this search and filter.')
	assert empty.children.any(it.id == 'software.health.repair' && it.text == 'Review all repairs')
	assert !empty.children.any(it.id.starts_with('software.row.'))
	free_window_tree(empty)
	app.handle('software.row.0')!; assert app.health_selected == -1
	os.setenv('VINIX_SOFTWARE_HEALTH_MODE', 'duplicate', true)
	app.handle('software.health.reload')!; wait_for_software(mut app)
	assert !app.health_ready && app.health_snapshot.rows.len == 0 && app.details_pages.len == 0
	assert app.health_issues_only && editor_bytes_text(app.health_query) == 'no such package'
	os.unsetenv('VINIX_SOFTWARE_HEALTH_MODE')
	app.handle('software.health.reload')!; wait_for_software(mut app)
	assert app.health_ready && app.health_matching.len == 0
	app.handle('software.health.issues')!
	health_fixture_query(mut app, 'Health É🚀')!
	assert app.health_matching.len == 32
	health_fixture_query(mut app, 'é🚀')!
	app.key_input('\x7f'); assert editor_bytes_text(app.health_query) == 'é'
	app.key_input('\x08'); assert app.health_query.len == 0
	health_fixture_query(mut app, 'z'.repeat(console_filter_limit))!
	app.paste_input('discarded'); assert app.health_query.len == console_filter_limit
	app.key_input('\x01'); app.key_input('\x7f')
	assert app.health_query.len == 0 && app.health_matching.len == 32
	app.key_input('\x1b'); assert app.health_mode && !app.health_focus
	app.key_input('unfocused'); app.paste_input('unfocused'); assert app.health_query.len == 0
	small := app.build(ui2.rect(0, 0, 320, 240))!
	assert small.children.any(it.id == 'software.health.back')
	assert !small.children.any(it.id == 'software.health.search' || it.id == 'software.health.repair')
	for element in small.children { assert element.frame.x >= 0 && element.frame.x + element.frame.width <= 320 }
	free_window_tree(small)
	assert app.query == 'catalog-search'.bytes() && app.selected == 0 && app.filter == 1
}

fn check_software_health() ! {
	check_software_health_navigation()!
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true,
		query: 'catalog-search'.bytes(), output: []u8{cap: 8192}, matching: [0], selected: 0, filter: 1,
		catalog_error: 'catalog unavailable'.clone(), rows: [SoftwareRow{ id: 'editor', name: 'Editor', installed_version: '1.0.0' }] }
	defer { os.unsetenv('VINIX_SOFTWARE_HEALTH_MODE'); app.close_app() }
	tree := app.build(ui2.rect(0, 0, 640, 610))!
	assert tree.children.any(it.id == 'software.health' && it.text == 'Health report'); free_window_tree(tree)
	app.handle('software.health')!
	assert app.health_mode && app.worker_health && app.worker_view && !app.admin_prompt && app.prepare_close()
	assert app.worker.args == ['--json', '--progress', 'health']
	pid := app.worker.pid; app.handle('software.health')!; assert app.worker.pid == pid
	wait_for_software(mut app)
	assert app.health_ready && app.health_snapshot.rows.len == 32 && app.health_summary.contains('3 with issues')
	assert app.health_matching[..4] == [1, 2, 3, 0] && app.health_selected == 1
	assert 'Installed publisher key: ' + 'a'.repeat(64) in details_fixture_values(&app, 0)
	assert 'Architecture: aarch64' in details_fixture_values(&app, 0)
	assert 'Diagnostic: ' + 'A complete diagnostic é🚀 '.repeat(10) in details_fixture_values(&app, 0)
	assert app.details_pages.len > 1 && !app.details_mode
	for _ in 0 .. app.details_pages.len + 2 { app.handle('software.health.next')! }
	assert app.details_page == app.details_pages.len - 1
	health := app.build(ui2.rect(0, 0, 640, 610))!
	assert health.children.any(it.id == 'software.health.repair') && !health.children.any(it.id == 'software.confirm')
	assert health.children.any(it.id == 'software.row.0' && it.text == 'Payload: app-01')
	assert health.children.any(it.id == 'software.row.2' && it.text == 'Launcher: app-03')
	for element in health.children {
		if element.id.starts_with('software.row.') { assert element.frame.y >= 128 && element.frame.y + element.frame.height <= 396 }
	}
	free_window_tree(health)
	for hidden in ['software.confirm', 'software.install', 'software.repair', 'software.upgrade', 'software.verify', packagecore.request_prefix + '{"id":"editor"}'] {
		app.handle(hidden)!; assert app.health_mode && app.worker == unsafe { nil } && app.review == '' && app.launch_request == ''
	}
	app.key_input('changed'); app.paste_input('changed'); assert app.query == 'catalog-search'.bytes()
	app.handle('software.health.down')!; assert app.health_scroll > 0
	app.handle('software.row.0')!; assert app.health_selected == app.health_matching[app.health_scroll] && app.details_page == 0
	check_health_filters(mut app)!
	app.handle('software.health.back')!
	assert !app.health_mode && app.health_snapshot.rows.len == 0 && app.health_query.len == 0 && !app.health_issues_only
	assert app.selected == 0 && app.filter == 1 && app.query == 'catalog-search'.bytes() && app.catalog_error == 'catalog unavailable'
	for mode in ['missing', 'duplicate', 'type', 'trailing', 'failed', 'incomplete', 'no-progress', 'malformed-progress', 'partial-progress', 'wrong-count', 'reordered', 'duplicate-complete', 'oversized-progress', 'flood', 'late-failure'] {
		os.setenv('VINIX_SOFTWARE_HEALTH_MODE', mode, true)
		app.handle('software.health')!; wait_for_software(mut app)
		assert app.health_mode && !app.health_ready && app.health_snapshot.rows.len == 0
		failed := app.build(ui2.rect(0, 0, 640, 610))!
		assert !failed.children.any(it.id == 'software.health.repair')
		free_window_tree(failed)
		assert app.failure_pages.len > 0
		if mode in ['failed', 'late-failure', 'flood'] { assert app.status.contains(if mode == 'failed' { 'restore storage' } else if mode == 'flood' { 'retained failure' } else { 'Storage read failed' }) }
		app.handle('software.health.repair')!; assert app.worker == unsafe { nil } && app.review == ''
		app.handle('software.health.back')!
	}
	os.setenv('VINIX_SOFTWARE_HEALTH_MODE', 'empty', true)
	app.handle('software.health')!; wait_for_software(mut app)
	assert app.health_ready && app.health_snapshot.rows.len == 0 && app.health_progress_packages == 0
	app.handle('software.health.back')!
	os.unsetenv('VINIX_SOFTWARE_HEALTH_MODE')
	app.handle('software.health')!; wait_for_software(mut app)
	health_fixture_query(mut app, 'no matching package')!
	app.handle('software.health.repair')!
	assert !app.health_mode && app.health_snapshot.rows.len == 0 && app.worker.args == ['review', 'repair'] && !app.admin_prompt
	wait_for_software(mut app); assert app.review_ready; app.handle('software.cancel')!
	os.setenv('VINIX_SOFTWARE_HEALTH_MODE', 'slow', true)
	for escape in [false, true]! {
		app.handle('software.health')!; slow := app.worker.pid
		for _ in 0 .. 500 { app.poll(); if app.health_progress_packages > 0 { break }; time.sleep(time.millisecond) }
		assert app.worker != unsafe { nil } && app.progress_seen && app.status.contains('Inspecting app-') && !app.health_ready
		pending := app.build(ui2.rect(0, 0, 640, 610))!
		assert pending.children.any(it.id == 'software.health.stop') && pending.children.any(it.id == 'software.progress')
		assert !pending.children.any(it.id == 'software.health.repair' || it.id == 'software.health.reload')
		free_window_tree(pending)
		compact := app.build(ui2.rect(0, 0, 320, 240))!
		assert compact.children.any(it.id == 'software.health.stop'); free_window_tree(compact)
		if escape { app.key_input('\x1b') } else { app.handle('software.health.stop')! }
		assert app.health_mode && app.worker == unsafe { nil } && !app.health_ready && !app.progress_seen
		assert app.health_snapshot.rows.len == 0 && app.health_progress_packages == 0 && app.status.contains('Inspection stopped')
		assert C.kill(slow, 0) != 0
		app.handle('software.health.back')!
	}
	os.unsetenv('VINIX_SOFTWARE_HEALTH_MODE')
	app.handle('software.health')!; wait_for_software(mut app); assert app.health_ready
	app.handle('software.health.back')!
	os.setenv('VINIX_SOFTWARE_HEALTH_MODE', 'slow', true)
	app.handle('software.health')!; slow := app.worker.pid
	assert app.prepare_close(); app.close_app(); assert C.kill(slow, 0) != 0
	mut missing := SoftwareApp{ service_path: '/missing-package-health-service'.clone(), query: []u8{cap: 256}, output: []u8{cap: 8192} }
	missing.handle('software.health')!
	assert missing.health_mode && missing.worker == unsafe { nil } && missing.status.contains('package service is missing')
	missing.close_app()
	println('Software health: read-only asynchronous report, issue-first searchable metadata/diagnostics, issues-only filtering, stable visible selection, empty results, bounded Unicode editing, reload retention, compact Back, isolated catalog state, full-set repair review and safe close PASS')
	println('Software health progress: separate bounded stderr, live package names, both-pipe EOF, complete/exit/report/count admission, malformed/partial/late/flood refusal, Stop/Escape kill and reap, retry and compact cancellation PASS')
}

fn check_software_health_progress_memory() ! {
	$if !track_heap ? { return error('compile health progress memory fixture with -d track_heap') }
	$if track_heap ? {
		text := json2.encode(software_health_fixture())
		mut lines := [pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'verify' })]
		for row in software_health_fixture().rows { lines << pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'verify', package: row.id, repository: row.repository }) }
		lines << pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 })
		frames := lines.join('\n') + '\n'
		bad := pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'unknown', package: 'editor', repository: 'trusted' }) + '\n'
		oversized := 'x'.repeat(pkgprotocol.progress_limit + 1) + '\n'
		arguments := ['--json', '--progress', 'health']
		defer { unsafe { oversized.free(); (&array(&arguments)).free() } }
		mut app := SoftwareApp{ query: []u8{cap: 256}, output: []u8{cap: 8192} }
		unsafe { app.output.flags |= .noslices }
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.health_mode = true; app.worker_health = true; app.worker_failed = false
				metadata_fixture_output(mut app, text)
				app.health_progress_output(unsafe { tos(frames.str, 8) })
				app.health_progress_output(unsafe { tos(frames.str + 8, frames.len - 8) })
				app.finish_health_output(0)
				assert app.health_ready && app.health_progress_packages == 32 && app.progress_pending.len == 0
				free_window_tree(app.build_health(640, 610)); free_window_tree(app.build_health_compact(320, 240)); app.clear_health()
				app.worker_failed = false; app.health_progress_output(bad); app.finish_health_output(0)
				assert app.worker_failed && !app.health_ready && app.output.len < 8192
				app.capture_failure(arguments, 0)
				free_window_tree(app.build_health_compact(320, 240))
				app.clear_health()
				for phase in ['partial', 'complete', 'oversized']! {
					// Never start a process during allocation measurement. Functional
					// barriers exercise the real child/pipe/kill/reap lifecycle above.
					app.worker = os.new_process('/fixture-not-executed'.clone())
					app.health_mode = true; app.worker_health = true; app.worker_view = true; app.worker_failed = false
					metadata_fixture_output(mut app, text)
					app.health_progress_output(unsafe { tos(frames.str, 8) })
					if phase == 'complete' {
						app.health_progress_output(unsafe { tos(frames.str + 8, frames.len - 8) })
						assert app.status.contains('waiting for the service to exit') && !app.health_ready
					} else if phase == 'oversized' {
						app.health_progress_output(oversized)
						assert app.output_truncated && app.health_errors.len > 0
					}
					free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
					free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
					if phase == 'partial' { app.handle('software.health.stop')! }
					else if phase == 'complete' { app.key_input('\x1b') }
					else { app.handle('software.cancel')! }
					assert app.worker == unsafe { nil } && !app.worker_health && !app.health_ready && !app.progress_seen
					assert app.output.len == 0 && !app.output_truncated && app.progress_pending.len == 0 && app.health_errors.len == 0
					free_window_tree(app.build_health_compact(320, 240))
					app.clear_health()
				}
				app.clear_failure()
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'health progress retained ${kept} bytes'
		println('Software health progress: 1000 fragmented/report/admission/full/compact/failure/partial/complete/oversized/stop/descriptor-retirement cycles retain zero tracked bytes PASS')
	}
}

fn check_software_health_memory() ! {
	$if !track_heap ? { return error('compile health memory fixture with -d track_heap') }
	$if track_heap ? {
		text := json2.encode(software_health_fixture())
		mut app := SoftwareApp{ query: []u8{cap: 256}, output: text.bytes() }
		defer { app.close_app(); unsafe { text.free() } }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.health_mode = true; app.load_health()
				assert app.health_ready && app.health_matching[0] == 1
				software_search_paste_cycle(mut app)
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
				app.handle_health('software.row.1')
				app.handle_health('software.health.next')
				selected := app.health_selected; scroll := app.health_scroll; page := app.details_page
				free_window_tree(app.build_health_compact(320, 240))
				assert app.health_selected == selected && app.health_scroll == scroll && app.details_page == page
				free_window_tree(app.build_health(640, 610))
				app.handle_health('software.health.search')
				for query in ['APP-23', 'É🚀', 'COMPLETE DIAGNOSTIC', 'no matching row']! {
					app.health_key_input('\x01'); app.health_key_input('\x08'); app.health_paste_input(query)
					free_window_tree(app.build_health(640, 610))
				}
				assert app.health_selected == -1 && app.details_pages.len == 0
				app.handle_health('software.health.issues')
				free_window_tree(app.build_health_compact(320, 240))
				app.clear_health()
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'health views retained ${kept} bytes'
		println('Software health: 1000 decode/order/page/render/select/search/filter/empty/compact/retire cycles retain zero tracked bytes PASS')
	}
}
