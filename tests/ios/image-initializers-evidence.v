// SPDX-License-Identifier: GPL-2.0-or-later
// Complete, external evidence for the image initializer table checkpoint.
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
	require_text_with_panic(out, path, markers, '')!
}

fn require_text_with_panic(out string, path string, markers []string, expected_panic string) ! {
	mut text := os.read_file(out + '/' + path)!.replace('\r\n', '\n')
	for marker in markers {
		if !text.contains(marker) { return error(path + ': missing ' + marker) }
	}
	// The real application probe is expected to fail at this exact next blocker.
	// Remove one matching line; any other or repeated panic still fails the check.
	if expected_panic != '' {
		line := 'V panic: ' + expected_panic + '\n'
		if !text.contains(line) { return error(path + ': missing expected panic') }
		text = text.replace_once(line, '')
	}
	for bad in ['ERROR: AddressSanitizer', 'runtime error:', '> assert ', 'KERNEL PANIC',
		'FATAL EXCEPTION', 'V panic:', 'IOS-NATIVE: FAIL', 'iOS FAIL:'] {
		if text.contains(bad) { return error(path + ': ' + bad) }
	}
}

const initializer_marker = 'IOS-IMAGE-INITIALIZERS: 176816 Fortnite offsets, old/new count boundaries, readonly offset/pointer tables, aggregate routines/initializer/terminator limit, malformed/file-backed/executable/alignment rejection and ordered collection: PASS'

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
	for name in ['source-revision.txt', 'baseline-source-revision.txt'] {
		revision := os.read_file(out + '/' + name)!.trim_space()
		if revision.len != 40 || revision.bytes().any(!it.is_hex_digit()) { return error('invalid source revision') }
	}
	for file in ['source/compat/ios/runner/lifecycle.c.v',
		'source/compat/ios/runner/image_initializers_test.v',
		'source/compat/ios/runner/native.c.v', 'source/tests/ios/native-init.v',
		'source/tests/ios/notification-checks.v', 'source/tests/ios/notification-vm.v',
		'source/tests/ios/image-initializers-evidence.v',
		'source/tests/ios/image-initializers-input-inventory.v',
		'baseline-lifecycle.c.v', 'source-files.txt', 'build-inputs.sha256',
		'notification-checks', 'baseline-notification-checks', 'notification-vm',
		'image-initializers-evidence.v', 'inventory-inputs.v',
		'payload/center-host.c', 'NotificationChecks.app/Contents/Info.plist',
		'NotificationChecks.app/Contents/MacOS/center-host'] {
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
		if !os.is_file(out + '/payload/host-' + i.str() + '.o') { return error('missing host object') }
	}
	for item in ['native-init', 'baseline-run-ios-gles', 'run-ios-gles'] {
		for suffix in ['', '.c'] {
			if !os.is_file(out + '/' + item + suffix) { return error('missing ' + item + suffix) }
		}
	}
	for label in ['host-generate', 'host-object-0', 'host-object-1', 'host-object-2', 'host-object-3',
		'host-link', 'host', 'host-deterministic', 'build-init',
		'baseline-build-run-ios-gles', 'build-run-ios-gles', 'baseline-probe-no-ads', 'probe-no-ads'] {
		if os.read_file(out + '/' + label + '.status.txt')!.trim_space() != '0' { return error(label + ' failed') }
		require_text(out, label + '.log', ['COMMAND: '])!
	}
	for log in ['host.log', 'host-deterministic.log'] {
		require_text(out, log, [initializer_marker])!
	}
	baseline := probe_state(out, 'baseline-probe-no-ads-state.txt')!
	current := probe_state(out, 'probe-no-ads-state.txt')!
	if baseline == current { return error('baseline and current VM must differ') }
	common := ['iOS DIAGNOSTIC PROBE: binding /System/Library/Frameworks/StoreKit.framework/StoreKit _OBJC_CLASS_$_SKAdNetwork to nil',
		'iOS startup: registering Objective-C metadata for /opt/ios/FortniteClient-IOS-Shipping',
		'IOS-NATIVE: /opt/ios/run-ios wait status 256', 'FORTNITE PROBE: process exit status 1',
		'FORTNITE PROBE COMPLETE']
	require_text(out, baseline + '/serial.log', common)!
	require_text(out, baseline + '/serial.log', ['iOS: invalid initializer section'])!
	if os.read_file(out + '/' + baseline + '/serial.log')!.contains('iOS startup: Swift image metadata') {
		return error('baseline unexpectedly passed initializer collection')
	}
	next_blocker := 'iOS: object has no live runtime metadata'
	require_text_with_panic(out, current + '/serial.log', common, next_blocker)!
	require_text_with_panic(out, current + '/serial.log', ['iOS startup: Swift image metadata',
		'iOS startup: Objective-C +load'], next_blocker)!
	serial := os.read_file(out + '/' + current + '/serial.log')!
	for unexpected in ['iOS: invalid initializer section', 'iOS startup: initializers for ',
		'iOS startup: application entry'] {
		if serial.contains(unexpected) { return error('unexpected probe stage: ' + unexpected) }
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
	path := out + '/host.log'; original := os.read_file(path)!
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
	if os.args.len != 3 { eprintln('usage: image-initializers-evidence seal|check|selftest DIR | hash FILE'); exit(2) }
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
	println('Image initializer table evidence ' + os.args[1] + ': PASS')
}
