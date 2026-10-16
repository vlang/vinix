// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import desktop.sessioncore
import json2
import os
import time

fn session_test_wait() {
	for _ in 0 .. 100 {
		if session_call_ok('ping', []) { return }
		time.sleep(20 * time.millisecond)
	}
	assert false, 'session broker did not become ready'
}

fn test_services_file_chooser_import_and_remove_keep_authorization_and_disabled_state() {
	base := '${os.temp_dir()}/vinix-service-import-test-${C.getpid()}'
	os.mkdir(base)!
	os.chmod(base, 0o700)!
	previous := os.getenv_opt('VINIX_SESSION_RUNTIME')
	os.setenv('VINIX_SESSION_RUNTIME', base, true)
	defer {
		if value := previous { os.setenv('VINIX_SESSION_RUNTIME', value, true) }
		else { os.unsetenv('VINIX_SESSION_RUNTIME') }
		os.rmdir_all(base) or {}
	}
	home := '${base}/home'
	os.mkdir(home)!
	config := '${home}/.vinix-services'
	os.write_file(config, 'vinix-services\t1\n')!
	unit := '${home}/example.service'
	os.write_file(unit, '[Service]\nType=simple\nExecStart=/bin/sleep 60\n')!
	binary := os.real_path('build/session-runtime/vinix-session')
	mut broker := os.new_process(binary)
	broker.set_args(['--session-home=${home}'])
	broker.run()
	defer { broker.signal_kill(); broker.wait(); broker.close() }
	session_test_wait()
	assert !session_call_ok('service.import', ['example.service', unit, '0'])
	assert session_call_ok('attach', [])
	mut d := Desktop{home: home, canvas: Canvas{width: 1600, height: 900}}
	d.initialize_shell_hub()
	d.hub.attached = true
	assert d.handle_session_hub_action('session.service.import')
	assert d.hub.service_import
	assert session_call_ok('dialog.result', [C.getpid().str(), 'linux-service', unit])
	d.poll_shell_services()
	assert !d.hub.service_import && d.hub.service_count == 1
	assert d.hub.service_names[0].str() == 'example.service'
	assert !d.hub.service_enabled[0]
	assert d.hub.service_status.str() == 'Service installed. Select Start to run it.'
	restored := sessioncore.decode_services(os.read_file(config)!, false)!
	assert restored.count == 1 && !restored.services[0].enabled && restored.services[0].pid == 0
	assert d.handle_session_hub_action('session.service.remove.0')
	assert d.hub.service_count == 0 && d.hub.service_status.str() == 'Service removed.'
	assert os.read_file(config)! == 'vinix-services\t1\n'
	assert session_call_ok('shutdown', [])
	broker.wait()
	assert broker.code == 0
}

fn test_local_file_uri_decoding_rejects_remote_hosts_and_nul() {
	for uri in ['file:///home/user/My%20File.txt', 'file://localhost/home/user/My%20File.txt',
		'file:/home/user/My%20File.txt#section'] {
		path := session_file_uri_path(uri) or { panic('local file URI rejected') }
		assert path == '/home/user/My File.txt'
		unsafe { path.free() }
	}
	assert session_file_uri_path('file://server/share/file') == none
	assert session_file_uri_path('file:///tmp/%00file') == none
	assert session_file_uri_path('file:///tmp/%ZZ') == none
	path := session_file_uri_path('file:///tmp/A+B%23C') or { panic('escaped filename rejected') }
	assert path == '/tmp/A+B#C'
	unsafe { path.free() }
}

fn test_saved_workspace_configuration_keeps_live_displays_without_app_restore() {
	home := '${os.temp_dir()}/vinix-display-session-${C.getpid()}'
	os.mkdir(home) or { panic(err) }
	defer { os.rmdir_all(home) or {}; unsafe { home.free() } }
	mut saved := sessioncore.Windows{ restore_session: false }
	saved.configure(8) or { panic(err) }
	record := saved.encode()
	path := '${home}/.vinix-window-session'
	defer { unsafe { record.free(); path.free() } }
	sessioncore.save(path, record) or { panic(err) }
	mut d := Desktop{ home: home, canvas: Canvas{width:1600,height:900} }
	d.session.output_count = 2
	d.session.outputs[0] = sessioncore.Display{id:sessioncore.text('/dev/fb0')!,area:sessioncore.Rect{0,0,800,850},primary:true}
	d.session.outputs[1] = sessioncore.Display{id:sessioncore.text('/dev/fb1')!,area:sessioncore.Rect{800,0,800,850}}
	assert !d.restore_shell_session()
	assert d.workspace_total() == 8
	assert d.session.state.display_count == 2
	assert d.session.state.displays[1].area.x == 800
	d.initialize_shell_hub()
	assert d.session_document_app('/missing/readme.txt', 'vinix-notes') == 'vinix-notes'
	d.hub.associations.set('text/plain', 'vinix-firefox', false) or { panic(err) }
	d.hub.association_overrides.set('text/plain', 'vinix-firefox', false) or { panic(err) }
	d.save_associations()
	mut restored := Desktop{home:home}
	assert restored.session_document_app('/missing/readme.txt', 'vinix-editor') == 'vinix-firefox'
	assert restored.session_document_app('/missing/plot.vgraph', 'vinix-grapher') == 'vinix-grapher'
	restored.session_associate_document('/missing/readme.txt', 'vinix-notes')
	assert restored.session_document_app('/missing/readme.txt', 'vinix-editor') == 'vinix-notes'
	mut files := FilesContextApp{document_default:true}
	files.queue_document_open(path, 'vinix-editor')
	request_bytes := files.take_document_open_request()
	defer { unsafe { request_bytes.free() } }
	request := json2.decode[DocumentOpenRequest](unsafe { tos(&request_bytes[8], request_bytes.len - 8) }) or { panic(err) }
	defer { unsafe { request.path.free(); request.app.free() } }
	assert request.use_default && request.app == 'vinix-editor'
}

fn test_workspace_group_geometry_custom_chords_and_permission_revocation() {
	mut d := Desktop{ canvas: Canvas{ width: 1600, height: 900 } }
	d.configure_workspaces(8)
	a := d.spawn('A', .system, 20, 20, 300, 200)
	b := d.spawn('B', .system, 60, 60, 300, 200)
	d.windows[0].group = 7
	d.windows[1].group = 7
	d.move_window_to_workspace(a, 6)
	assert d.windows[0].workspace == 6 && d.windows[1].workspace == 6
	d.configure_workspaces(3)
	assert d.windows[0].workspace == 2 && d.windows[1].workspace == 2
	d.hub.policy.bind('\x1b[104;9u', 'help') or { panic(err) }
	assert d.session_shortcut_prefix('\x1b[104;', 0)
	assert d.take_window_shortcuts('a\x1b[104;9ub') == 'ab'
	assert d.hub.tab == 4
	d.close_window(b)
	assert d.windows.len == 2 // A and the session hub
	d.hub.policy.allow_capture = false
	d.accept_capture_request(CaptureRequest{sequence:99,command:.screenshot})
	assert d.capture.report.phase == .failed && d.capture.report.handled_sequence == 99
	d.configure_workspaces(16)
	assert d.taskbar_layout(0).workspace_width < 240
	assert d.handle_session_hub_action('session.workspace.next')
	assert d.current_workspace == 4
	assert d.handle_session_hub_action('session.workspace.previous')
	assert d.current_workspace == 3
}

fn test_display_viewports_use_virtual_canvas_coordinates() {
	mut canvas := new_canvas(6, 3)
	defer { unsafe { free(canvas.pixels) } }
	for y in 0 .. 3 {
		for x in 0 .. 6 {
			unsafe { canvas.pixels[y * canvas.stride + x] = u32(y * 16 + x) }
		}
	}
	mut left := [6]u32{}
	mut right := [6]u32{}
	mut first := Framebuffer{ fd: 1, base: unsafe { &left[0] }, width: 3, height: 2, stride: 3, direct: true, origin_y: 1 }
	mut second := Framebuffer{ fd: 1, base: unsafe { &right[0] }, width: 3, height: 2, stride: 3, direct: true, origin_x: 3, origin_y: 1 }
	first.present_viewport(&canvas)
	second.present_viewport(&canvas)
	assert left == [u32(16), 17, 18, 32, 33, 34]!
	assert right == [u32(19), 20, 21, 35, 36, 37]!
}
