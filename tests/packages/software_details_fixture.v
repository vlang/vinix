// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8
import json2
import os
import ui2
import desktop.packagecore
import tools.packages.pkgprotocol

fn details_fixture_row() SoftwareRow {
	return SoftwareRow{ id: 'org.' + 'a'.repeat(120), name: 'Long name é🚀 '.repeat(14),
		description: 'A complete description é🚀 '.repeat(120), version: '2.0.0', installed_version: '1.0.0',
		installed_name: 'Installed application', installed_kind: 'native', installed_permissions: ['display', 'files'], installed_window_protocol: 2,
		architecture: 'aarch64', kind: 'linux', runtime: 'runtime-' + 'a'.repeat(110), repository: 'publisher-' + 'b'.repeat(110),
		public_key: 'a'.repeat(64), license: 'Vendor license é '.repeat(12), proprietary: true, firmware: true,
		permissions: ['files', 'network', 'process'], requested: true, updatable: true, update_action: 'update', diagnostic: 'Denied:\n' + 'long é🚀 reason '.repeat(160) }
}

// Reconstruct displayed values across page boundaries, stripping only the
// renderer's bullet/continuation prefixes. This checks full disclosure.
fn details_fixture_values(app &SoftwareApp, section int) []string {
	mut values := []string{}
	mut current := []u8{}
	for page in app.details_pages {
		assert utf8.validate_str(page.text)
		lines := page.text.split('\n')
		assert lines.len <= 14
		for line in lines {
			assert line.len <= 52
			if page.section != section { continue }
			if line.starts_with('• ') {
				if current.len > 0 { values << current.bytestr(); current.clear() }
				for index in 4 .. line.len { current << line[index] }
			} else {
				assert line.starts_with('  ')
				for index in 2 .. line.len { current << line[index] }
			}
		}
	}
	if current.len > 0 { values << current.bytestr() }
	return values
}

fn check_software_details() ! {
	row := details_fixture_row()
	mut app := SoftwareApp{ rows: [row], matching: [0], selected: 0, query: []u8{cap: 256}, output: []u8{cap: 8192},
		catalog_error: 'Catalog error é🚀 '.repeat(100), update_error: 'Update error é🚀 '.repeat(100) }
	defer { app.close_app() }
	tree := app.build(ui2.rect(0, 0, 640, 610))!
	assert tree.children.any(it.id == 'software.details')
	for element in tree.children {
		if element.id.starts_with('software.row.') { assert element.frame.y + element.frame.height <= 434 }
	}
	free_window_tree(tree)
	app.handle('software.details')!
	assert app.details_mode && !app.details_review && app.worker == unsafe { nil } && app.prepare_close()
	assert details_fixture_values(&app, 1) == [row.description]
	assert 'Publisher key: ' + row.public_key in details_fixture_values(&app, 2)
	assert 'Displayed package repository: ' + row.repository in details_fixture_values(&app, 2)
	assert 'License: ' + row.license in details_fixture_values(&app, 4)
	assert 'Proprietary payload: Yes' in details_fixture_values(&app, 4) && 'Firmware payload: Yes' in details_fixture_values(&app, 4)
	assert 'Installed native-window protocol: 2' in details_fixture_values(&app, 0)
	assert 'Displayed package permission: network' in details_fixture_values(&app, 3)
	assert 'Installed permission: display' in details_fixture_values(&app, 3)
	assert 'Installed permission: network' !in details_fixture_values(&app, 3)
	assert 'Package diagnostic: Denied:\\x0a' + 'long é🚀 reason '.repeat(160) in details_fixture_values(&app, 5)
	assert 'Catalog diagnostic: ' + app.catalog_error in details_fixture_values(&app, 5)
	assert 'Update diagnostic: ' + app.update_error in details_fixture_values(&app, 5)
	for hidden in ['software.confirm', 'software.cancel', 'software.row.1', 'software.reload', 'software.install', 'software.run', 'software.policy', 'software.data', 'software.search'] {
		app.handle(hidden)!
		assert app.details_mode && app.selected == 0 && app.worker == unsafe { nil }
	}
	app.handle(packagecore.request_prefix + '{"id":"other"}')!
	app.key_input('\x01'); app.paste_input('changed')
	assert app.launch_request == '' && app.query.len == 0
	app.handle('software.details.description')!
	first := app.details_page
	app.handle('software.details.previous')!; assert app.details_page == first
	app.handle('software.details.next')!; assert app.details_page > first
	for _ in 0 .. app.details_pages.len { app.handle('software.details.next')! }
	last := app.details_page; app.handle('software.details.next')!; assert app.details_page == last
	app.handle('software.details.previous')!; assert app.details_page < last
	details := app.build(ui2.rect(0, 0, 640, 610))!
	assert details.children.any(it.id == 'software.details.back') && !details.children.any(it.id == 'software.confirm')
	free_window_tree(details)
	app.handle('software.details.back')!
	assert !app.details_mode && app.details_pages.len == 0 && app.selected == 0
	for operation in ['install', 'remove', 'upgrade', 'deploy', 'rollback', 'mirror'] {
		app.review = operation.clone()
		base := fixture_review(operation, if operation in ['upgrade', 'rollback'] { []string{} } else { ['editor'] })
		snapshot := if operation == 'mirror' { pkgprotocol.Review{ ...base, generation: 0, rows: base.rows.map(pkgprotocol.ReviewPackage{ ...it, action: 'export' }) } }
			else if operation == 'remove' { pkgprotocol.Review{ ...base, requested: [], rows: base.rows.map(pkgprotocol.ReviewPackage{ ...it, requested: false, action: 'remove' }) } }
			else { base }
		app.review_snapshot = pkgprotocol.decode_review(json2.encode(snapshot))!
		app.review_ready = true; app.review_selected = 1; app.review_scroll = 1
		if operation == 'deploy' { app.deployment_pending = '/company/' + 'approved é🚀 '.repeat(160) + '.json' }
		app.handle('software.details')!
		assert app.details_mode && app.details_review
		assert 'Package ID: runtime' in details_fixture_values(&app, 0)
		if operation == 'rollback' { assert 'Restore from generation: 2' in details_fixture_values(&app, 0) }
		assert 'License: Vendor-EULA' in details_fixture_values(&app, 4)
		if operation == 'deploy' { assert 'Deployment file: ' + app.deployment_pending in details_fixture_values(&app, 5) }
		for hidden in ['software.confirm', 'software.cancel', 'software.row.0', 'software.reload'] { app.handle(hidden)! }
		assert app.review_ready && app.review_selected == 1 && app.review_scroll == 1 && app.worker == unsafe { nil }
		app.handle('software.details.back')!
		assert app.review_ready && app.review_selected == 1 && app.review_snapshot.operation == operation
		app.clear_review()
	}
	app.open_details(); app.key_input('\x1b')
	assert !app.details_mode && app.details_pages.len == 0
	// Reload/retirement invalidates pages without retaining the source row.
	app.open_details(); app.clear_review()
	assert !app.details_mode && app.details_pages.len == 0
	// Old service views can lack installed launch fields. Avoid inventing grants.
	app.rows[0] = SoftwareRow{ ...row, installed_kind: '', installed_permissions: [], installed_window_protocol: 0 }
	app.open_details()
	assert 'Installed permissions: Unavailable from this service' in details_fixture_values(&app, 3)
	app.clear_details()
	for bad in [SoftwareRow{ ...row, description: '\xff' }, SoftwareRow{ ...row, description: 'x'.repeat(4097) }, SoftwareRow{ ...row, installed_window_protocol: 3 }] {
		app.rows[0] = bad; app.open_details()
		assert !app.details_mode && app.details_pages.len == 0 && app.status.contains('supported text limits')
	}
	app.rows[0] = row
	app.open_details(); assert app.details_mode
	app.service_path = os.executable()
	app.start(['view'], true)
	assert !app.details_mode && app.details_pages.len == 0
	wait_for_software(mut app)
	assert !app.details_mode && app.selected == -1
	println('Software package details: complete Unicode descriptions/provenance/licenses/diagnostics, installed versus displayed permissions, paging, frozen review, hidden-action refusal, legacy fields and invalid-text refusal passed')
}

fn check_software_details_memory() ! {
	$if !track_heap ? { return error('compile details memory fixture with -d track_heap') }
	$if track_heap ? {
		row := details_fixture_row()
		mut app := SoftwareApp{ rows: [row], selected: 0, catalog_error: '\n'.repeat(4096) }
		review_text := json2.encode(fixture_review('upgrade', []))
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.open_details(); assert app.details_mode && app.details_pages.len > 32
				for section, action in software_details_actions {
					app.handle_details(action)
					free_window_tree(app.build_details(640, 610))
					app.handle_details('software.details.next')
					assert app.details_section == section
				}
				app.handle_details('software.details.back')
				app.review = 'upgrade'.clone()
				app.review_snapshot = pkgprotocol.decode_review(review_text)!
				app.review_ready = true; app.review_selected = 1
				app.open_details(); assert app.details_mode && app.details_review
				free_window_tree(app.build_details(640, 610))
				app.clear_review()
			}
		}
		kept := C.vinix_heap_end()
		app.close_app()
		unsafe { review_text.free() }
		assert kept == 0, 'details pages retained ${kept} bytes'
		println('Software package details: 1000 catalog/review/open/growing-UTF-8-page/redraw/navigate/back/retire cycles retain zero tracked bytes')
	}
}
