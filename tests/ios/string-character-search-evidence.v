// SPDX-License-Identifier: GPL-2.0-or-later
// Complete external evidence for NSString character search and the next +load fault.
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

fn require_text(out string, path string, markers []string) ! {
	text := os.read_file(out + '/' + path)!.replace('\r\n', '\n')
	for marker in markers {
		if !text.contains(marker) { return error(path + ': missing ' + marker) }
	}
	for bad in ['ERROR: AddressSanitizer', 'runtime error:', '> assert ', 'KERNEL PANIC',
		'FATAL EXCEPTION', 'V panic:', 'IOS-NATIVE: FAIL', 'iOS FAIL:'] {
		if text.contains(bad) { return error(path + ': ' + bad) }
	}
}

const search_markers = [
	'IOS-STRING-CHARACTER-SEARCH: UTF16 range ABI, full Unicode/NUL/combining input, first match, mutable inputs, nil receiver, image UTF8/UTF16 constants, 16MiB boundary and two drained runtimes',
	'IOS-STRING-CHARACTER-SEARCH-NATIVE: identical metadata and 176 Unicode searches plus mutable sets/strings and nil receiver',
	'IOS-STRING-CHARACTER-SEARCH-REJECT: 23 invalid receiver, constant, UTF8, size and character set inputs fail explicitly',
]

fn probe_state(out string, pointer string) !string {
	state := os.file_name(os.read_file(out + '/' + pointer)!.trim_space())
	if !state.starts_with('probe-no-ads-') || state.split('/').any(it in ['', '.', '..']) {
		return error('invalid VM pointer')
	}
	for file in ['boot.img', 'efivars.fd', 'initramfs.tar.gz', 'limine.conf', 'serial.log'] {
		if !os.is_file(out + '/' + state + '/' + file) { return error('missing VM artifact ' + state + '/' + file) }
	}
	return state
}

fn results(out string) ! {
	for name in ['source-revision.txt'] {
		revision := os.read_file(out + '/' + name)!.trim_space()
		if revision.len != 40 || revision.bytes().any(!it.is_hex_digit()) { return error('invalid source revision') }
	}
	for file in ['source/compat/ios/runner/ns_string_character_search.c.v',
		'source/compat/ios/runner/ns_string_character_search_test.v',
		'source/compat/ios/runner/objc_lifecycle.c.v', 'source/tests/ios/native-init.v',
		'source/tests/ios/notification-checks.v', 'source/tests/ios/notification-vm.v',
		'source/tests/ios/string-character-search-evidence.v',
		'source/tests/ios/image-initializers-input-inventory.v',
		'source/tests/ios/startup-host.v', 'source/tests/ios/inspect-string-character-search.v',
		'source-files.txt', 'build-inputs.sha256', 'notification-checks', 'notification-vm',
		'string-character-search-evidence', 'inventory-inputs', 'startup-host-tool',
		'inspect-string-character-search', 'inspect-string-character-search.log', 'load-debug.log',
		'next-boundary-disassembly.log', 'application/FortniteClient-IOS-Shipping',
		'application/Frameworks/EOSSDK.framework/EOSSDK',
		'application/Frameworks/MarketplaceKitWrapper.framework/MarketplaceKitWrapper',
		'string-character-search/payload/center-host.c',
		'string-character-search/NotificationChecks.app/Contents/Info.plist',
		'string-character-search/NotificationChecks.app/Contents/MacOS/center-host'] {
		if !os.is_file(out + '/' + file) { return error('missing ' + file) }
	}
	mut seen := map[string]bool{}
	for path in os.read_lines(out + '/source-files.txt')! {
		if path.starts_with('/') || path.contains('\\') || path.split('/').any(it in ['', '.', '..']) || path in seen { return error('invalid source path') }
		seen[path] = true
		if !os.is_file(out + '/source/' + path) { return error('missing source ' + path) }
	}
	if seen.len == 0 { return error('empty source inventory') }
	for i in 0 .. 4 {
		for prefix in ['', 'updated-host/', 'string-character-search/payload/'] {
			if !os.is_file(out + '/' + prefix + 'host-' + i.str() + '.o') { return error('missing host object') }
		}
	}
	for item in ['native-init', 'run-ios-gles'] {
		for suffix in ['', '.c'] {
			if !os.is_file(out + '/' + item + suffix) { return error('missing ' + item + suffix) }
		}
	}
	for prefix in ['', 'updated-host/'] {
		for file in ['startup-host.c', 'run-ios-host'] {
			if !os.is_file(out + '/' + prefix + file) { return error('missing ' + prefix + file) }
		}
	}
	mut labels := ['build-init', 'build-run-ios-gles', 'probe-no-ads']
	for prefix in ['', 'updated-host/'] {
		for label in ['generate', 'object-0', 'object-1', 'object-2', 'object-3', 'link'] { labels << prefix + label }
	}
	for label in ['host-generate', 'host-object-0', 'host-object-1', 'host-object-2', 'host-object-3', 'host-link', 'host', 'host-deterministic'] {
		labels << 'string-character-search/' + label
	}
	for label in labels {
		if os.read_file(out + '/' + label + '.status.txt')!.trim_space() != '0' { return error(label + ' failed') }
		require_text(out, label + '.log', ['COMMAND: '])!
	}
	for log in ['host.log', 'host-deterministic.log'] {
		require_text(out, 'string-character-search/' + log, search_markers)!
	}
	require_text(out, 'load-debug.log', ['rangeOfCharacterFromSet:', '0x00000000000007c8'])!
	require_text(out, 'inspect-string-character-search.log', ['TYPES: {_NSRange=QQ}24@0:8@16', 'SEARCH:'])!
	if digest(out + '/application/FortniteClient-IOS-Shipping')! != '6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373' {
		return error('unexpected application executable')
	}
	current := probe_state(out, 'probe-no-ads-state.txt')!
	require_text(out, current + '/serial.log', ['IOS-NATIVE: /opt/ios/run-ios wait status 35584',
		'FORTNITE PROBE: process exit status 139', 'FORTNITE PROBE COMPLETE', 'signal 11: segmentation fault'])!
	if os.read_file(out + '/updated-host/probe-no-ads.status.txt')!.trim_space() != '134' {
		return error('unexpected host probe status')
	}
	host := os.read_file(out + '/updated-host/probe-no-ads.log')!
	// This is an expected *application failure*, not a sanitizer-clean launch.
	if host.count('ERROR: AddressSanitizer:') != 1
		|| !host.contains('ERROR: AddressSanitizer: SEGV on unknown address 0x000000000000')
		|| !host.contains('pc 0x00013d69f674') || !host.contains('iOS Mach-O mapping: 0x13d604000')
		|| !host.contains('block_invoke_void') || !host.contains('dispatch_once_run') {
		return error('host probe did not reach the recorded null-read boundary')
	}
	for log in [current + '/serial.log', 'updated-host/probe-no-ads.log'] {
		text := os.read_file(out + '/' + log)!
		mut last := -1
		for name in ['FIRMessaging', 'FIRInstallations', 'GDTCCTUploader', 'GDTCORFlatFileStorage',
			'GDTCORLifecycle', 'GDTCORMetricsController', 'GDTCORApplication'] {
			position := text.index('iOS +load: ' + name + ' at ') or { return error('missing +load ' + name) }
			if position <= last { return error('out-of-order +load') }
			last = position
		}
		for marker in ['iOS startup: Swift image metadata', 'iOS startup: Objective-C +load',
			'iOS DIAGNOSTIC PROBE: binding /System/Library/Frameworks/StoreKit.framework/StoreKit _OBJC_CLASS_$_SKAdNetwork to nil'] {
			if !text.contains(marker) { return error('missing startup marker ' + marker) }
		}
		for unexpected in ['runtime error:', 'V panic:', 'KERNEL PANIC', 'iOS: object has no live runtime metadata',
			'iOS startup: initializers for ', 'iOS startup: application entry'] {
			if text.contains(unexpected) { return error('unexpected probe stage: ' + unexpected) }
		}
	}
}

fn seal(out string) ! {
	results(out)!
	mut lines := []string{}
	for path in files(out, '')! {
		if path == 'manifest.sha256' { continue }
		lines << digest(out + '/' + path)! + '  ' + path
	}
	os.write_file(out + '/manifest.sha256', lines.join('\n') + '\n')!
}

fn check(out string) ! {
	mut seen := map[string]bool{}
	lines := os.read_lines(out + '/manifest.sha256')!
	for line in lines {
		if line.len < 67 || line[64..66] != '  ' { return error('invalid manifest record') }
		hash := line[..64]; path := line[66..]
		if hash.bytes().any(!it.is_hex_digit()) || path.starts_with('/') || path.contains('\\')
			|| path.split('/').any(it in ['', '.', '..']) || path == 'manifest.sha256' || path in seen {
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
	state := os.file_name(os.read_file(out + '/probe-no-ads-state.txt')!.trim_space())
	path := out + '/' + state + '/boot.img'; backup := path + '.selftest'
	if os.exists(backup) { return error('selftest backup already exists') }
	os.mv(path, backup)!
	defer { os.mv(backup, path) or { panic(err) } }
	check(out) or { println('missing guest media: rejected'); return }
	return error('missing guest media passed')
}

fn reject_tamper(out string) ! {
	path := out + '/string-character-search/host.log'; original := os.read_file(path)!
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
	if os.args.len != 3 { eprintln('usage: string-character-search-evidence seal|check|selftest DIR | hash FILE'); exit(2) }
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
	println('String character search evidence ' + os.args[1] + ': PASS (application still faults in GDTCORApplication +load)')
}
