// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8
import json2
import os
import ui2
import desktop.packagecore
import tools.packages.pkgprotocol

// Read the labels the native renderer actually draws, not the container's
// complete accessibility/ownership text. All line slices must borrow that text.
fn software_paragraph_fixture_text(element &ui2.Element, truncated bool) string {
	assert element.kind == .view && element.accessibility_label == element.text
	mut bytes := []u8{cap: element.text.len}
	defer { unsafe { bytes.free() } }
	mut ellipsis := false
	mut row := 0
	for child in element.children {
		assert child.kind == .label && child.text_style.lines == 1 && child.text_style.font_family == 'mono'
		assert child.id == '' && child.key == '' && child.children.len == 0
		assert !child.text.contains('\n') && utf8.validate_str(child.text)
		assert child.frame.height == 18 && child.frame.y + 18 <= element.frame.height
		if child.text == '…' && child.frame.x != 0 {
			assert truncated && child.frame.y == (row - 1) * 18, 'Unexpected truncation: ${element.text}'
			ellipsis = true
			continue
		}
		assert child.frame.x == 0 && child.frame.y == row * 18 && child.frame.width == element.frame.width
		assert child.text.len <= int(element.frame.width) / 8
		if child.text.len > 0 {
			assert usize(child.text.str) >= usize(element.text.str)
			assert usize(child.text.str) + usize(child.text.len) <= usize(element.text.str) + usize(element.text.len)
		}
		for byte in child.text { bytes << byte }
		row++
	}
	assert ellipsis == truncated
	return bytes.bytestr()
}

fn software_paragraph_fixture_check(tree &ui2.Element, prefix string) {
	for element in tree.children {
		if !element.text.starts_with(prefix) { continue }
		text := software_paragraph_fixture_text(&element, false)
		expected := element.text.replace('\n', '')
		defer { unsafe { text.free(); expected.free() } }
		assert text == expected
		return
	}
	assert false, 'missing paragraph: ${prefix}'
}

fn check_software_paragraphs() ! {
	for text in ['first line\n\nsecond line\n', 'Words wrap at spaces; identifiers-continue-without-spaces.',
		'é🚀界 '.repeat(12), 'file:///offline/' + 'x'.repeat(80)] {
		label := software_label(text, 14, 46, 96, 400, false)
		rendered := software_paragraph_fixture_text(&label, false)
		expected := text.replace('\n', '')
		assert rendered == expected
		unsafe { rendered.free(); expected.free() }
		free_window_tree(label)
	}
	overflow := software_label('Long diagnostic é🚀 '.repeat(40), 14, 46, 96, 54, true)
	shown := software_paragraph_fixture_text(&overflow, true)
	assert overflow.text.starts_with(shown) && shown.len < overflow.text.len
	unsafe { shown.free() }; free_window_tree(overflow)
	short := software_label('Heading', 14, 8, 120, 28, false)
	assert short.kind == .label && short.children.len == 0 && short.text_style.font_family == ''
	free_window_tree(short)
	mut app := SoftwareApp{ administration_required: true, output: []u8{cap: 8192}, query: []u8{cap: 256},
		status: 'Enter your own administrator password to approve this package change.'.clone() }
	defer { app.close_app() }
	app.admin_prompt = true
	for size in [ui2.rect(0, 0, 320, 280), ui2.rect(0, 0, 640, 610)]! {
		tree := app.build(size)!
		software_paragraph_fixture_check(&tree, 'This package change needs an administrator.')
		software_paragraph_fixture_check(&tree, app.status)
		for element in tree.children {
			if element.text != app.status { continue }
			assert element.frame.y >= 218 && element.frame.y + element.frame.height <= size.height - 8
		}
		free_window_tree(tree)
	}
	app.clear_admin_prompt(); app.cleanup_mode = true
	cleanup := app.build(ui2.rect(0, 0, 640, 610))!
	software_paragraph_fixture_check(&cleanup, 'Deletion is permanent')
	free_window_tree(cleanup); app.cleanup_mode = false
	app.data_mode = true; app.data_pending = 'removed-app'.clone()
	data := app.build(ui2.rect(0, 0, 640, 610))!
	software_paragraph_fixture_check(&data, 'Only this signed-in account')
	software_paragraph_fixture_check(&data, 'This cannot be undone.')
	assert data.children.any(it.id == 'software.data.confirm')
	free_window_tree(data); app.clear_personal_data()
	app.data_mode = true; app.data_ready = true; app.data_status = fixture_personal_data_status(); app.data_selected = 1
	data_row := app.build(ui2.rect(0, 0, 640, 610))!
	software_paragraph_fixture_check(&data_row, 'Location: ~/.local/share/vinix-apps/ID')
	free_window_tree(data_row); app.clear_personal_data(); app.data_mode = false
	app.repository_mode = true
	repository := app.build(ui2.rect(0, 0, 640, 610))!
	software_paragraph_fixture_check(&repository, 'Obtain the publisher key')
	free_window_tree(repository); app.repository_mode = false
	app.launch_mode = true
	for private_data in [false, true]! {
		app.launch_data_cwd = private_data
		launch := app.build(ui2.rect(0, 0, 640, 610))!
		software_paragraph_fixture_check(&launch, 'Quotes group values')
		software_paragraph_fixture_check(&launch, if private_data { 'Relative output files' } else { 'Installed files are read-only.' })
		software_paragraph_fixture_check(&launch, 'This application has no document-file permission.')
		free_window_tree(launch)
	}
	app.launch_mode = false
	app.snapshot_mode = true
	snapshot := app.build(ui2.rect(0, 0, 640, 610))!
	software_paragraph_fixture_check(&snapshot, 'Save all installed applications')
	software_paragraph_fixture_check(&snapshot, 'This saves metadata')
	free_window_tree(snapshot); app.snapshot_mode = false
	app.deployment_mode = true
	deployment := app.build(ui2.rect(0, 0, 640, 610))!
	software_paragraph_fixture_check(&deployment, 'Use a deployment file supplied by your organization.')
	software_paragraph_fixture_check(&deployment, 'The review includes installs')
	free_window_tree(deployment); app.deployment_mode = false
	app.mirror_mode = true
	mirror := app.build(ui2.rect(0, 0, 640, 610))!
	software_paragraph_fixture_check(&mirror, 'Exports current authenticated catalog versions')
	free_window_tree(mirror); app.mirror_mode = false
	app.rows = [SoftwareRow{ id: 'editor', name: 'Editor', public_key: 'a'.repeat(64), permissions: ['files', 'network'] }]
	app.matching = [0]; app.selected = 0
	catalog := app.build(ui2.rect(0, 0, 640, 610))!
	software_paragraph_fixture_check(&catalog, 'Publisher key: ')
	software_paragraph_fixture_check(&catalog, 'Permissions: ')
	free_window_tree(catalog)
	assert app.worker == unsafe { nil } && !app.admin_prompt
	println('Software paragraphs: complete minimum-size destructive/trust/restore/launch warnings, keys and permissions, explicit newlines, UTF-8 wrapping, overflow marks, borrowed lines and unobscured administrator controls PASS')
}

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

fn details_fixture_rendered_lines(tree &ui2.Element, text string, x int, y int, width int, line_height int, byte_limit int) {
	mut lines := text.split('\n')
	defer { software_policy_free_lines(mut lines) }
	assert lines.len <= 14
	mut row := 0
	for element in tree.children {
		if element.text_style.font_family != 'mono' { continue }
		assert row < lines.len && element.text == lines[row] && !element.text.contains('\n')
		assert utf8.validate_str(element.text) && element.text.len <= byte_limit
		assert element.frame.x == x && element.frame.y == y + row * line_height
		assert element.frame.width == width && element.frame.height == line_height
		assert element.text_style.lines == 1 && element.key == ''
		row++
	}
	assert row == lines.len && row > 0
}

fn details_fixture_check_all_pages(mut app SoftwareApp) ! {
	page := app.details_page; section := app.details_section
	for index, value in app.details_pages {
		app.details_page = index; app.details_section = value.section
		for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 900, 660)]! {
			tree := app.build(size)!
			details_fixture_rendered_lines(&tree, value.text, 14, 174, int(size.width) - 28, 20, 52)
			assert !tree.children.any(it.id == 'software.confirm')
			for element in tree.children {
				assert element.frame.y >= 0 && element.frame.y + element.frame.height <= size.height
			}
			free_window_tree(tree)
			assert app.details_page == index && app.details_section == value.section && app.worker == unsafe { nil }
		}
	}
	app.details_page = page; app.details_section = section
}

fn check_software_report_page_lines() ! {
	mut app := SoftwareApp{ output: []u8{cap: 8192}, query: []u8{cap: 256} }
	unsafe { app.output.flags |= .noslices }
	defer { app.close_app() }
	health := json2.encode(software_health_fixture())
	defer { unsafe { health.free() } }
	metadata_fixture_output(mut app, health); app.health_mode = true; assert app.load_health()
	for index, page in app.details_pages {
		app.details_page = index
		tree := app.build(ui2.rect(0, 0, 640, 610))!
		details_fixture_rendered_lines(&tree, page.text, 274, 128, 352, 18, 28)
		assert tree.children.any(it.id == 'software.health.repair')
		free_window_tree(tree)
	}
	assert app.health_ready && app.health_selected == 1 && app.health_snapshot.rows.len == 32
	app.clear_health()
	audit := json2.encode(software_audit_fixture_report(false, 31))
	defer { unsafe { audit.free() } }
	metadata_fixture_output(mut app, audit); app.audit_mode = true
	app.audit_path = software_snapshot_fixture_path.clone(); assert app.load_deployment_audit(3)
	for index, page in app.details_pages {
		app.details_page = index
		tree := app.build(ui2.rect(0, 0, 640, 610))!
		details_fixture_rendered_lines(&tree, page.text, 274, 128, 352, 18, 28)
		assert tree.children.any(it.id == 'software.audit.review')
		free_window_tree(tree)
	}
	assert app.audit_ready && app.audit_snapshot.rows.len == 31 && app.audit_selected == 0
	app.clear_deployment_audit()
	saved := json2.encode(software_snapshot_fixture_receipt(software_snapshot_fixture_path))
	defer { unsafe { saved.free() } }
	metadata_fixture_output(mut app, saved); app.snapshot_mode = true
	app.snapshot_pending = software_snapshot_fixture_path.clone(); assert app.load_deployment_snapshot()
	for index, page in app.details_pages {
		app.details_page = index
		tree := app.build(ui2.rect(0, 0, 640, 610))!
		details_fixture_rendered_lines(&tree, page.text, 14, 94, 612, 20, 52)
		assert tree.children.any(it.id == 'software.snapshot.export')
		free_window_tree(tree)
	}
	assert app.snapshot_saved.destination == software_snapshot_fixture_path && app.snapshot_ready
	app.clear_deployment_snapshot()
	policy := json2.encode(fixture_policy_document()); review := json2.encode(fixture_policy_review())
	defer { unsafe { policy.free(); review.free() } }
	app.policy_mode = true; metadata_fixture_output(mut app, policy); app.load_policy_document(); assert app.policy_ready
	for reviewing in [false, true]! {
		if reviewing {
			app.policy_pending = policy_fixture_path.clone(); metadata_fixture_output(mut app, review); app.load_policy_review()
			assert app.policy_review_ready
		}
		for index, page in app.policy_pages {
			app.policy_page = index; app.policy_section = page.section
			tree := app.build(ui2.rect(0, 0, 640, 610))!
			details_fixture_rendered_lines(&tree, page.text, 14, 174, 612, 20, 52)
			assert tree.children.any(it.id == 'software.policy.confirm') == reviewing
			free_window_tree(tree)
		}
	}
	assert app.policy_ready && app.policy_review_ready && app.policy_snapshot.fingerprint == 'c'.repeat(64)
	assert app.worker == unsafe { nil } && !app.admin_prompt
	println('Software disclosure lines: complete catalog/review/health/audit/snapshot/policy pages, individual native-renderer labels, narrow UTF-8 columns, geometry and unchanged review state PASS')
}

fn check_software_details() ! {
	check_software_paragraphs()!
	check_software_report_page_lines()!
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
	details_fixture_check_all_pages(mut app)!
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
	for operation in ['install', 'remove', 'upgrade', 'repair', 'deploy', 'rollback', 'mirror'] {
		app.review = operation.clone()
		base := fixture_review(operation, if operation in ['upgrade', 'repair', 'rollback'] { []string{} } else { ['editor'] })
		snapshot := if operation == 'mirror' { pkgprotocol.Review{ ...base, generation: 0, rows: base.rows.map(pkgprotocol.ReviewPackage{ ...it, action: 'export' }) } }
			else if operation == 'remove' { pkgprotocol.Review{ ...base, requested: [], rows: base.rows.map(pkgprotocol.ReviewPackage{ ...it, requested: false, action: 'remove' }) } }
			else { base }
		app.review_snapshot = pkgprotocol.decode_review(json2.encode(snapshot))!
		app.review_ready = true; app.review_selected = 1; app.review_scroll = 1
		if operation == 'deploy' { app.deployment_pending = '/company/' + 'approved é🚀 '.repeat(160) + '.json' }
		app.handle('software.details')!
		assert app.details_mode && app.details_review
		details_fixture_check_all_pages(mut app)!
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
				free_window_tree(software_label('Owned paragraph é🚀 '.repeat(16), 14, 8, 352, 72, true))
				free_window_tree(software_label(row.description, 14, 8, 96, 54, false))
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
		println('Software paragraphs: 1000 owned/borrowed/wrapped/truncated label retirement cycles retain zero tracked bytes')
	}
}
