// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import tools.packages.pkgprotocol

const software_audit_fixture_path = '/private/tmp/部署 with spaces; $literal.json'

fn software_audit_fixture_report(matches bool, count int) pkgprotocol.DeploymentAudit {
	mut rows := []pkgprotocol.DeploymentAuditRow{cap: count}
	for index in 0 .. count {
		status := if matches || index > 2 { 'match' } else if index == 0 { 'changed' } else if index == 1 { 'missing' } else { 'unexpected' }
		rows << pkgprotocol.DeploymentAuditRow{ id: 'app-' + (10000 + index).str(), status: status,
			expected_version: if status == 'unexpected' { '' } else { '1.0.0' },
			installed_version: if status == 'missing' { '' } else if status == 'changed' { '2.0.0' } else { '1.0.0' },
			differences: if status == 'changed' { ['metadata_sha256', 'public_key', 'repository', 'requested', 'sequence', 'version'] } else { []string{} } }
	}
	return pkgprotocol.DeploymentAudit{ generation: 7, architecture: 'aarch64', deployment_sha256: 'd'.repeat(64), matches: matches, rows: rows }
}

fn software_audit_service_fixture(args []string) bool {
	if args.len < 3 || args[1] != '--json' || args[2] != 'deployment-audit' { return false }
	assert args.len == 4 && os.args[1] == '--json'
	path := args[3]
	if path == '/error-audit.json' { eprintln('fixture: deployment file is unreadable'); exit(1) }
	if path == '/huge-audit.json' { print('x'.repeat(software_output_limit + 32)); return true }
	matches := path in ['/match-audit.json', '/empty-audit.json']
	text := json2.encode(software_audit_fixture_report(matches, if path == '/empty-audit.json' { 0 } else { 31 }))
	if path == '/bad-audit.json' { print(text.replace('"format":1', '"format":2')); exit(3) }
	if path == '/partial-audit.json' { print(text[..text.len / 2]); exit(3) }
	if path == '/wrong-exit-audit.json' { print(text); return true }
	if path == '/slow-audit.json' {
		print(text[..text.len / 2]); flush_stdout(); time.sleep(2 * time.second)
		print(text[text.len / 2..]); exit(3)
	}
	if path == '/failed-audit.json' { print(text); exit(23) }
	// A split write must be buffered as one complete document, without the
	// ordinary operation-output tail dropping rows or interpreting exit 3.
	print(text[..17]); flush_stdout(); time.sleep(time.millisecond)
	print(text[17..]); exit(if matches { 0 } else { 3 })
}

fn check_software_audit() ! {
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true,
		output: []u8{cap: 8192}, query: []u8{cap: 256}, selected: 5, filter: 1 }
	defer { app.close_app() }
	app.query << 'kept search'.bytes()
	app.handle('software.deployment')!
	form := app.build(ui2.rect(0, 0, 640, 610))!
	assert form.children.any(it.id == 'software.deployment.audit')
	app.handle('software.deployment.audit')!
	assert !app.audit_mode && app.worker == unsafe { nil } && app.status.contains('absolute')
	software_repository_text(mut app.deployment_path, software_audit_fixture_path)
	app.handle('software.deployment.audit')!
	assert app.audit_mode && app.worker_audit && app.prepare_close() && !app.admin_prompt
	assert app.worker.args == ['--json', 'deployment-audit', software_audit_fixture_path]
	app.handle('software.confirm')!
	assert !app.audit_ready && app.review == ''
	app.paste_input('/other.json')
	assert editor_bytes_text(app.deployment_path) == software_audit_fixture_path
	software_repository_text(mut app.deployment_path, '/form-changed.json')
	wait_for_software(mut app)
	assert app.audit_ready && !app.audit_snapshot.matches && app.audit_snapshot.rows.len == 31
	assert app.audit_path == software_audit_fixture_path && app.failure_pages.len == 0
	assert app.audit_summary.contains('3 differences') && app.details_pages.len >= 2
	check_software_report_reader(mut app)!
	check_report_return_selection(mut app)!
	mut facts := app.details_pages.map(it.text).join('\n').replace('\n  ', '')
	assert facts.contains('Changed field: public_key') && facts.contains('below the lock minimum') && facts.contains('SHA-256')
	unsafe { facts.free() }
	wide := app.build(ui2.rect(0, 0, 900, 660))!
	assert wide.children.any(it.id == 'software.audit.review') && wide.children.any(it.text.contains('changed: app-10000'))
	app.handle('software.audit.next')!; assert app.details_page == 1
	app.handle('software.audit.previous')!; assert app.details_page == 0
	app.handle('software.audit.down')!; assert app.audit_scroll == app.page_rows
	app.handle('software.row.1')!; assert app.audit_selected == app.audit_scroll + 1
	app.handle('software.audit.up')!; assert app.audit_scroll == 0
	app.handle('software.audit.reload')!
	assert !app.audit_ready && app.audit_snapshot.rows.len == 0 && app.details_pages.len == 0
	assert app.worker.args[2] == software_audit_fixture_path
	wait_for_software(mut app)
	// Reconciliation obtains a new service review of the captured source, even
	// when the editable form was changed during the audit.
	app.handle('software.audit.review')!
	assert !app.audit_mode && app.audit_path == '' && app.deployment_pending == software_audit_fixture_path
	assert app.worker.args == ['deployment-review', software_audit_fixture_path] && !app.admin_prompt
	wait_for_software(mut app)
	assert app.review_ready && app.review_snapshot.operation == 'deploy'
	app.handle('software.cancel')!
	assert app.query.bytestr() == 'kept search' && app.selected == 5 && app.filter == 1
	for path in ['/match-audit.json', '/empty-audit.json', '/bad-audit.json', '/partial-audit.json', '/wrong-exit-audit.json', '/error-audit.json', '/failed-audit.json', '/huge-audit.json'] {
		software_repository_text(mut app.deployment_path, path)
		app.handle('software.deployment.audit')!
		wait_for_software(mut app)
		if path in ['/match-audit.json', '/empty-audit.json'] {
			assert app.audit_ready && app.audit_snapshot.matches
			check_software_report_reader(mut app)!
		} else {
			assert !app.audit_ready && app.audit_snapshot.rows.len == 0 && app.failure_pages.len > 0
			if path == '/wrong-exit-audit.json' { assert app.status.contains('disagrees') }
			if path == '/error-audit.json' { assert app.status.contains('unreadable') }
			app.handle('software.failure')!; assert app.failure_mode
			app.key_input('\x1b'); assert !app.failure_mode && app.audit_mode
		}
		compact := app.build(ui2.rect(0, 0, 480, 340))!
		assert compact.children.any(it.id == 'software.audit.back')
		app.handle('software.audit.back')!
		assert !app.audit_mode && app.deployment_mode && app.audit_path == ''
	}
	software_repository_text(mut app.deployment_path, '/slow-audit.json')
	app.handle('software.deployment.audit')!
	for _ in 0 .. 100 { app.poll(); if app.output.len > 0 { break }; time.sleep(time.millisecond) }
	assert app.worker != unsafe { nil } && !app.audit_ready
	app.handle('software.report.read')!; assert !app.report_reader_mode
	compact := app.build(ui2.rect(0, 0, 480, 340))!
	assert compact.children.any(it.id == 'software.audit.stop')
	app.handle('software.audit.review')!; assert app.worker_audit && app.review == ''
	app.handle('software.audit.stop')!
	assert app.worker == unsafe { nil } && !app.audit_ready && app.output.len == 0 && app.status.contains('stopped')
	app.key_input('\x1b'); assert !app.audit_mode && app.deployment_mode
	println('Software deployment audit: literal ordinary argv, exit 0/3 coherence, complete drift rows, details/paging, frozen reload/review, cancellation, failure diagnostics, bounds and compact navigation passed')
}

fn check_software_audit_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		text := json2.encode(software_audit_fixture_report(false, 31))
		mut app := SoftwareApp{ deployment_mode: true, output: []u8{cap: 8192} }
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.audit_mode = true; app.audit_path = software_audit_fixture_path.clone()
				app.output.clear(); for byte in text { app.output << byte }
				assert app.load_deployment_audit(3)
				report_reader_cycle(mut app)!
				tree := app.build(ui2.rect(0, 0, 900, 660))!
				free_window_tree(tree)
				app.handle_deployment_audit('software.audit.next')
				app.handle_deployment_audit('software.row.1')
				app.handle_deployment_audit('software.audit.down')
				app.handle_deployment_audit('software.audit.back')
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'deployment audit UI retained ${kept} bytes'
		println('Software deployment audit: 1000 complete decode, detail, render, paging and retirement cycles retain zero tracked bytes')
		println('Software report reader: 1000 decode/short-pages/package-steps/resize/back/cache-retirement cycles retain zero tracked bytes')
	}
}
