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
	if mode == 'held' {
		print(text); flush_stdout()
		mut release := u8(0); assert C.read(0, &release, 1) == 1 && release == `!`
		return true
	}
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
	check_software_search_paste()
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
	// Searching stays available while an ordinary catalog read waits to exit.
	os.setenv('VINIX_SOFTWARE_VIEW_FIXTURE', 'held', true)
	app.start(['view'], true); pid := app.worker.pid
	wait_for_package_navigation_output(mut app, false)
	app.paste_input('APP-31'); assert app.matching == [31] && app.worker.pid == pid
	app.paste_input('\x1b'); assert app.focus && app.worker.pid == pid && app.query.bytestr() == 'APP-31'
	release := u8(`!`); assert C.write(app.worker.stdio_fd[0], &release, 1) == 1
	wait_for_software(mut app); assert app.matching == [31] && app.query.bytestr() == 'APP-31'
	app.key_input('\x01'); app.key_input('\x7f')
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
				software_search_paste_cycle(mut app)
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
		println('Software search paste: 1000 literal/rejected/selected/empty input and catalog retirement cycles retain zero tracked bytes')
	}
}

fn software_search_fixture_text(a &SoftwareApp) string {
	return editor_bytes_text(if a.health_mode { a.health_query } else if a.audit_mode { a.audit_query } else { a.query })
}

fn software_search_fixture_focus(a &SoftwareApp) bool {
	return if a.health_mode { a.health_focus } else if a.audit_mode { a.audit_focus } else { a.focus }
}

fn software_search_fixture_selected(a &SoftwareApp) bool {
	return if a.health_mode { a.health_select_all } else if a.audit_mode { a.audit_select_all } else { a.select_all }
}

fn software_search_fixture_set_focus(mut a SoftwareApp, focused bool) {
	if a.health_mode { a.health_focus = focused } else if a.audit_mode { a.audit_focus = focused } else { a.focus = focused }
}

fn check_software_search_paste() {
	full := 'é'.repeat(128); oversize := full + 'x'; prefix := 'x'.repeat(250)
	defer { unsafe { full.free(); oversize.free(); prefix.free() } }
	for mode in 0 .. 3 {
		mut app := SoftwareApp{ health_mode: mode == 1, health_ready: mode == 1, audit_mode: mode == 2, audit_ready: mode == 2 }
		software_search_fixture_set_focus(mut app, true)
		for selected in [false, true]! {
			app.key_input('\x01'); app.paste_input('kept')
			if selected { app.key_input('\x01') }
			app.scroll = 7; app.health_scroll = 8; app.audit_scroll = 9; app.details_page = 3
			for invalid in ['\x00', '\x01', '\x08', '\x7f', '\r', '\n', '\x1b', '\t', 'bad\nquery', 'bad\x1b[A',
				'bad\x80', '\xc2', '\xc0\xaf', '\xe0\x80\xaf', '\xed\xa0\x80', '\xf4\x90\x80\x80', '\xc2\x80', '\xc2\x9f', oversize]! {
				app.paste_input(invalid)
				assert software_search_fixture_text(&app) == 'kept' && software_search_fixture_focus(&app)
				assert software_search_fixture_selected(&app) == selected && app.status == software_search_input_error
				assert app.scroll == 7 && app.health_scroll == 8 && app.audit_scroll == 9 && app.details_page == 3
			}
			app.paste_input('')
			assert software_search_fixture_text(&app) == 'kept' && software_search_fixture_selected(&app) == selected
			app.paste_input(' é🚀 ; $(literal) \\')
			assert software_search_fixture_text(&app) == if selected { ' é🚀 ; $(literal) \\' } else { 'kept é🚀 ; $(literal) \\' }
			assert software_search_fixture_focus(&app) && !software_search_fixture_selected(&app)
		}
		app.key_input('\x01'); app.paste_input(full)
		assert software_search_fixture_text(&app) == full
		app.paste_input('🚀'); assert software_search_fixture_text(&app) == full && !software_search_fixture_selected(&app)
		app.key_input('\x01'); app.paste_input(oversize)
		assert software_search_fixture_text(&app) == full && software_search_fixture_selected(&app)
		software_search_fixture_set_focus(mut app, false)
		app.paste_input('unfocused'); app.paste_input('\x1b')
		assert software_search_fixture_text(&app) == full && software_search_fixture_selected(&app) && !software_search_fixture_focus(&app)
		software_search_fixture_set_focus(mut app, true)
		app.paste_input(prefix); app.paste_input('🚀'); app.paste_input('é')
		assert software_search_fixture_text(&app).len == 256
		app.key_input('\x08'); assert software_search_fixture_text(&app).len == 254
		app.key_input('\x7f'); assert software_search_fixture_text(&app) == prefix
		app.key_input('\x01'); app.key_input('\x08'); assert software_search_fixture_text(&app) == ''
		app.key_input('typed'); assert software_search_fixture_text(&app) == 'typed'
		for key in ['\r', '\n', '\x1b']! {
			software_search_fixture_set_focus(mut app, true); app.key_input(key)
			assert !software_search_fixture_focus(&app) && software_search_fixture_text(&app) == 'typed'
		}
		app.close_app()
	}
	println('Software search paste: catalog/health/audit literal bounded UTF-8, controls, malformed text, exact byte limits, atomic refusal, selection/focus/page preservation, empty/unfocused input and keyboard editing passed')
}

fn software_search_paste_cycle(mut app SoftwareApp) {
	software_search_fixture_set_focus(mut app, true)
	app.key_input('\x01'); app.paste_input('É🚀')
	app.key_input('\x01')
	for input in ['\x1b', '\x01', '\x08', '\r', 'bad\ntext', '\xc2\x80', '\xed\xa0\x80', '']! {
		app.paste_input(input)
		assert software_search_fixture_text(&app) == 'É🚀' && software_search_fixture_selected(&app) && software_search_fixture_focus(&app)
	}
	app.paste_input('APP-23'); assert software_search_fixture_text(&app) == 'APP-23'
	app.key_input('\x01'); app.key_input('\x08')
	software_search_fixture_set_focus(mut app, false)
}
