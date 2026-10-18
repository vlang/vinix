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
			installed_repository: 'original-publisher', installed_public_key: 'b'.repeat(64),
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
		'provenance-partial' { text.replace('"installed_repository":"original-publisher",', '') }
		'provenance-invalid' { text.replace('"installed_repository":"original-publisher"', '"installed_repository":"../outside"') }
		'coherence' { text.replace('"updatable":true', '"updatable":false') }
		else { panic('unknown view fixture') }
	})
	return true
}

fn software_view_legacy(text string) string {
	return text.replace('"installed_name":"Installed application",', '').replace('"installed_kind":"native",', '')
		.replace('"installed_permissions":["display"],', '').replace('"installed_window_protocol":2,', '')
		.replace('"installed_repository":"original-publisher",', '').replace('"installed_public_key":"' + 'b'.repeat(64) + '",', '')
}

fn check_software_view_reader() ! {
	check_software_search_paste()
	check_software_catalog_browser()!
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true, query: []u8{cap: 256}, output: []u8{cap: 8192} }
	defer { os.unsetenv('VINIX_SOFTWARE_VIEW_FIXTURE'); app.close_app() }
	text := json2.encode(software_view_fixture())
	metadata_fixture_output(mut app, text); app.load_view()
	assert app.rows.len == 32 && app.rows[31].firmware && app.rows[31].proprietary && app.rows[31].updatable
	assert app.rows[31].permissions == ['files', 'network'] && app.rows[31].installed_permissions == ['display']
	assert app.rows[31].installed_window_protocol == 2
	assert app.rows[31].installed_repository == 'original-publisher' && app.rows[31].installed_public_key == 'b'.repeat(64)
	app.focus = true
	app.key_input('APPLICATION É🚀'); assert app.matching.len == 32
	app.key_input('\x01'); app.key_input('éki'); assert app.matching.len == 32
	app.key_input('\x01'); app.key_input('APP-31'); assert app.matching == [31]
	app.key_input('\x01'); app.key_input('\x7f'); assert app.matching.len == 32
	// Searching stays available while an ordinary catalog read waits to exit.
	os.setenv('VINIX_SOFTWARE_VIEW_FIXTURE', 'held', true)
	app.start(['view'], true); pid := app.worker.pid
	wait_for_package_navigation_output(mut app, false)
	app.handle('software.catalog.browse')!; assert !app.catalog_browser_mode && app.worker.pid == pid
	app.handle('software.status')!; assert !app.status_reader.mode && app.worker.pid == pid
	app.paste_input('APP-31'); assert app.matching == [31] && app.worker.pid == pid
	app.paste_input('\x1b'); assert app.focus && app.worker.pid == pid && app.query.bytestr() == 'APP-31'
	release := u8(`!`); assert C.write(app.worker.stdio_fd[0], &release, 1) == 1
	wait_for_software(mut app); assert app.matching == [31] && app.query.bytestr() == 'APP-31'
	app.key_input('\x01'); app.key_input('\x7f')
	app.selected = 31
	for mode in ['missing', 'duplicate', 'partial', 'coherence', 'provenance-partial', 'provenance-invalid'] {
		os.setenv('VINIX_SOFTWARE_VIEW_FIXTURE', mode, true)
		app.start(['view'], true); wait_for_software(mut app)
		assert app.status.starts_with('Invalid response from the package service:') && !app.admin_prompt && app.worker == unsafe { nil }
		assert app.rows.len == 32 && app.selected == 31 && app.rows[31].updatable && app.rows[31].firmware
		assert app.rows[31].installed_permissions == ['display'] && app.rows[31].installed_window_protocol == 2
		assert app.rows[31].installed_repository == 'original-publisher' && app.rows[31].installed_public_key == 'b'.repeat(64)
		app.handle('software.confirm')!
		assert !app.admin_prompt && app.worker == unsafe { nil }
	}
	metadata_fixture_output(mut app, software_view_legacy(text)); app.load_view()
	assert app.rows.len == 32 && app.rows[0].installed_kind == '' && app.rows[0].installed_window_protocol == 0
	app.selected = 0; app.open_details()
	assert 'Installed permissions: Unavailable from this service' in details_fixture_values(&app, 3)
	assert 'Installed publisher: Unavailable from this service' in details_fixture_values(&app, 2)
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
				catalog_browser_cycle(mut app)!
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
		println('Software compact catalog: 1000 search/filter/select/details/resize/ignored-write/Back and retirement cycles retain zero tracked bytes')
	}
}

fn catalog_browser_cycle(mut app SoftwareApp) ! {
	app.handle('software.catalog.browse')!; assert app.catalog_browser_mode && app.selected == 31
	free_window_tree(app.build(ui2.rect(0, 0, 180, 220))!)
	app.key_input('\x1b[D'); assert app.selected == 30
	app.handle('software.catalog.next')!; assert app.selected == 31
	for _ in 0 .. 3 { app.handle('software.catalog.filter')! }
	app.handle('software.search')!; app.key_input('\x01'); app.paste_input('APP-31')
	assert app.matching.len == 1 && app.matching[0] == 31 && app.selected == 31
	app.paste_input('\x1b'); assert app.catalog_browser_notice && app.catalog_browser_mode
	preview := app.build(ui2.rect(0, 0, 320, 240))!
	assert preview.children.any(it.id == 'software.status'); free_window_tree(preview)
	status_reader_cycle(mut app)!
	app.key_input('\x01'); app.paste_input('ÉKI'); assert app.matching.len == 32 && !app.catalog_browser_notice
	app.key_input('\r'); app.key_input('\r'); assert app.details_mode && app.catalog_browser_mode
	free_window_tree(app.build(ui2.rect(0, 0, 180, 220))!)
	app.key_input('\x1b'); assert !app.details_mode && app.catalog_browser_mode && app.details_pages.len == 0
	for action in ['software.install', 'software.remove', 'software.upgrade', 'software.reload', 'software.refresh',
		'software.confirm', 'software.run', 'software.repositories', 'software.deployment']! { app.handle(action)! }
	assert app.worker == unsafe { nil } && !app.admin_prompt && app.review == '' && app.launch_request == ''
	free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
	app.key_input('\x1b'); assert !app.catalog_browser_mode && app.selected == 31 && app.filter == 0
}

fn check_software_catalog_browser() ! {
	for architecture in ['aarch64', 'x86_64']! {
		mut view := software_view_fixture()
		mapped := view.rows.map(SoftwareRow{ ...it, architecture: architecture })
		text := json2.encode(SoftwareView{ ...view, architecture: architecture,
			rows: mapped })
		mut app := SoftwareApp{ query: []u8{cap: 256}, output: []u8{cap: 8192}, administration_required: true }
		defer { app.close_app(); view.close(); unsafe { (&array(&mapped)).free(); text.free() } }
		metadata_fixture_output(mut app, text); app.load_view(); app.selected = 31
		free_window_tree(app.build(ui2.rect(0, 0, 900, 900))!); assert app.page_rows == 16
		compact := app.build(ui2.rect(0, 0, 180, 220))!
		assert compact.children.any(it.id == 'software.catalog.browse'); free_window_tree(compact)
		app.handle('software.catalog.browse')!; assert app.catalog_browser_mode && app.selected == 31
		for size in [ui2.rect(0, 0, 180, 220), ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 640, 610)]! {
			tree := app.build(size)!
			for id in ['software.catalog.back', 'software.catalog.filter', 'software.search', 'software.catalog.previous', 'software.catalog.next', 'software.details']! {
				button := tree.children.filter(it.id == id)[0]
				assert button.frame.x >= 14 && button.frame.y >= 8 && button.frame.x + button.frame.width <= size.width - 14
				assert button.frame.y + button.frame.height <= size.height
			}
			name := tree.children.filter(it.frame.y == 146)[0]
			assert name.text == app.rows[31].name
			assert software_paragraph_fixture_text(&name, false) == name.text
			free_window_tree(tree)
		}
		app.handle('software.catalog.next')!; assert app.selected == 31
		for _ in 0 .. 40 { app.key_input('\x1b[A') }; assert app.selected == 0
		app.key_input('\x1b[D'); assert app.selected == 0
		app.handle('software.search')!; app.paste_input('APP-31'); assert app.selected == 31 && app.matching == [31]
		app.key_input('\x01'); app.paste_input('missing'); assert app.selected == -1 && app.matching.len == 0
		empty := app.build(ui2.rect(0, 0, 180, 220))!
		assert empty.children.any(it.text == 'No matches') && !empty.children.any(it.id == 'software.details'); free_window_tree(empty)
		app.handle('software.details')!; assert !app.details_mode
		app.key_input('\x01'); app.paste_input('APPLICATION É🚀'); assert app.selected == 0 && app.matching.len == 32
		app.key_input('\x01'); app.paste_input('\xff')
		assert app.catalog_browser_notice && app.select_all && app.query.bytestr() == 'APPLICATION É🚀'
		error_tree := app.build(ui2.rect(0, 0, 180, 220))!
		assert error_tree.children.any(it.text == software_search_input_error); free_window_tree(error_tree)
		app.paste_input('ÉKI'); app.key_input('\r'); assert !app.focus
		for _ in 0 .. 31 { app.key_input('\x1b[C') }; assert app.selected == 31
		for _ in 0 .. 3 { app.handle('software.catalog.filter')!; assert app.matching.len == 32 && app.selected == 31 }
		app.handle('software.details')!; assert app.details_mode && app.catalog_browser_mode
		assert ('Architecture: ' + architecture) in details_fixture_values(&app, 0)
		app.key_input('\x1b'); assert app.catalog_browser_mode && app.details_pages.len == 0
		free_window_tree(app.build(ui2.rect(0, 0, 160, 180))!)
		app.key_input('\x1b'); assert !app.catalog_browser_mode
		returned := app.build(ui2.rect(0, 0, 640, 610))!
		assert app.matching.index(app.selected) >= app.scroll && app.matching.index(app.selected) < app.scroll + app.page_rows
		assert returned.children.any(it.id.starts_with('software.row.') && it.box.bg == settings_choice_bg); free_window_tree(returned)
		app.handle('software.up')!; scroll := app.scroll
		free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); assert app.scroll == scroll
		app.filter = 0; catalog_browser_cycle(mut app)!
	}
	// All supported kinds and the maximum catalog remain reachable through filters.
	mut rows := []SoftwareRow{cap: 4096}
	for i in 0 .. 4096 {
		kind := ['native', 'linux', 'windows', 'apple', 'runtime', 'data']![i % 6]
		number := i.str()
		rows << SoftwareRow{ id: 'app-' + number, name: 'Application é🚀', description: 'Description',
			version: '1.0.0', installed_version: if i % 2 == 0 { '1.0.0' } else { '' },
			installed_name: if i % 2 == 0 { 'Installed application' } else { '' }, installed_kind: if i % 2 == 0 { kind } else { '' },
			architecture: 'x86_64', kind: kind, runtime: 'runtime', repository: 'publisher', public_key: 'a'.repeat(64), license: 'MIT',
			updatable: i % 4 == 0, update_action: if i % 4 == 0 { 'update' } else { '' } }
		unsafe { number.free() }
	}
	mut wide := SoftwareView{ format: 1, generation: 1, architecture: 'x86_64', rows: rows }
	text := json2.encode(wide)
	mut app := SoftwareApp{ query: []u8{cap: 256}, output: []u8{cap: 8192} }
	defer { app.close_app(); wide.close(); unsafe { text.free() } }
	metadata_fixture_output(mut app, text); app.load_view(); assert app.rows.len == 4096, app.status
	app.handle('software.catalog.browse')!
	for i in 0 .. 4096 { assert app.selected == i; app.handle('software.catalog.next')! }
	assert app.selected == 4095
	app.handle('software.catalog.filter')!; assert app.filter == 1 && app.matching.len == 2048 && app.selected == 0
	app.handle('software.catalog.filter')!; assert app.filter == 2 && app.matching.len == 1024
	for _ in 0 .. 1024 { app.handle('software.catalog.next')! }; assert app.selected == 4092
	app.key_input('\x1b'); app.query.clear(); app.filter = 0
	// Empty catalogs are still browsable; loaded proposals and other forms refuse entry.
	for row in app.rows { software_free_row(row) }; app.rows.clear(); app.filter_rows()
	app.open_catalog_browser(); assert app.selected == -1 && app.catalog_browser_mode
	app.key_input('\x1b'); app.review = 'install'.clone(); app.open_catalog_browser(); assert !app.catalog_browser_mode
	app.clear_review(); app.launch_mode = true; app.open_catalog_browser(); assert !app.catalog_browser_mode; app.launch_mode = false
	app.update_error = 'The catalog is expired.'.clone(); app.filter = 1
	app.open_catalog_browser(); app.handle('software.catalog.filter')!
	assert app.filter == 2 && app.matching.len == 0 && app.catalog_browser_notice && app.status.contains('Updates unavailable:')
	app.key_input('\x1b')
	// Unavailable presentation metadata is a visible diagnostic, never a reader.
	app.rows << SoftwareRow{ id: 'invalid', name: 'Invalid metadata', description: '\xff'.clone() }
	app.filter = 0; app.filter_rows(); app.open_catalog_browser(); app.handle('software.details')!
	assert app.catalog_browser_mode && !app.details_mode && app.catalog_browser_notice && app.status.contains('invalid UTF-8')
	invalid := app.build(ui2.rect(0, 0, 180, 220))!; assert invalid.children.any(it.text == app.status); free_window_tree(invalid)
	app.key_input('\x1b')
	println('Software compact catalog: both architectures, all six kinds, 4096 packages, search/filter/empty states, complete Details, native controls, resize selection, read-only actions and Back passed')
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
