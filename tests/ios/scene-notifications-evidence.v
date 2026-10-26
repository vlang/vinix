// SPDX-License-Identifier: GPL-2.0-or-later
// Complete external evidence for scene exports and the next initializer failures.
module main

import crypto.sha256
import os

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		count := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	return hash.sum([]u8{}).hex()
}

fn files(root string, relative string) ![]string {
	mut result := []string{}
	for name in os.ls(os.join_path(root, relative))! {
		path := if relative == '' { name } else { relative + '/' + name }
		full := root + '/' + path
		if os.is_link(full) { return error('symlink in evidence: ' + path) }
		if os.is_dir(full) { result << files(root, path)! } else { result << path }
	}
	result.sort()
	return result
}

fn safe_path(path string) bool {
	return !path.starts_with('/') && !path.contains('\\')
		&& !path.split('/').any(it in ['', '.', '..'])
}

fn require_text(out string, path string, markers []string, expected_panics bool) ! {
	text := os.read_file(out + '/' + path)!.replace('\r\n', '\n')
	for marker in markers {
		if !text.contains(marker) { return error(path + ': missing ' + marker) }
	}
	for bad in ['ERROR: AddressSanitizer', 'runtime error:', '> assert ', 'KERNEL PANIC',
		'FATAL EXCEPTION', 'IOS-NATIVE: FAIL', 'iOS FAIL:'] {
		if text.contains(bad) { return error(path + ': ' + bad) }
	}
	for line in text.split_into_lines() {
		if line.contains('V panic:') && (!expected_panics ||
			(!line.contains('iOS: unimplemented Objective-C method NSData dataWithContentsOfURL:')
			&& !line.contains('iOS: unimplemented Objective-C method NSProcessInfo physicalMemory'))) {
			return error(path + ': unexpected panic: ' + line)
		}
	}
}

fn probe_state(out string) !string {
	state := os.file_name(os.read_file(out + '/probe-no-ads-state.txt')!.trim_space())
	if !state.starts_with('probe-no-ads-') || !safe_path(state) { return error('invalid VM pointer') }
	for file in ['boot.img', 'efivars.fd', 'initramfs.tar.gz', 'limine.conf', 'serial.log'] {
		if !os.is_file(out + '/' + state + '/' + file) { return error('missing VM artifact ' + state + '/' + file) }
	}
	return state
}

fn results(out string) ! {
	revision := os.read_file(out + '/source-revision.txt')!.trim_space()
	if revision.len != 40 || revision.bytes().any(!it.is_hex_digit()) { return error('invalid source revision') }
	for file in ['source/compat/ios/runner/frameworks.c.v',
		'source/compat/ios/runner/scene_notifications_test.v',
		'source/tests/ios/native-init.v', 'source/tests/ios/notification-checks.v',
		'source/tests/ios/notification-vm.v', 'source/tests/ios/scene-notifications-evidence.v',
		'source/tests/ios/image-initializers-input-inventory.v',
		'source/tests/ios/startup-host.v', 'source/tests/ios/inspect-scene-notifications.v',
		'source-files.txt', 'build-inputs.sha256', 'notification-checks', 'notification-vm',
		'scene-notifications-evidence', 'inventory-inputs', 'startup-host-tool', 'imports.log',
		'native/inspect-scene-notifications', 'application/FortniteClient-IOS-Shipping',
		'application/Frameworks/EOSSDK.framework/EOSSDK',
		'application/Frameworks/MarketplaceKitWrapper.framework/MarketplaceKitWrapper',
		'fixture/payload/center-host.c', 'fixture/NotificationChecks.app/Contents/Info.plist',
		'fixture/NotificationChecks.app/Contents/MacOS/center-host', 'host/startup-host.c',
		'host/run-ios-host'] {
		if !os.is_file(out + '/' + file) { return error('missing ' + file) }
	}
	mut seen := map[string]bool{}
	for path in os.read_lines(out + '/source-files.txt')! {
		if !safe_path(path) || path in seen { return error('invalid source path') }
		seen[path] = true
		if !os.is_file(out + '/source/' + path) { return error('missing source ' + path) }
	}
	if seen.len == 0 { return error('empty source inventory') }
	inputs := os.read_lines(out + '/build-inputs.sha256')!
	if inputs.len == 0 { return error('empty build input inventory') }
	for line in inputs {
		if line.len < 67 || line[64..66] != '  ' || line[..64].bytes().any(!it.is_hex_digit()) {
			return error('invalid build input record')
		}
	}
	for i in 0 .. 4 {
		for prefix in ['host/', 'fixture/payload/'] {
			if !os.is_file(out + '/' + prefix + 'host-' + i.str() + '.o') { return error('missing host object') }
		}
	}
	for item in ['native-init', 'run-ios-gles'] {
		for suffix in ['', '.c'] {
			if !os.is_file(out + '/' + item + suffix) { return error('missing ' + item + suffix) }
		}
	}
	mut labels := ['build-init', 'build-run-ios-gles', 'probe-no-ads', 'native/inspect-build', 'native/inspect']
	for label in ['generate', 'object-0', 'object-1', 'object-2', 'object-3', 'link'] { labels << 'host/' + label }
	for label in ['host-generate', 'host-object-0', 'host-object-1', 'host-object-2', 'host-object-3', 'host-link', 'host', 'host-deterministic'] {
		labels << 'fixture/' + label
	}
	for label in labels {
		if os.read_file(out + '/' + label + '.status.txt')!.trim_space() != '0' { return error(label + ' failed') }
		require_text(out, label + '.log', ['COMMAND: '], false)!
	}
	require_text(out, 'native/inspect.log', [
		'IOS-SCENE-NATIVE: UISceneWillEnterForegroundNotification=UISceneWillEnterForegroundNotification',
		'IOS-SCENE-NATIVE: UISceneDidEnterBackgroundNotification=UISceneDidEnterBackgroundNotification'], false)!
	for log in ['host.log', 'host-deterministic.log'] {
		require_text(out, 'fixture/' + log, ['IOS-SCENE-NOTIFICATIONS: two native names, stable NSString pointer cells, eight concurrent first lookups, equal-name notification delivery, object filters, removal, pool survival and two drained runtimes'], false)!
	}
	require_text(out, 'imports.log', ['0x10DC981E0', '_UISceneWillEnterForegroundNotification'], false)!
	if digest(out + '/application/FortniteClient-IOS-Shipping')! != '6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373' {
		return error('unexpected application executable')
	}
	current := probe_state(out)!
	if os.read_file(out + '/host/probe-no-ads.status.txt')!.trim_space() != '1' { return error('unexpected host probe status') }
	for log in [current + '/serial.log', 'host/probe-no-ads.log'] {
		require_text(out, log, ['iOS startup: Swift image metadata', 'iOS startup: Objective-C +load',
			'iOS DIAGNOSTIC PROBE: binding /System/Library/Frameworks/StoreKit.framework/StoreKit _OBJC_CLASS_$_SKAdNetwork to nil',
			'iOS startup: initializers for ',
			'iOS: unimplemented Objective-C method NSData dataWithContentsOfURL:'], true)!
		text := os.read_file(out + '/' + log)!
		mut last := -1
		for name in ['FIRMessaging', 'FIRInstallations', 'GDTCCTUploader', 'GDTCORFlatFileStorage',
			'GDTCORLifecycle', 'GDTCORMetricsController', 'GDTCORApplication', 'iOSConfigRuleProviders', 'fortConfigRuleProvider'] {
			position := text.index('iOS +load: ' + name + ' at ') or { return error('missing +load ' + name) }
			if position <= last { return error('out-of-order +load') }
			last = position
		}
		first_initializer := text.index('iOS startup: initializers for ') or { return error('missing initializer stage') }
		if first_initializer <= last || text.count('iOS +load: ') != 9
			|| text.count('iOS startup: initializers for ') != 3 { return error('unexpected startup sequence') }
		if text.contains('iOS startup: application entry') { return error('unexpected application entry') }
	}
	require_text(out, 'host/probe-no-ads.log', ['iOS: unimplemented Objective-C method NSProcessInfo physicalMemory'], true)!
	require_text(out, current + '/serial.log', ['iOS: unimplemented Objective-C method NSProcessInfo physicalMemory',
		'IOS-NATIVE: /opt/ios/run-ios wait status 256', 'FORTNITE PROBE: process exit status 1', 'FORTNITE PROBE COMPLETE'], true)!
}

fn seal(out string) ! {
	results(out)!
	mut lines := []string{}
	for path in files(out, '')! {
		if path != 'manifest.sha256' { lines << digest(out + '/' + path)! + '  ' + path }
	}
	os.write_file(out + '/manifest.sha256', lines.join('\n') + '\n')!
}

fn check(out string) ! {
	mut seen := map[string]bool{}
	lines := os.read_lines(out + '/manifest.sha256')!
	for line in lines {
		if line.len < 67 || line[64..66] != '  ' { return error('invalid manifest record') }
		hash := line[..64]; path := line[66..]
		if hash.bytes().any(!it.is_hex_digit()) || !safe_path(path) || path == 'manifest.sha256' || path in seen {
			return error('unsafe or duplicate manifest path')
		}
		seen[path] = true
	}
	actual := files(out, '')!
	if actual.len != seen.len + 1 { return error('manifest file count mismatch') }
	for path in actual {
		if path != 'manifest.sha256' && path !in seen { return error('unmanifested file: ' + path) }
	}
	for line in lines {
		if digest(out + '/' + line[66..])! != line[..64] { return error('checksum mismatch: ' + line[66..]) }
	}
	results(out)!
}

fn reject_missing(out string) ! {
	path := out + '/' + probe_state(out)! + '/boot.img'; backup := path + '.selftest'
	if os.exists(backup) { return error('selftest backup already exists') }
	os.mv(path, backup)!
	defer { os.mv(backup, path) or { panic(err) } }
	check(out) or { println('missing guest media: rejected'); return }
	return error('missing guest media passed')
}

fn reject_tamper(out string) ! {
	path := out + '/fixture/host.log'; original := os.read_file(path)!
	defer { os.write_file(path, original) or { panic(err) } }
	os.write_file(path, original + '\nSELFTEST-TAMPER\n')!
	check(out) or { println('changed log: rejected'); return }
	return error('changed log passed')
}

fn reject_extra(out string) ! {
	path := out + '/selftest-unmanifested.txt'
	if os.exists(path) { return error('selftest extra file already exists') }
	os.write_file(path, 'unmanifested\n')!
	defer { os.rm(path) or { panic(err) } }
	check(out) or { println('unmanifested file: rejected'); return }
	return error('unmanifested file passed')
}

fn main() {
	if os.args.len != 3 { eprintln('usage: scene-notifications-evidence seal|check|selftest DIR | hash FILE'); exit(2) }
	if os.args[1] == 'hash' {
		println(digest(os.args[2]) or { eprintln(err); exit(1) })
		return
	}
	out := os.real_path(os.args[2]); root := os.real_path(os.getwd())
	if !os.is_dir(out) || out == root || out.starts_with(root + '/') { eprintln('evidence directory must exist outside the repository'); exit(2) }
	match os.args[1] {
		'seal' { seal(out) or { eprintln(err); exit(1) } }
		'check' { check(out) or { eprintln(err); exit(1) } }
		'selftest' {
			check(out) or { eprintln(err); exit(1) }
			reject_missing(out) or { eprintln(err); exit(1) }
			reject_tamper(out) or { eprintln(err); exit(1) }
			reject_extra(out) or { eprintln(err); exit(1) }
			check(out) or { eprintln(err); exit(1) }
		}
		else { eprintln('unknown mode'); exit(2) }
	}
	println('Scene notifications evidence ' + os.args[1] + ': PASS (application still fails during image initialization)')
}
