// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import ui2

fn software_view_fixture() SoftwareView {
	mut rows := []SoftwareRow{cap: 32}
	for index in 0 .. 32 {
		rows << SoftwareRow{ id: 'app-' + index.str(), name: 'Application é🚀', description: 'Complete description ÉKİé🚀 '.repeat(16),
			version: '2.0.0', installed_version: '1.0.0', installed_name: 'Installed application', installed_kind: 'native',
			installed_permissions: ['display'], installed_window_protocol: 2, architecture: 'aarch64', kind: 'linux', runtime: 'runtime',
			repository: 'publisher', public_key: 'a'.repeat(64), license: 'Vendor-EULA', proprietary: true, firmware: true,
			permissions: ['files', 'network'], requested: true, updatable: true, update_action: 'update' }
	}
	return SoftwareView{ format: 1, generation: 7, architecture: 'aarch64', rows: rows }
}

fn software_view_service_fixture(args []string) bool {
	if args[1] != 'view' { return false }
	mode := os.getenv('VINIX_SOFTWARE_VIEW_FIXTURE')
	defer { unsafe { mode.free() } }
	if mode == '' { return false }
	text := json2.encode(software_view_fixture())
	defer { unsafe { text.free() } }
	println(match mode {
		'missing' { text.replace('"firmware":true,', '') }
		'duplicate' { text.replace('"firmware":true', '"firmware":true,"firm\\u0077are":false') }
		'partial' { text.replace('"installed_permissions":["display"],', '') }
		'coherence' { text.replace('"updatable":true', '"updatable":false') }
		else { panic('unknown view fixture') }
	})
	return true
}

fn software_view_legacy(text string) string {
	return text.replace('"installed_name":"Installed application",', '').replace('"installed_kind":"native",', '')
		.replace('"installed_permissions":["display"],', '').replace('"installed_window_protocol":2,', '')
}

fn check_software_view_reader() ! {
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true, query: []u8{cap: 256}, output: []u8{cap: 8192} }
	defer { os.unsetenv('VINIX_SOFTWARE_VIEW_FIXTURE'); app.close_app() }
	text := json2.encode(software_view_fixture())
	metadata_fixture_output(mut app, text); app.load_view()
	assert app.rows.len == 32 && app.rows[31].firmware && app.rows[31].proprietary && app.rows[31].updatable
	assert app.rows[31].permissions == ['files', 'network'] && app.rows[31].installed_permissions == ['display']
	assert app.rows[31].installed_window_protocol == 2
	app.focus = true
	app.key_input('APPLICATION É🚀'); assert app.matching.len == 32
	app.key_input('\x01'); app.key_input('éki'); assert app.matching.len == 32
	app.key_input('\x01'); app.key_input('APP-31'); assert app.matching == [31]
	app.key_input('\x01'); app.key_input('\x7f'); assert app.matching.len == 32
	app.selected = 31
	for mode in ['missing', 'duplicate', 'partial', 'coherence'] {
		os.setenv('VINIX_SOFTWARE_VIEW_FIXTURE', mode, true)
		app.start(['view'], true); wait_for_software(mut app)
		assert app.status.starts_with('Invalid response from the package service:') && !app.admin_prompt && app.worker == unsafe { nil }
		assert app.rows.len == 32 && app.selected == 31 && app.rows[31].updatable && app.rows[31].firmware
		assert app.rows[31].installed_permissions == ['display'] && app.rows[31].installed_window_protocol == 2
		app.handle('software.confirm')!
		assert !app.admin_prompt && app.worker == unsafe { nil }
	}
	metadata_fixture_output(mut app, software_view_legacy(text)); app.load_view()
	assert app.rows.len == 32 && app.rows[0].installed_kind == '' && app.rows[0].installed_window_protocol == 0
	app.selected = 0; app.open_details()
	assert 'Installed permissions: Unavailable from this service' in details_fixture_values(&app, 3)
	app.clear_details()
	println('Software catalog reader: complete typed flags, installed-versus-planned launch fields, asynchronous malformed-response refusal, prior-valid-view preservation and explicit legacy details passed')
}

fn check_software_view_memory() ! {
	$if !track_heap ? { return error('compile view memory fixture with -d track_heap') }
	$if track_heap ? {
		text := json2.encode(software_view_fixture())
		bad := text.replace('"id":"app-31"', '"id":"app-31","firm\\u0077are":false')
		partial := text[..text.len - 1] + ',"extra":{"incomplete":}}'
		legacy := software_view_legacy(text)
		empty := json2.encode(SoftwareView{ format: 1, architecture: 'aarch64' })
		for warmup in 0 .. 2 {
			mut app := SoftwareApp{ query: []u8{cap: 256}, output: []u8{cap: 8192} }
			unsafe { app.rows.flags |= .noslices; app.matching.flags |= .noslices; app.output.flags |= .noslices }
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				metadata_fixture_output(mut app, text); app.load_view(); assert app.rows.len == 32
				app.query.clear()
				for byte in 'ÉKI' { app.query << byte }
				app.filter_rows(); assert app.matching.len == 32
				app.selected = 31
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
				app.open_details(); free_window_tree(app.build_details(640, 610)); app.clear_details()
				for invalid in [bad, partial]! {
					metadata_fixture_output(mut app, invalid); app.load_view()
					assert app.rows.len == 32 && app.selected == 31 && app.status.starts_with('Invalid response')
				}
				metadata_fixture_output(mut app, legacy); app.load_view()
				assert app.rows.len == 32 && app.rows[31].installed_kind == ''
				metadata_fixture_output(mut app, empty); app.load_view(); assert app.rows.len == 0
				app.query.clear()
			}
			app.close_app()
		}
		kept := C.vinix_heap_end()
		assert kept == 0, 'Software catalog reloads retained ${kept} bytes'
		println('Software catalog reader: 1000 wide/partial-invalid/legacy reload, display/details and retirement cycles retain zero tracked bytes')
	}
}
