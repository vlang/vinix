// SPDX-License-Identifier: GPL-2.0-or-later
// Complete, external evidence for the GKTurnBasedMatchmakerViewController metadata checkpoint.
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
	text := os.read_file(out + '/' + path)!
	for marker in markers {
		if !text.contains(marker) { return error(path + ': missing ' + marker) }
	}
	for bad in ['ERROR: AddressSanitizer', 'runtime error:', '> assert ', 'KERNEL PANIC',
		'FATAL EXCEPTION', 'V panic:', 'IOS-NATIVE: FAIL', 'iOS FAIL:'] {
		if text.contains(bad) { return error(path + ': ' + bad) }
	}
}

const runtime_marker = 'IOS-GAMECENTER: scoped class/metaclass imports, SDK inheritance, subclass metadata, truthful reflection and two drained runtimes'
const rejection_marker = 'IOS-GAMECENTER-REJECT: 48 dispatch, direct/caller allocation, subclass, saved NSObject IMP and isa cases fail explicitly'

fn results(out string) ! {
	revision := os.read_file(out + '/source-revision.txt')!.trim_space()
	if revision.len != 40 || revision.bytes().any(!it.is_hex_digit()) { return error('invalid source revision') }
	for file in ['source/compat/ios/runner/game_center.c.v',
		'source/compat/ios/runner/game_center_test.v', 'source/compat/ios/runner/objc.c.v',
		'source/compat/ios/runner/frameworks.c.v', 'source/compat/ios/runner/objc_runtime.c.v',
		'source/compat/ios/runner/objc_storage.c.v', 'source/compat/ios/runner/scenes.c.v',
		'source/compat/ios/runner/uikit.v', 'source/tests/ios/native-checks.v',
		'source/tests/ios/native-init.v', 'source/tests/ios/notification-checks.v',
		'source/tests/ios/notification-vm.v', 'source/tests/ios/inspect-gk-turn-based-matchmaker.v',
		'source/tests/ios/gk-turn-based-matchmaker-evidence.v',
		'source/tests/ios/gk-turn-based-matchmaker-input-inventory.v', 'build-inputs.sha256',
		'notification-checks', 'notification-vm', 'native-checks',
		'gk-turn-based-matchmaker-evidence.v', 'inventory-inputs.v', 'inspect-gk-turn-based-matchmaker',
		'payload/center-host.c', 'NotificationChecks.app/Contents/Info.plist',
		'NotificationChecks.app/Contents/MacOS/center-host'] {
		if !os.is_file(out + '/' + file) { return error('missing ' + file) }
	}
	for i in 0 .. 4 {
		if !os.is_file(out + '/payload/host-' + i.str() + '.o') { return error('missing host object') }
	}
	for item in ['game-center-checks', 'native-init', 'run-ios-gles'] {
		for suffix in ['', '.c'] {
			if !os.is_file(out + '/' + item + suffix) { return error('missing ' + item + suffix) }
		}
	}
	for label in ['host-generate', 'host-object-0', 'host-object-1', 'host-object-2', 'host-object-3',
		'host-link', 'host', 'host-deterministic', 'build-game-center', 'build-init',
		'build-run-ios-gles', 'game-center', 'probe', 'audit', 'driver-build', 'inspect-build', 'inspect'] {
		if os.read_file(out + '/' + label + '.status.txt')!.trim_space() != '0' { return error(label + ' failed') }
		require_text(out, label + '.log', ['COMMAND: '])!
	}
	for log in ['host.log', 'host-deterministic.log'] {
		require_text(out, log, [runtime_marker, rejection_marker])!
	}
	require_text(out, 'inspect.log', ['GKTurnBasedMatchmakerViewController PARENT UINavigationController METAPARENT UINavigationController',
		'GKGameCenterViewController PARENT UINavigationController METAPARENT UINavigationController',
		'UINavigationController PARENT UIViewController METAPARENT UIViewController',
		'IOS-GKMATCHMAKER-INSPECT: PASS (metadata only; no UI construction)'])!
	for mode in ['game-center', 'probe', 'audit'] {
		state := os.file_name(os.read_file(out + '/' + mode + '-state.txt')!.trim_space())
		if !state.starts_with(mode + '-') || state.split('/').any(it in ['', '.', '..']) { return error('invalid VM pointer') }
		for file in ['boot.img', 'efivars.fd', 'initramfs.tar.gz', 'limine.conf', 'serial.log'] {
			if !os.is_file(out + '/' + state + '/' + file) { return error('missing VM artifact ' + state + '/' + file) }
		}
		if mode == 'game-center' {
			require_text(out, state + '/serial.log', [runtime_marker, rejection_marker,
				'IOS-NATIVE: /opt/ios/game-center-checks wait status 0', 'VINIX iOS GAMECENTER: PASS'])!
		} else if mode == 'audit' {
			require_text(out, state + '/serial.log', ['iOS IMPORT AUDIT: 2989 resolved, 15 unresolved strong, 114 unresolved weak (app code was not executed)',
				'IOS-NATIVE: /opt/ios/run-ios wait status 256', 'FORTNITE PROBE: process exit status 1', 'FORTNITE PROBE COMPLETE'])!
		} else {
			require_text(out, state + '/serial.log', ['iOS: linking /opt/ios/FortniteClient-IOS-Shipping:',
				next_blocker, 'IOS-NATIVE: /opt/ios/run-ios wait status 256',
				'FORTNITE PROBE: process exit status 1', 'FORTNITE PROBE COMPLETE'])!
		}
	}
}

const next_blocker = 'iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)'

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
	state := os.file_name(os.read_file(out + '/game-center-state.txt')!.trim_space())
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
	if os.args.len != 3 { eprintln('usage: gk-turn-based-matchmaker-evidence seal|check|selftest DIR | hash FILE'); exit(2) }
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
	println('GKTurnBasedMatchmakerViewController evidence ' + os.args[1] + ': PASS')
}
