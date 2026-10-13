// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import desktop.packagecore
import tools.packages.pkgprotocol

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
	app.handle('software.row.0')!; app.handle('software.data.delete')!
	assert app.data_pending == '' && app.status.contains('Uninstall')
	app.handle('software.row.3')!; app.handle('software.data.delete')!
	assert app.data_pending == '' && app.status.contains('ordinary directory')
	app.handle('software.row.1')!; app.handle('software.data.delete')!
	assert app.data_pending == 'removed-app' && app.worker == unsafe { nil }
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
	app.handle('software.data.back')!
	wait_for_software(mut app)
	assert !app.data_mode
	app.close_app()
	mut root := SoftwareApp{ service_path: os.executable() }
	root.handle('software.data')!
	assert root.data_mode && root.worker == unsafe { nil } && root.status.contains('ordinary account')
	root.handle('software.data.confirm')!
	assert root.worker == unsafe { nil }
	root_tree := root.build(ui2.rect(0, 0, 640, 610))!
	assert !root_tree.children.any(it.id == 'software.data.delete' || it.id == 'software.data.reload')
	free_window_tree(root_tree); root.close_app()
	mut paged := SoftwareApp{ administration_required: true, data_mode: true, data_ready: true, page_rows: 2,
		data_status: pkgprotocol.decode_personal_data(json2.encode(fixture_personal_data_status()))! }
	paged.handle('software.data.down')!; paged.handle('software.row.0')!
	assert paged.data_scroll == 2 && paged.data_selected == 2
	paged.handle('software.data.up')!; assert paged.data_scroll == 0
	paged.close_app()
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
				free_window_tree(app.build_personal_data(640, 610))
				app.handle_personal_data('software.data.delete')
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
	}
}
