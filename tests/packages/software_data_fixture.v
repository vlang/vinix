// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import desktop.packagecore
import tools.packages.pkgprotocol

fn check_data_report_content(app &SoftwareApp) {
	mut bytes := []u8{}
	unsafe { bytes.flags |= .noslices }
	for page in app.details_pages {
		mut lines := page.text.split_into_lines()
		for line in lines {
			start := if line.starts_with('• ') { 4 } else { 2 }
			for index in start .. line.len { bytes << line[index] }
		}
		software_policy_free_lines(mut lines)
	}
	text := editor_bytes_text(bytes)
	defer { unsafe { bytes.free() } }
	assert text.contains('Only the signed-in ordinary account') && text.contains('Uninstall keeps personal data')
	assert text.contains('not personal data')
	count := app.data_status.rows.len.str(); expected_count := 'Applications with retained data: ' + count
	assert text.contains(expected_count); unsafe { count.free(); expected_count.free() }
	if app.data_pending != '' {
		id := 'Permanently delete data for: ' + app.data_pending
		location := 'Only this account\'s ~/.local/share/vinix-apps/' + app.data_pending + ' directory is deleted.'
		assert text.contains(id) && text.contains(location)
		unsafe { id.free(); location.free() }
		assert text.contains('This cannot be undone') && text.contains('Documents granted to the application stay in their original locations')
		assert text.contains('installed state, live leases and filesystem safety') && text.contains('Reading does not approve deletion')
	} else if app.data_selected >= 0 && app.data_selected < app.data_status.rows.len {
		row := app.data_status.rows[app.data_selected]
		id := 'Application: ' + row.id; location := 'Location: ~/.local/share/vinix-apps/' + row.id
		assert text.contains(id) && text.contains(location)
		unsafe { id.free(); location.free() }
		assert text.contains('Application is installed.') == row.installed
		assert text.contains('Application is uninstalled; personal data remains.') == !row.installed
		if row.diagnostic != '' {
			diagnostic := 'Diagnostic: ' + row.diagnostic
			assert text.contains(diagnostic); unsafe { diagnostic.free() }
		} else { assert text.contains('No inventory diagnostic was reported') }
		assert text.contains('an observation, not permission to delete')
	} else if app.data_status.rows.len == 0 { assert text.contains('No personal application data was found for this account.') }
}

fn check_data_reader_boundaries() ! {
	mut rows := []pkgprotocol.PersonalData{cap: 4096}
	for index in 0 .. 4095 {
		number := index.str()
		rows << pkgprotocol.PersonalData{ id: 'data-app-' + number, installed: index % 2 == 0 }
		unsafe { number.free() }
	}
	prefix := 'Directory safety: 部署 é🚀 '
	rows << pkgprotocol.PersonalData{ id: 'x'.repeat(128), diagnostic: prefix + 'd'.repeat(512 - prefix.len) }
	mut inventory := pkgprotocol.PersonalDataStatus{ format: 1, rows: rows }
	text := json2.encode(inventory); inventory.close()
	mut app := SoftwareApp{ administration_required: true, data_mode: true, output: text.bytes() }
	app.load_personal_data(); assert app.data_ready && app.data_selected == -1 && app.data_status.rows.len == 4096
	check_data_report_content(&app); check_report_return_selection(mut app)!
	check_software_report_reader(mut app)!
	app.data_selected = app.data_status.rows.len - 1; app.prepare_personal_data_details()
	check_data_report_content(&app); check_software_report_reader(mut app)!
	app.close_app(); unsafe { text.free() }
	mut empty := SoftwareApp{ administration_required: true, data_mode: true, output: '{"format":1,"rows":[]}'.bytes() }
	empty.load_personal_data(); assert empty.data_ready && !empty.report_has_packages()
	check_data_report_content(&empty); check_software_report_reader(mut empty)!
	empty.close_app()
	println('Software personal data reader: empty and 4096-row inventory, 128-byte IDs and complete 512-byte Unicode diagnostics, initial selection and bounded item navigation, full/compact return placement and retirement passed')
}

fn software_data_service_fixture(args []string) !bool {
	if args[1..] == ['--json', 'data-list'] {
		status := fixture_personal_data_status()
		println(json2.encode(pkgprotocol.PersonalDataStatus{ ...status, rows: status.rows.filter(it.id != 'removed-app' || !os.exists(os.getenv('VINIX_SOFTWARE_DATA_FIXTURE'))) }))
		return true
	}
	if args[1] == 'purge-data' {
		assert args.len == 3
		time.sleep(30 * time.millisecond)
		if args[2] == 'busy-app' {
			eprintln('cannot purge busy-app: generation 3 is still in use; stop applications using that generation and retry')
			exit(17)
		}
		assert args[2] == 'removed-app'
		os.write_file(os.getenv('VINIX_SOFTWARE_DATA_FIXTURE'), 'removed-app')!
		return true
	}
	return false
}

fn fixture_personal_data_status() pkgprotocol.PersonalDataStatus {
	return pkgprotocol.PersonalDataStatus{ format: 1, rows: [
		pkgprotocol.PersonalData{ id: 'installed-app', installed: true },
		pkgprotocol.PersonalData{ id: 'removed-app' },
		pkgprotocol.PersonalData{ id: 'busy-app' },
		pkgprotocol.PersonalData{ id: 'unsafe-app', diagnostic: 'Application data must be an ordinary directory.' }] }
}

fn check_software_data() ! {
	receipt := os.temp_dir() + '/vinix-software-data-' + os.getpid().str()
	os.setenv('VINIX_SOFTWARE_DATA_FIXTURE', receipt, true)
	defer { os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_DATA_FIXTURE') }
	mut app := SoftwareApp{ administration_required: true, service_path: os.executable(), output: []u8{cap: 8192}, query: []u8{cap: 256} }
	app.handle('software.data')!
	assert app.data_mode && app.worker.args == ['--json', 'data-list'] && !app.admin_prompt
	assert app.prepare_close(), 'inventory must be safe to close'
	wait_for_software(mut app)
	assert app.data_ready && app.data_status.rows.len == 4 && !app.admin_prompt
	check_data_report_content(&app); check_software_report_reader(mut app)!
	app.handle('software.row.0')!; app.handle('software.data.delete')!
	assert app.data_pending == '' && app.status.contains('Uninstall')
	check_data_report_content(&app); check_software_report_reader(mut app)!
	app.handle('software.row.3')!; app.handle('software.data.delete')!
	assert app.data_pending == '' && app.status.contains('ordinary directory')
	check_data_report_content(&app); check_software_report_reader(mut app)!
	app.handle('software.row.1')!; app.handle('software.data.delete')!
	assert app.data_pending == 'removed-app' && app.worker == unsafe { nil }
	check_data_report_content(&app); check_software_report_reader(mut app)!
	app.handle('software.row.2')!; app.handle('software.data.reload')!
	app.handle('software.data.back')!; app.handle('software.confirm')!
	assert app.data_pending == 'removed-app' && app.data_selected == 1 && app.worker == unsafe { nil } && app.data_mode
	app.handle(packagecore.request_prefix + '{"id":"installed-app"}')!
	assert app.launch_request == '' && app.worker == unsafe { nil }
	tree := app.build(ui2.rect(0, 0, 640, 610))!
	assert tree.children.any(it.text == 'removed-app')
	assert tree.children.any(it.id == 'software.data.confirm' && it.text == 'Delete permanently')
	assert !tree.children.any(it.id == 'software.data.back' || it.id == 'software.row.0')
	free_window_tree(tree)
	app.handle('software.data.cancel')!
	assert app.data_pending == '' && app.status.contains('cancelled')
	app.handle('software.row.2')!; app.handle('software.data.delete')!; app.handle('software.data.confirm')!
	assert app.worker.args == ['purge-data', 'busy-app'] && !app.admin_prompt && !app.prepare_close()
	app.handle('software.data.cancel')!
	assert app.data_pending == 'busy-app'
	wait_for_software(mut app)
	assert app.data_pending == 'busy-app' && app.status.contains('still in use')
	check_data_report_content(&app); check_software_report_reader(mut app)!
	assert app.prepare_close()
	app.handle('software.data.cancel')!; app.handle('software.row.1')!
	app.handle('software.data.delete')!; app.handle('software.data.confirm')!
	assert app.worker.args == ['purge-data', 'removed-app'] && !app.admin_prompt
	wait_for_software(mut app)
	assert app.data_ready && app.data_pending == '' && app.data_selected == -1
	assert app.status == 'Personal data deleted for removed-app.'
	assert !app.data_status.rows.any(it.id == 'removed-app') && os.read_file(receipt)! == 'removed-app'
	app.output.clear(); for byte in '{"format":2}' { app.output << byte }
	app.data_ready = false; app.load_personal_data()
	app.data_selected = 1; app.handle('software.data.delete')!
	assert !app.data_ready && app.data_pending == '' && app.status.contains('Invalid personal data')
	app.handle('software.report.read')!; assert !app.report_reader_mode && app.details_pages.len == 0 && app.details_compact_pages.len == 0
	app.handle('software.data.back')!
	wait_for_software(mut app)
	assert !app.data_mode
	app.close_app()
	mut root := SoftwareApp{ service_path: os.executable() }
	root.handle('software.data')!
	assert root.data_mode && root.worker == unsafe { nil } && root.status.contains('ordinary account')
	root.handle('software.data.confirm')!
	root.handle('software.report.read')!
	assert root.worker == unsafe { nil }
	assert !root.report_reader_mode && root.details_pages.len == 0
	root_tree := root.build(ui2.rect(0, 0, 640, 610))!
	assert !root_tree.children.any(it.id == 'software.data.delete' || it.id == 'software.data.reload')
	free_window_tree(root_tree); root.close_app()
	mut paged := SoftwareApp{ administration_required: true, data_mode: true, data_ready: true, page_rows: 2,
		data_status: pkgprotocol.decode_personal_data(json2.encode(fixture_personal_data_status()))! }
	paged.handle('software.data.down')!; paged.handle('software.row.0')!
	assert paged.data_scroll == 2 && paged.data_selected == 2
	paged.handle('software.data.up')!; assert paged.data_scroll == 0
	paged.close_app()
	check_data_reader_boundaries()!
	println('Software personal data: own-account inventory, installed/unsafe refusal, frozen explicit confirmation, cancellation, paging, live-lease diagnostics, reload and close guard passed')
}

fn check_software_data_memory() ! {
	$if !track_heap ? { return error('compile personal data memory fixture with -d track_heap') }
	$if track_heap ? {
		text := json2.encode(fixture_personal_data_status())
		mut wide_rows := []pkgprotocol.PersonalData{cap: 32}
		for index in 0 .. 32 { wide_rows << pkgprotocol.PersonalData{ id: 'app-' + index.str() } }
		wide := json2.encode(pkgprotocol.PersonalDataStatus{ format: 1, rows: wide_rows })
		mut wide_status := pkgprotocol.PersonalDataStatus{ rows: wide_rows }; wide_status.close()
		invalid := '{"format":1,"rows":[{"id":"app","installed":false,"diagnostic":"owned"},{"id":"other","installed":false,"diagnostic":"\\ud800"}]}'
		mut app := SoftwareApp{ administration_required: true, data_mode: true, output: text.bytes() }
		unsafe { app.output.flags |= .noslices }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				for input in [wide, invalid, text]! {
					app.output.clear(); for byte in input { app.output << byte }
					app.load_personal_data()
					assert app.data_ready == (input != invalid)
					app.clear_personal_data()
				}
				app.load_personal_data()
				app.handle_personal_data('software.row.1')
				report_reader_cycle(mut app)!
				free_window_tree(app.build_personal_data(640, 610))
				app.handle_personal_data('software.data.delete')
				report_reader_cycle(mut app)!
				free_window_tree(app.build_personal_data(640, 610))
				app.handle_personal_data('software.data.cancel')
				app.clear_personal_data()
			}
			unsafe { app.status.free() }; app.status = ''
		}
		kept := C.vinix_heap_end()
		app.close_app(); unsafe { text.free(); wide.free() }
		assert kept == 0, 'personal data management retained ${kept} bytes'
		println('Software personal data: 1000 wide/invalid/valid decode/select/render/confirm/cancel/retire cycles retain zero tracked bytes')
		println('Software personal data reader: 1000 inventory/confirmation/read/item/page/resize/ignored-deletion/Back/cancel/retirement cycles retain zero tracked bytes')
	}
}
