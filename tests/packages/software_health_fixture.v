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
			name: 'Health é🚀 '.repeat(12), version: '1.0.0', kind: if index == 2 { 'runtime' } else { 'native' },
			repository: 'publisher-' + 'a'.repeat(110), public_key: 'a'.repeat(64),
			issue: match index { 1 { 'payload' } 2 { 'namespace' } 3 { 'registration' } else { '' } },
			diagnostic: if index in [1, 2, 3]! { 'A complete diagnostic é🚀 '.repeat(10) } else { '' } }
	}
	return pkgprotocol.HealthReport{ generation: 7, architecture: 'aarch64', rows: rows }
}

fn software_health_service_fixture(args []string) bool {
	if args.len != 3 || args[1..] != ['--json', 'health'] { return false }
	mode := os.getenv('VINIX_SOFTWARE_HEALTH_MODE')
	defer { unsafe { mode.free() } }
	if mode == 'failed' { eprintln('Installed state is unavailable; restore storage before retrying.'); exit(23) }
	if mode == 'slow' { time.sleep(3 * time.second) }
	text := json2.encode(software_health_fixture())
	defer { unsafe { text.free() } }
	println(match mode {
		'missing' { text.replace(',"diagnostic":""', '') }
		'duplicate' { text.replace('"generation":7', '"generation":7,"generat\\u0069on":7') }
		'type' { text.replace('"issue":"payload"', '"issue":true') }
		'trailing' { text + '{}' }
		else { text }
	})
	return true
}

fn check_software_health() ! {
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true,
		query: []u8{cap: 256}, output: []u8{cap: 8192}, matching: [0], selected: 0, filter: 1,
		catalog_error: 'catalog unavailable'.clone(), rows: [SoftwareRow{ id: 'editor', name: 'Editor', installed_version: '1.0.0' }] }
	defer { os.unsetenv('VINIX_SOFTWARE_HEALTH_MODE'); app.close_app() }
	tree := app.build(ui2.rect(0, 0, 640, 610))!
	assert tree.children.any(it.id == 'software.health' && it.text == 'Health report'); free_window_tree(tree)
	app.handle('software.health')!
	assert app.health_mode && app.worker_health && app.worker_view && !app.admin_prompt && app.prepare_close()
	assert app.worker.args == ['--json', 'health']
	pid := app.worker.pid; app.handle('software.health')!; assert app.worker.pid == pid
	wait_for_software(mut app)
	assert app.health_ready && app.health_snapshot.rows.len == 32 && app.health_summary.contains('3 with issues')
	assert app.health_matching[..4] == [1, 2, 3, 0] && app.health_selected == 1
	assert 'Installed publisher key: ' + 'a'.repeat(64) in details_fixture_values(&app, 0)
	assert 'Diagnostic: ' + 'A complete diagnostic é🚀 '.repeat(10) in details_fixture_values(&app, 0)
	assert app.details_pages.len > 1 && !app.details_mode
	for _ in 0 .. app.details_pages.len + 2 { app.handle('software.health.next')! }
	assert app.details_page == app.details_pages.len - 1
	health := app.build(ui2.rect(0, 0, 640, 610))!
	assert health.children.any(it.id == 'software.health.repair') && !health.children.any(it.id == 'software.confirm')
	free_window_tree(health)
	for hidden in ['software.confirm', 'software.install', 'software.repair', 'software.upgrade', 'software.verify', packagecore.request_prefix + '{"id":"editor"}'] {
		app.handle(hidden)!; assert app.health_mode && app.worker == unsafe { nil } && app.review == '' && app.launch_request == ''
	}
	app.key_input('changed'); app.paste_input('changed'); assert app.query.len == 0
	app.handle('software.health.down')!; assert app.health_scroll > 0
	app.handle('software.row.0')!; assert app.health_selected == app.health_matching[app.health_scroll] && app.details_page == 0
	app.handle('software.health.back')!
	assert !app.health_mode && app.health_snapshot.rows.len == 0 && app.selected == 0 && app.filter == 1 && app.catalog_error == 'catalog unavailable'
	for mode in ['missing', 'duplicate', 'type', 'trailing', 'failed'] {
		os.setenv('VINIX_SOFTWARE_HEALTH_MODE', mode, true)
		app.handle('software.health')!; wait_for_software(mut app)
		assert app.health_mode && !app.health_ready && app.health_snapshot.rows.len == 0
		assert !app.build(ui2.rect(0, 0, 640, 610))!.children.any(it.id == 'software.health.repair')
		app.handle('software.health.repair')!; assert app.worker == unsafe { nil } && app.review == ''
		app.handle('software.health.back')!
	}
	os.unsetenv('VINIX_SOFTWARE_HEALTH_MODE')
	app.handle('software.health')!; wait_for_software(mut app)
	app.handle('software.health.repair')!
	assert !app.health_mode && app.health_snapshot.rows.len == 0 && app.worker.args == ['review', 'repair'] && !app.admin_prompt
	wait_for_software(mut app); assert app.review_ready; app.handle('software.cancel')!
	os.setenv('VINIX_SOFTWARE_HEALTH_MODE', 'slow', true)
	app.handle('software.health')!; slow := app.worker.pid
	assert app.prepare_close(); app.close_app(); assert C.kill(slow, 0) != 0
	mut missing := SoftwareApp{ service_path: '/missing-package-health-service'.clone(), query: []u8{cap: 256}, output: []u8{cap: 8192} }
	missing.handle('software.health')!
	assert missing.health_mode && missing.worker == unsafe { nil } && missing.status.contains('package service is missing')
	missing.close_app()
	println('Software health: read-only asynchronous report, issue-first inventory, full paged provenance/diagnostics, navigation, modal isolation, invalid/failing response refusal, fresh repair review and safe close PASS')
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
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
				app.handle_health('software.row.1')
				app.handle_health('software.health.next')
				free_window_tree(app.build_health(640, 610))
				app.clear_health()
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'health views retained ${kept} bytes'
		println('Software health: 1000 decode/order/prepare/paged-render/select/retire cycles retain zero tracked bytes PASS')
	}
}
