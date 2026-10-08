// SPDX-License-Identifier: GPL-2.0-or-later
module packagefixture

import androidhost as ah

fn make_body(entries map[string]string) !string {
	mapping := call('builtins.dict')!
	for name, data in entries { call('operator.setitem', o(mapping), v(ah.Value(name)), b(data))! }
	return call('archive', o(mapping))!
}

fn snapshot_contents(archive string, name string) !string {
	return method(method(archive, 'extractfile', [v(ah.Value(name))], {})!, 'read', [], {})!
}

fn names(archive string) !string { return method(archive, 'getnames', [], {})! }

fn assert_member(unit string, name string, actual string, method_name string) ! {
	unit_call(unit, method_name, [v(ah.Value(name)), o(actual)])!
}

fn assert_bytes(unit string, hex string, actual string, method_name string) ! {
	unit_call(unit, method_name, [b(hex), o(actual)])!
}

fn saved_body(unit string, archive string) ! {
	assert_equal(unit, snapshot_contents(archive, 'etc/apk/world')!, b('67746b0a'))!
	assert_member(unit, 'usr/bin/gtk3-demo', names(archive)!, 'assertNotIn')!
}

fn atomic_case(unit string) ! {
	first := make_body({ 'usr/bin/gtk3-demo': '6f6e65' })!
	assert_equal(unit, unit_call(unit, 'upload', [o(first)])!, v(ah.Value(204)))!
	second := make_body({ 'etc/apk/world': '67746b0a' })!
	assert_equal(unit, unit_call(unit, 'upload', [o(second)])!, v(ah.Value(204)))!
	manager := invoke('tarfile.open', [o(unit_field(unit, 'store')!), v(ah.Value('r:'))], {})!
	archive := enter(manager)!
	saved_body(unit, archive) or {
		failure := err
		if retire(manager, failure)! { return }
		return failure
	}
	retire(manager, none)!
}

fn expected_http(unit string, method_name string, arguments []ah.Value, code int) ! {
	expected := callback('resolve', { 'name': ah.Value('urllib.error.HTTPError') })!.text()
	manager := unit_call(unit, 'assertRaises', [o(expected)])!
	failure_object := enter(manager)!
	mut retired := false
	unit_call(unit, method_name, arguments) or {
		failure := err
		retired = true
		if !retire(manager, failure)! { return failure }
		''
	}
	if !retired { retire(manager, none)! }
	assert_equal(unit, attribute(attribute(failure_object, 'exception')!, 'code')!, v(ah.Value(code)))!
}

fn traversal(unit string) ! {
	good := make_body({ 'usr/lib/libgtk.so': '67746b' })!
	assert_equal(unit, unit_call(unit, 'upload', [o(good)])!, v(ah.Value(204)))!
	store := unit_field(unit, 'store')!
	before := method(store, 'read_bytes', [], {})!
	bad := make_body({ '../escape': '626164' })!
	expected_http(unit, 'upload', [o(bad)], 400)!
	assert_equal(unit, method(store, 'read_bytes', [], {})!, o(before))!
}

fn source_first(unit string, archive string) ! {
	assert_bytes(unit, '535044582d4c6963656e73652d4964656e7469666965723a2047504c2d322e302d6f722d6c61746572', snapshot_contents(archive, 'desktop/main.v')!, 'assertIn')!
	for name in ['desktop/local.v', '.vinix-build/desktop/app_calculator.v', '.vinix-build/desktop/translations_data.v'] {
		assert_member(unit, name, names(archive)!, 'assertIn')!
	}
	unit_call(unit, 'assertTrue', [o(method(method(archive, 'getmember', [v(ah.Value('.vinix-build/desktop/app_icon_data.h'))], {})!, 'isfile', [], {})!)])!
	icon := snapshot_contents(archive, '.vinix-build/desktop/app_icon_data.h')!
	assert_bytes(unit, '73746174696320636f6e737420756e7369676e656420636861722076696e69785f6170705f69636f6e5f7465726d696e616c5b5d', icon, 'assertIn')!
	spaced := method(bytes('20')!, 'join', [o(method(icon, 'split', [], {})!)], {})!
	assert_bytes(unit, '307866662c20307831312c20307832322c20307833332c2030786666', spaced, 'assertIn')!
	assert_member(unit, '.vinix-build/vmodules/ui2/v.mod', names(archive)!, 'assertIn')!
	assert_member(unit, '.vinix-build/vmodules/ui2/ui/vinix_headless_backend.v', names(archive)!, 'assertIn')!
	staged_main := method(archive, 'extractfile', [v(ah.Value('.vinix-build/desktop/main.v'))], {})!
	assert_bytes(unit, '416c6c207269676874732072657365727665642e', method(staged_main, 'read', [], {})!, 'assertNotIn')!
	for name in ['.vinix-build/desktop/main.v', '.vinix-build/vmodules/ui2/ui/ui.v'] {
		unit_call(unit, 'assertTrue', [o(method(method(archive, 'getmember', [v(ah.Value(name))], {})!, 'isfile', [], {})!)])!
	}
	assert_bytes(unit, '73656c65637465645f7569325f736f75726365', snapshot_contents(archive, '.vinix-build/vmodules/ui2/ui/ui.v')!, 'assertIn')!
	assert_member(unit, 'ignored.txt', names(archive)!, 'assertNotIn')!
	iter := iterator(names(archive)!)!
	mut found := false
	for {
		row := next(iter)!
		if row.done { break }
		if truth(call('operator.contains', o(row.value), v(ah.Value('.git/')))!)! { found = true; break }
	}
	unit_call(unit, 'assertFalse', [v(ah.Value(found))])!
}

fn source_scope(unit string, mode string) ! {
	manager := unit_call(unit, 'source_snapshot', [])!
	archive := enter(manager)!
	source_scope_body(unit, archive, mode) or {
		failure := err
		if retire(manager, failure)! { return }
		return failure
	}
	retire(manager, none)!
}

fn source_scope_body(unit string, archive string, mode string) ! {
	match mode {
		'first' { source_first(unit, archive)! }
		'ui2' { assert_bytes(unit, '73656c65637465645f7569325f736f75726365' + '203d2066616c7365', snapshot_contents(archive, '.vinix-build/vmodules/ui2/ui/ui.v')!, 'assertIn')! }
		'changed' { assert_bytes(unit, '6368616e67656420616674657220736572766572207374617274', snapshot_contents(archive, 'desktop/main.v')!, 'assertIn')! }
		'oversized' {
			assert_member(unit, '.initramfs-desktop.tar.abc123', names(archive)!, 'assertNotIn')!
			assert_member(unit, 'desktop/local.v', names(archive)!, 'assertIn')!
		}
		else { return error('unknown source fixture scope') }
	}
}

fn source_live(unit string) ! {
	source_scope(unit, 'first')!
	first := unit_call(unit, 'source_snapshot_bytes', [])!
	call('time.sleep', o(call('builtins.float', v(ah.Value('1.1')))!))!
	assert_equal(unit, unit_call(unit, 'source_snapshot_bytes', [])!, o(first))!
	write_text(join(unit_field(unit, 'ui2')!, 'ui/ui.v')!, 'module ui2\nconst selected_ui2_source = false\n')!
	source_scope(unit, 'ui2')!
	write_text(join(unit_field(unit, 'source')!, 'desktop/main.v')!, 'module main\n// changed after server start\n')!
	source_scope(unit, 'changed')!
}

fn live_apps(unit string) ! {
	for pair in [['vinix-files', 'files-live'], ['vinix-activity', 'activity-live'], ['vinix-settings', 'settings-live']] {
		app, directory := pair[0], pair[1]
		published := join(join(unit_field(unit, 'source')!, 'build-aarch64-desktop-apps')!, directory)!
		method(published, 'mkdir', [], { 'parents': v(ah.Value(true)) })!
		method(join(published, app)!, 'write_bytes', [o(method(literal(ah.Value(app + ' executable'))!, 'encode', [], {})!)], {})!
		write_text(join(published, 'version')!, '123 17\n')!
	}
	for pair in [['/vinix-files/binary', 'vinix-files executable'], ['/vinix-activity/binary', 'vinix-activity executable'], ['/vinix-activity/version', '123 17\n'], ['/vinix-settings/binary', 'vinix-settings executable']] {
		assert_equal(unit, unit_call(unit, 'fetch', [v(ah.Value(pair[0]))])!, o(method(literal(ah.Value(pair[1]))!, 'encode', [], {})!))!
	}
	for path in ['/vinix-terminal/binary', '/vinix-files/vinix-files', '/vinix-files/binary/x'] {
		expected_http(unit, 'fetch', [v(ah.Value(path))], 404)!
	}
}

fn oversized(unit string) ! {
	manager := call('open', o(join(unit_field(unit, 'source')!, '.initramfs-desktop.tar.abc123')!), v(ah.Value('wb')))!
	leftover := enter(manager)!
	method(leftover, 'truncate', [v(ah.Value(65 * 1024 * 1024))], {}) or {
		failure := err
		if retire(manager, failure)! { return }
		return failure
	}
	retire(manager, none)!
	source_scope(unit, 'oversized')!
}

fn testcase(unit string, name string) ! {
	match name {
		'test_atomic_valid_overlay_replacement' { atomic_case(unit)! }
		'test_rejects_traversal_and_keeps_previous_overlay' { traversal(unit)! }
		'test_source_snapshot_reflects_live_tracked_and_untracked_files' { source_live(unit)! }
		'test_serves_each_live_app_build_from_its_own_directory' { live_apps(unit)! }
		'test_live_app_without_a_build_is_not_found' { expected_http(unit, 'fetch', [v(ah.Value('/vinix-activity/version'))], 404)! }
		'test_source_snapshot_skips_oversized_files' { oversized(unit)! }
		else { return error('unknown independent package fixture') }
	}
}
