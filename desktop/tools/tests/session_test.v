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

fn test_broker_selector_filters_run_before_argument_decoding_or_side_effects() {
	mut daemon := &SessionDaemon{compositor: int(C.getpid()) + 1}
	defer { unsafe { free(daemon) } }
	peer := SessionCredentials{pid: C.getpid(), uid: C.getuid(), gid: C.getgid()}
	// These have the right shape but invalid encoded arguments. Domain denial
	// must happen before unfield(), file access, queuing or a settings handler.
	for request in ['settings.set\tzz', 'policy.set\tzz', 'service.import\tzz\tzz\tzz',
		'exchange.grant\tzz', 'dialog.result\tzz\tzz\tzz'] {
		mut denied := false
		daemon.handle(peer, request) or {
			assert err.msg().starts_with('compositor/')
			denied = true
		}
		assert denied
		assert daemon.queue_count == 0 && !daemon.changed && !daemon.stop
	}
	assert daemon.handle(peer, 'ping')! == 'ok'
	daemon.policy.clipboard_apps = false
	for request in ['clipboard.offer\t0\t0\tzz', 'clipboard.read\tzz', 'clipboard.request',
		'exchange.take'] {
		mut denied := false
		daemon.handle(peer, request) or {
			assert err.msg().starts_with('application/')
			denied = true
		}
		assert denied && daemon.queue_count == 0
	}
	for request in ['sbp/selectors/register\tzz', 'clipboard.*\tzz', 'ping\tzz'] {
		if _ := daemon.handle(peer, request) {
			assert false, 'unknown or malformed operation reached a handler'
		}
	}
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
	binary := os.real_path('build/session-runtime/vinix-desktop')
	mut broker := os.new_process(binary)
	broker.set_args(['--session-services', '--session-home=${home}'])
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

fn test_broker_credentials_durable_alarms_dialogs_exchange_and_shutdown() {
	base := '${os.temp_dir()}/vinix-session-test-${C.getpid()}'
	os.mkdir(base) or { panic(err) }
	os.chmod(base, 0o700) or { panic(err) }
	defer { os.rmdir_all(base) or {} }
	os.setenv('VINIX_SESSION_RUNTIME', base, true)
	home := '${base}/home'
	os.mkdir(home) or { panic(err) }
	binary := os.real_path('build/session-runtime/vinix-desktop')
	assert os.is_file(binary)
	mut broker := os.new_process(binary)
	broker.set_args(['--session-services', '--session-home=${home}'])
	broker.run()
	defer {
		broker.signal_kill()
		broker.wait()
		broker.close()
	}
	session_test_wait()
	assert session_call_ok('attach', [])
	assert session_call_ok('quiet', ['2', '3600'])
	mut client := os.new_process(binary)
	client.set_args(['--session-control', 'alarm', 'detached', 'App closed timer', '1', '0'])
	client.run()
	client.wait()
	assert client.code == 0
	client.close()
	mut untrusted := os.new_process(binary)
	untrusted.set_args(['--session-control', 'settings.set', 'privacy.history', ''])
	untrusted.run()
	untrusted.wait()
	assert untrusted.code != 0
	untrusted.close()
	assert session_dialog_open('file', 0, 'Open file', home, '', 'text/plain')
	assert session_dialog_take('file') == none
	owner := int(C.getpid()).str()
	selected_path := '${home}/document.txt'
	assert !owner.contains('\x00') && !selected_path.contains('\x00')
	assert session_call_ok('dialog.result', [owner, 'file', selected_path])
	selected := session_dialog_take('file') or { panic('missing selected file') }
	assert selected == '${home}/document.txt'
	assert session_offer_data(.html, '<b>Hello</b>', false)
	token_record := session_call('exchange.grant', [owner]) or { panic(err) }
	f := sessioncore.fields(token_record) or { panic(err) }
	assert f.count == 2 && f.values[0] == 'token'
	data := session_call('clipboard.read', [f.values[1]]) or { panic(err) }
	assert data == 'data\t1\t3c623e48656c6c6f3c2f623e'
	if _ := session_call('clipboard.read', [f.values[1]]) {
		assert false, 'exchange token was replayed'
	}
	assert session_offer_data(.text, 'private', true)
	private_snapshot := session_call('clipboard.snapshot', []) or { panic(err) }
	assert private_snapshot == 'data\t0\t70726976617465\t1\t${owner}'
	assert session_call_ok('clipboard.clear', [])
	cleared_snapshot := session_call('clipboard.snapshot', []) or { panic(err) }
	assert cleared_snapshot == 'empty'
	if _ := session_call('clipboard.promote', [owner]) {
		assert false, 'cleared clipboard offer survived'
	}
	// A policy update must revoke an issued token immediately and permanently,
	// including when application access is later enabled again.
	assert session_offer_data(.text, 'revoke this copy', false)
	pending_record := session_call('exchange.grant', [owner])!
	pending := sessioncore.fields(pending_record)!
	assert pending.count == 2 && pending.values[0] == 'token'
	disabled_policy := sessioncore.Policy{clipboard_apps: false}.encode()
	assert session_call_ok('policy.set', [disabled_policy])
	assert !session_offer_data(.text, 'disabled', false)
	assert !session_call_ok('clipboard.request', [])
	assert !session_call_ok('exchange.take', [])
	assert !session_call_ok('clipboard.read', [pending.values[1]])
	enabled_policy := sessioncore.Policy{}.encode()
	assert session_call_ok('policy.set', [enabled_policy])
	assert !session_call_ok('clipboard.read', [pending.values[1]])
	assert !session_call_ok('clipboard.promote', [owner])
	revoked_snapshot := session_call('clipboard.snapshot', [])!
	assert revoked_snapshot == 'empty'
	assert session_offer_data(.text, 'new copy', false)
	new_grant := session_call('exchange.grant', [owner])!
	new_fields := sessioncore.fields(new_grant)!
	new_data := session_call('clipboard.read', [new_fields.values[1]])!
	assert new_data == 'data\t0\t6e657720636f7079'
	unsafe {
		pending_record.free()
		disabled_policy.free()
		enabled_policy.free()
		revoked_snapshot.free()
		new_grant.free()
		new_data.free()
	}
	// Restart the broker before the deadline. The detached alarm is restored
	// from the synchronized snapshot, while ephemeral clipboard grants vanish.
	broker.signal_kill()
	broker.wait()
	broker.close()
	broker = os.new_process(binary)
	broker.set_args(['--session-services', '--session-home=${home}'])
	broker.run()
	session_test_wait()
	assert session_call_ok('attach', [])
	time.sleep(1100 * time.millisecond)
	history := session_call('history', []) or { panic(err) }
	notices := sessioncore.decode_notifications(history) or { panic(err) }
	assert notices.count == 1
	assert notices.items[0].title.str() == 'App closed timer'
	assert notices.mode == .focus
	assert session_call_ok('shutdown', [])
	broker.wait()
	assert broker.code == 0
	unsafe {
		base.free()
		home.free()
		binary.free()
		owner.free()
		selected.free()
		token_record.free()
		data.free()
		private_snapshot.free()
		cleared_snapshot.free()
		history.free()
	}
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

fn test_real_service_groups_restart_dependencies_and_broker_crash_cleanup() {
	base := '${os.temp_dir()}/vinix-service-test-${C.getpid()}'
	os.mkdir(base) or { panic(err) }
	os.chmod(base, 0o700) or { panic(err) }
	defer {
		os.rmdir_all(base) or {}
		unsafe { base.free() }
	}
	os.setenv('VINIX_SESSION_RUNTIME', base, true)
	mut s := sessioncore.Supervisor{ count: 2 }
	for i in 0 .. 2 {
		mut service := sessioncore.Service{ name: sessioncore.text('test.${i}')!, executable: sessioncore.text('/bin/sleep')!, dependencies: u32(i), restart: .on_failure, restart_delay_ms: 100 }
		service.arguments[0].set('60')!
		service.argument_count = 1
		s.services[i] = service
	}
	s.validate() or { panic(err) }
	config := s.encode()
	defer { unsafe { config.free() } }
	sessioncore.save('${base}/.vinix-services', config) or { panic(err) }
	binary := os.real_path('build/session-runtime/vinix-desktop')
	defer { unsafe { binary.free() } }
	mut broker := os.new_process(binary)
	broker.set_args(['--session-services', '--session-home=${base}'])
	broker.run()
	defer {
		broker.signal_kill()
		broker.wait()
		broker.close()
	}
	session_test_wait()
	assert session_call_ok('attach', [])
	mut first := [0, 0]!
	for _ in 0 .. 100 {
		first = session_test_service_pids()
		if first[0] > 0 && first[1] > 0 { break }
		time.sleep(20 * time.millisecond)
	}
	assert first[0] > 0 && first[1] > 0
	C.kill(first[0], C.SIGKILL)
	mut next := [0, 0]!
	for _ in 0 .. 100 {
		next = session_test_service_pids()
		if next[0] > 0 && next[0] != first[0] && next[1] > 0 && next[1] != first[1] { break }
		time.sleep(20 * time.millisecond)
	}
	assert next[0] > 0 && next[0] != first[0] && next[1] > 0 && next[1] != first[1]
	assert session_call_ok('service.enable', ['0', '0'])
	for _ in 0 .. 100 {
		if session_test_service_pids() == [0, 0]! { break }
		time.sleep(20 * time.millisecond)
	}
	assert session_test_service_pids() == [0, 0]!
	assert session_call_ok('service.enable', ['0', '1'])
	for _ in 0 .. 100 {
		next = session_test_service_pids()
		if next[0] > 0 && next[1] > 0 { break }
		time.sleep(20 * time.millisecond)
	}
	assert next[0] > 0 && next[1] > 0
	mut children := [0, 0]!
	for _ in 0 .. 100 {
		children = [session_test_child(next[0]), session_test_child(next[1])]!
		if children[0] > 0 && children[1] > 0 { break }
		time.sleep(20 * time.millisecond)
	}
	assert children[0] > 0 && children[1] > 0
	broker.signal_kill()
	broker.wait()
	for _ in 0 .. 100 {
		if session_test_process_gone(next[0]) && session_test_process_gone(next[1]) && session_test_process_gone(children[0]) && session_test_process_gone(children[1]) {
			break
		}
		time.sleep(20 * time.millisecond)
	}
	assert session_test_process_gone(next[0]) && session_test_process_gone(next[1])
	assert session_test_process_gone(children[0]) && session_test_process_gone(children[1])
}

fn session_test_service_pids() [2]int {
	record := session_call('services', []) or { return [0, 0]! }
	defer { unsafe { record.free() } }
	mut result := [0, 0]!
	lines := record.split('\n')
	defer { unsafe {
		for line in lines { line.free() }
		(&array(&lines)).free()
	}
	 }
	for line in lines {
		f := sessioncore.fields(line) or { continue }
		if f.count != 8 || f.values[0] != 'service' { continue }
		i := int(sessioncore.number(f.values[1], 0, 1) or { continue })
		result[i] = int(sessioncore.number(f.values[4], 0, 2147483647) or { 0 })
	}
	return result
}

fn session_test_process_gone(pid int) bool {
	// macOS may retain the killed orphan as a zombie until launchd reaps it.
	if C.kill(pid, 0) != 0 { return true }
	result := os.exec(['ps', '-p', pid.str(), '-o', 'stat='])
	return result.exit_code != 0 || result.output.trim_space().starts_with('Z')
}

fn session_test_child(pid int) int {
	args := ['ps', '-axo', 'pid=,ppid=']
	result := os.exec(args)
	defer { unsafe {
		(&array(&args)).free()
		result.output.free()
	}
	 }
	lines := result.output.split('\n')
	defer { unsafe { lines.free() } }
	for line in lines {
		columns := line.split_any(' \t')
		defer { unsafe { columns.free() } }
		if columns.len != 2 { continue }
		parent := int(sessioncore.number(columns[1], 0, 2147483647) or { continue })
		if parent == pid { return int(sessioncore.number(columns[0], 1, 2147483647) or { 0 }) }
	}
	return 0
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
