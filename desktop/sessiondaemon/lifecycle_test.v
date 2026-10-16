// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the real executable boundary, authenticated IPC, persistence,
// dependency restarts and lease cleanup without a display or UI dependency.
module sessiondaemon

import desktop.sessioncore
import desktop.sessionipc
import os
import time

fn session_test_wait() {
	for _ in 0 .. 100 {
		if sessionipc.session_call_ok('ping', []) { return }
		time.sleep(20 * time.millisecond)
	}
	assert false, 'session broker did not become ready'
}

fn test_broker_credentials_durable_alarms_dialogs_exchange_and_shutdown() {
	base := '${os.temp_dir()}/vinix-session-test-${C.getpid()}'
	os.mkdir(base) or { panic(err) }
	os.chmod(base, 0o700) or { panic(err) }
	defer { os.rmdir_all(base) or {} }
	os.setenv('VINIX_SESSION_RUNTIME', base, true)
	home := '${base}/home'
	os.mkdir(home) or { panic(err) }
	binary := os.real_path('build/session-runtime/vinix-session')
	assert os.is_file(binary)
	mut broker := os.new_process(binary)
	broker.set_args(['--session-home=${home}'])
	broker.run()
	defer {
		broker.signal_kill()
		broker.wait()
		broker.close()
	}
	session_test_wait()
	assert sessionipc.session_call_ok('attach', [])
	assert sessionipc.session_call_ok('quiet', ['2', '3600'])
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
	assert sessionipc.dialog_open('file', 0, 'Open file', home, '', 'text/plain')
	assert sessionipc.dialog_take('file') == none
	owner := int(C.getpid()).str()
	selected_path := '${home}/document.txt'
	assert !owner.contains('\x00') && !selected_path.contains('\x00')
	assert sessionipc.session_call_ok('dialog.result', [owner, 'file', selected_path])
	selected := sessionipc.dialog_take('file') or { panic('missing selected file') }
	assert selected == '${home}/document.txt'
	assert sessionipc.offer_data(.html, '<b>Hello</b>', false)
	token_record := sessionipc.session_call('exchange.grant', [owner]) or { panic(err) }
	f := sessioncore.fields(token_record) or { panic(err) }
	assert f.count == 2 && f.values[0] == 'token'
	data := sessionipc.session_call('clipboard.read', [f.values[1]]) or { panic(err) }
	assert data == 'data\t1\t3c623e48656c6c6f3c2f623e'
	if _ := sessionipc.session_call('clipboard.read', [f.values[1]]) {
		assert false, 'exchange token was replayed'
	}
	assert sessionipc.offer_data(.text, 'private', true)
	private_snapshot := sessionipc.session_call('clipboard.snapshot', []) or { panic(err) }
	assert private_snapshot == 'data\t0\t70726976617465\t1\t${owner}'
	assert sessionipc.session_call_ok('clipboard.clear', [])
	cleared_snapshot := sessionipc.session_call('clipboard.snapshot', []) or { panic(err) }
	assert cleared_snapshot == 'empty'
	if _ := sessionipc.session_call('clipboard.promote', [owner]) {
		assert false, 'cleared clipboard offer survived'
	}
	// A policy update must revoke an issued token immediately and permanently,
	// including when application access is later enabled again.
	assert sessionipc.offer_data(.text, 'revoke this copy', false)
	pending_record := sessionipc.session_call('exchange.grant', [owner])!
	pending := sessioncore.fields(pending_record)!
	assert pending.count == 2 && pending.values[0] == 'token'
	disabled_policy := sessioncore.Policy{ clipboard_apps: false }.encode()
	assert sessionipc.session_call_ok('policy.set', [disabled_policy])
	assert !sessionipc.offer_data(.text, 'disabled', false)
	assert !sessionipc.session_call_ok('clipboard.request', [])
	assert !sessionipc.session_call_ok('exchange.take', [])
	assert !sessionipc.session_call_ok('clipboard.read', [pending.values[1]])
	enabled_policy := sessioncore.Policy{}.encode()
	assert sessionipc.session_call_ok('policy.set', [enabled_policy])
	assert !sessionipc.session_call_ok('clipboard.read', [pending.values[1]])
	assert !sessionipc.session_call_ok('clipboard.promote', [owner])
	revoked_snapshot := sessionipc.session_call('clipboard.snapshot', [])!
	assert revoked_snapshot == 'empty'
	assert sessionipc.offer_data(.text, 'new copy', false)
	new_grant := sessionipc.session_call('exchange.grant', [owner])!
	new_fields := sessioncore.fields(new_grant)!
	new_data := sessionipc.session_call('clipboard.read', [new_fields.values[1]])!
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
	broker.set_args(['--session-home=${home}'])
	broker.run()
	session_test_wait()
	assert sessionipc.session_call_ok('attach', [])
	time.sleep(1100 * time.millisecond)
	history := sessionipc.session_call('history', []) or { panic(err) }
	notices := sessioncore.decode_notifications(history) or { panic(err) }
	assert notices.count == 1
	assert notices.items[0].title.str() == 'App closed timer'
	assert notices.mode == .focus
	assert sessionipc.session_call_ok('shutdown', [])
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
	binary := os.real_path('build/session-runtime/vinix-session')
	defer { unsafe { binary.free() } }
	mut broker := os.new_process(binary)
	broker.set_args(['--session-home=${base}'])
	broker.run()
	defer {
		broker.signal_kill()
		broker.wait()
		broker.close()
	}
	session_test_wait()
	assert sessionipc.session_call_ok('attach', [])
	mut first := [0, 0]!
	for _ in 0 .. 100 {
		first = session_test_service_pids()
		if first[0] > 0 && first[1] > 0 { break }
		time.sleep(20 * time.millisecond)
	}
	assert first[0] > 0 && first[1] > 0
	for pid in first {
		identity := os.exec(['ps', '-p', pid.str(), '-o', 'args='])
		assert identity.exit_code == 0 && identity.output.contains('vinix-service-runner')
		unsafe { identity.output.free() }
	}
	C.kill(first[0], C.SIGKILL)
	mut next := [0, 0]!
	for _ in 0 .. 100 {
		next = session_test_service_pids()
		if next[0] > 0 && next[0] != first[0] && next[1] > 0 && next[1] != first[1] { break }
		time.sleep(20 * time.millisecond)
	}
	assert next[0] > 0 && next[0] != first[0] && next[1] > 0 && next[1] != first[1]
	assert sessionipc.session_call_ok('service.enable', ['0', '0'])
	for _ in 0 .. 100 {
		if session_test_service_pids() == [0, 0]! { break }
		time.sleep(20 * time.millisecond)
	}
	assert session_test_service_pids() == [0, 0]!
	assert sessionipc.session_call_ok('service.enable', ['0', '1'])
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
	record := sessionipc.session_call('services', []) or { return [0, 0]! }
	defer { unsafe { record.free() } }
	mut result := [0, 0]!
	lines := record.split('\n')
	defer {
		unsafe {
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
	defer {
		unsafe {
			(&array(&args)).free()
			result.output.free()
		}
	}
	lines := result.output.split('\n')
	defer { unsafe { lines.free() } }
	for line in lines {
		columns := line.fields()
		defer { unsafe { columns.free() } }
		if columns.len != 2 { continue }
		parent := int(sessioncore.number(columns[1], 0, 2147483647) or { continue })
		if parent == pid { return int(sessioncore.number(columns[0], 1, 2147483647) or { 0 }) }
	}
	return 0
}
