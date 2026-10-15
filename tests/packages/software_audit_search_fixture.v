// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import tools.packages.pkgprotocol

fn software_audit_search_report(count int, matches bool) pkgprotocol.DeploymentAudit {
	mut rows := []pkgprotocol.DeploymentAuditRow{cap: count}
	for index in 0 .. count {
		status := if matches { 'match' } else if index == 2 { 'missing' }
			else if index == count / 2 { 'changed' } else if index == count - 1 { 'unexpected' } else { 'match' }
		number := (10000 + index).str()
		rows << pkgprotocol.DeploymentAuditRow{ id: 'app-' + number, status: status,
			expected_version: if status == 'unexpected' { '' } else if status == 'missing' { '1.2.3' } else { '1.0.0' },
			installed_version: if status == 'missing' { '' } else if status == 'changed' { '2.5.0' } else if status == 'unexpected' { '3.1.4' } else { '1.0.0' },
			differences: if status == 'changed' { ['architecture', 'metadata_sha256', 'public_key', 'repository', 'requested', 'sequence', 'version'] } else { []string{} } }
		unsafe { number.free() }
	}
	return pkgprotocol.DeploymentAudit{ generation: 7, architecture: 'aarch64', deployment_sha256: 'd'.repeat(64),
		matches: matches || count == 0, rows: rows }
}

fn software_audit_search_service_fixture(args []string) bool {
	if args.len != 4 || args[1..3] != ['--json', 'deployment-audit']
		|| args[3] !in ['/search-audit.json', '/search-empty.json', '/search-match.json'] { return false }
	mode := os.getenv('VINIX_SOFTWARE_AUDIT_SEARCH')
	if mode == 'invalid' { print('{"format":1}'); exit(3) }
	mut report := software_audit_search_report(if args[3] == '/search-empty.json' { 0 } else { 64 }, args[3] == '/search-match.json')
	text := json2.encode(report)
	defer { report.close(); unsafe { mode.free(); text.free() } }
	print(text[..17]); flush_stdout()
	if mode == 'held' { mut release := u8(0); assert C.read(0, &release, 1) == 1 }
	else { time.sleep(time.millisecond) }
	print(text[17..]); exit(if report.matches { 0 } else { 3 })
}

fn audit_fixture_query(mut app SoftwareApp, query string) ! {
	app.handle('software.audit.search')!
	app.key_input('\x01'); app.key_input('\x08')
	app.paste_input(query)
	assert if app.audit_query.len == 0 { query == '' } else { editor_bytes_text(app.audit_query) == query }
}

fn check_software_audit_search() ! {
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true,
		output: []u8{cap: 8192}, query: 'kept catalog query'.bytes(), filter: 2, selected: 5 }
	defer { app.close_app(); os.unsetenv('VINIX_SOFTWARE_AUDIT_SEARCH') }
	app.handle('software.deployment')!
	software_repository_text(mut app.deployment_path, '/search-audit.json')
	app.handle('software.deployment.audit')!
	app.handle('software.audit.search')!; app.handle('software.audit.differences')!; app.paste_input('blocked')
	assert app.audit_query.len == 0 && !app.audit_differences_only && !app.admin_prompt
	wait_for_software(mut app)
	assert app.audit_ready && app.audit_matching.len == 64 && app.audit_matching[..3] == [2, 32, 63]
	assert app.audit_selected == 2 && app.audit_results == 'Showing 64 of 64' && app.audit_summary.contains('3 differences')
	free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
	for query, expected in {'APP-10037': [37], 'MISSING': [2], 'CHANGED': [32], 'UNEXPECTED': [63],
		'1.2.3': [2], '2.5.0': [32], '3.1.4': [63], 'ARCHITECTURE': [32], 'METADATA_SHA256': [32],
		'PUBLIC_KEY': [32], 'REPOSITORY': [32], 'REQUESTED': [32], 'SEQUENCE': [32], 'VERSION': [32]} {
		audit_fixture_query(mut app, query)!
		assert app.audit_matching == expected && app.audit_selected == expected[0], query
	}
	audit_fixture_query(mut app, 'app-10037')!; audit_fixture_query(mut app, '')!
	assert app.audit_selected == 37 && app.audit_matching.len == 64
	position := app.audit_matching.index(37)
	assert position >= app.audit_scroll && position < app.audit_scroll + app.page_rows
	app.handle('software.audit.down')!
	away := app.audit_scroll
	free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
	assert app.audit_scroll == away, 'redraw must not undo deliberate paging'
	app.handle('software.row.1')!
	assert app.audit_selected == app.audit_matching[away + 1]
	free_window_tree(app.build(ui2.rect(0, 0, 900, 900))!)
	resized_position := app.audit_matching.index(app.audit_selected)
	assert resized_position >= app.audit_scroll && resized_position < app.audit_scroll + app.page_rows
	app.handle('software.audit.differences')!
	assert app.audit_differences_only && app.audit_matching == [2, 32, 63] && app.audit_selected == 2
	check_software_report_reader(mut app)!
	app.handle('software.row.1')!; assert app.audit_selected == 32
	app.handle('software.audit.next')!; assert app.details_page == 1
	audit_fixture_query(mut app, 'PUBLIC_KEY')!
	assert app.audit_selected == 32 && app.details_page == 1 && app.audit_results == 'Showing 1 of 64'
	app.handle('software.audit.reload')!
	assert !app.audit_ready && app.audit_matching.len == 0 && app.details_pages.len == 0 && app.audit_results == ''
	app.paste_input('blocked'); app.handle('software.audit.differences')!
	assert editor_bytes_text(app.audit_query) == 'PUBLIC_KEY' && app.audit_differences_only
	assert app.worker.args == ['--json', 'deployment-audit', '/search-audit.json']
	wait_for_software(mut app); assert app.audit_matching == [32]
	os.setenv('VINIX_SOFTWARE_AUDIT_SEARCH', 'invalid', true)
	app.handle('software.audit.reload')!; wait_for_software(mut app)
	assert !app.audit_ready && app.audit_matching.len == 0 && app.details_pages.len == 0
	assert app.audit_differences_only && editor_bytes_text(app.audit_query) == 'PUBLIC_KEY'
	os.unsetenv('VINIX_SOFTWARE_AUDIT_SEARCH')
	app.handle('software.audit.reload')!; wait_for_software(mut app); assert app.audit_matching == [32]
	os.setenv('VINIX_SOFTWARE_AUDIT_SEARCH', 'held', true)
	app.handle('software.audit.reload')!; pid := app.worker.pid
	for _ in 0 .. 500 { app.poll(); if app.output.len > 0 { break }; time.sleep(time.millisecond) }
	app.handle('software.audit.stop')!
	assert app.worker == unsafe { nil } && C.kill(pid, 0) != 0 && !app.audit_ready && app.audit_results == ''
	assert app.audit_differences_only && editor_bytes_text(app.audit_query) == 'PUBLIC_KEY'
	os.unsetenv('VINIX_SOFTWARE_AUDIT_SEARCH')
	app.handle('software.audit.reload')!; wait_for_software(mut app)
	audit_fixture_query(mut app, 'é🚀')!; app.key_input('\x08')
	assert editor_bytes_text(app.audit_query) == 'é'
	app.key_input('\x08'); assert app.audit_query.len == 0
	audit_fixture_query(mut app, 'kept')!
	app.key_input('\x01')
	for invalid in ['bad\x00query', 'bad\nquery', 'bad\x80', 'x'.repeat(257)] {
		app.paste_input(invalid); assert editor_bytes_text(app.audit_query) == 'kept' && app.audit_select_all
	}
	app.paste_input('é'.repeat(128)); assert app.audit_query.len == 256
	app.paste_input('🚀'); assert app.audit_query.len == 256
	app.key_input('\x08'); assert app.audit_query.len == 254
	app.key_input('\x1b'); assert app.audit_mode && !app.audit_focus
	app.key_input('unfocused'); app.paste_input('unfocused'); assert app.audit_query.len == 254
	audit_fixture_query(mut app, 'no such package')!
	assert app.audit_matching.len == 0 && app.audit_selected == -1 && app.audit_results == 'Showing 0 of 64'
	check_software_report_reader(mut app)!
	facts := app.details_pages.map(it.text).join('\n').replace('\n  ', '')
	assert facts.contains('Captured lock SHA-256:') && !facts.contains('Package: ')
	unsafe { facts.free() }
	tree := app.build(ui2.rect(0, 0, 640, 610))!
	assert tree.children.any(it.text == 'No packages match this search and filter.')
	assert !tree.children.any(it.id.starts_with('software.row.')) && tree.children.any(it.id == 'software.audit.review')
	free_window_tree(tree)
	app.handle('software.row.0')!; assert app.audit_selected == -1
	compact := app.build(ui2.rect(0, 0, 320, 240))!
	assert compact.children.any(it.text == 'Showing 0 of 64') && compact.children.any(it.id == 'software.audit.back')
	free_window_tree(compact)
	// Empty presentation results cannot narrow reconciliation or change source.
	software_repository_text(mut app.deployment_path, '/changed-form.json')
	app.handle('software.audit.review')!
	assert app.worker.args == ['deployment-review', '/search-audit.json'] && !app.admin_prompt && app.audit_query.len == 0
	assert !app.audit_differences_only && app.audit_matching.len == 0
	wait_for_software(mut app); assert app.review_ready && app.review_snapshot.rows.len == 2
	app.handle('software.cancel')!
	for path in ['/search-empty.json', '/search-match.json'] {
		software_repository_text(mut app.deployment_path, path)
		app.handle('software.deployment.audit')!; wait_for_software(mut app)
		app.handle('software.audit.differences')!
		assert app.audit_matching.len == 0 && app.audit_selected == -1 && app.audit_snapshot.matches
		assert app.details_pages.len > 0
		app.key_input('\x1b'); assert !app.audit_mode && app.audit_query.len == 0 && !app.audit_differences_only
	}
	assert app.query.bytestr() == 'kept catalog query' && app.selected == 5 && app.filter == 2
	// Exercise the protocol's maximum union without a presentation row cap.
	mut report := software_audit_search_report(8192, false)
	text := json2.encode(report); report.close()
	app.audit_mode = true; app.audit_path = '/wide-audit.json'.clone()
	app.output.clear(); for byte in text { app.output << byte }
	unsafe { text.free() }
	assert app.load_deployment_audit(3) && app.audit_matching.len == 8192
	app.handle('software.audit.differences')!; assert app.audit_matching == [2, 4096, 8191]
	audit_fixture_query(mut app, 'APP-18191')!; assert app.audit_selected == 8191 && app.audit_matching == [8191]
	println('Software deployment audit search: all 8192 rows, difference-first projection, IDs/status/versions/fields, stable selection/resize, bounded UTF-8 editing, reload/stop/error retention, empty results and full deployment review passed')
}

fn check_software_audit_search_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		mut report := software_audit_search_report(64, false)
		text := json2.encode(report); report.close()
		defer { unsafe { text.free() } }
		mut app := SoftwareApp{ output: []u8{cap: 32768} }
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.audit_mode = true; app.audit_path = software_audit_fixture_path.clone()
				app.output.clear(); for byte in text { app.output << byte }
				assert app.load_deployment_audit(3)
				report_reader_cycle(mut app)!
				software_search_paste_cycle(mut app)
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
				for query in ['APP-10037', '', 'PUBLIC_KEY', 'no matching package', 'é🚀']! {
					audit_fixture_query(mut app, query)!
					app.handle_deployment_audit('software.audit.differences')
					free_window_tree(app.build(ui2.rect(0, 0, 900, 660))!)
					free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				}
				app.handle_deployment_audit('software.audit.back')
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'deployment audit search retained ${kept} bytes'
		println('Software deployment audit search: 1000 decode/search/filter/select/empty/resize/render/retirement cycles retain zero tracked bytes')
	}
}
