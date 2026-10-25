// SPDX-License-Identifier: GPL-2.0-or-later
// Complete, external evidence for the AVAudioApplication startup checkpoint.
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

const runtime_marker = 'IOS-AUDIO-APPLICATION: scoped imports, 24-byte singleton, typed reflection, denied record permission, synchronous false completions, callback reentry, four readers and two drained runtimes'
const rejection_marker = 'IOS-AUDIO-APPLICATION-REJECT: 19 construction, caller storage, subclass, isa, destruction, retirement, nil completion and unsupported input cases fail explicitly'

fn results(out string) ! {
	revision := os.read_file(out + '/source-revision.txt')!.trim_space()
	if revision.len != 40 || revision.bytes().any(!it.is_hex_digit()) { return error('invalid source revision') }
	for file in ['source/compat/ios/runner/audio_application.c.v',
		'source/compat/ios/runner/audio_application_test.v', 'source/compat/ios/runner/objc.c.v',
		'source/compat/ios/runner/frameworks.c.v', 'source/compat/ios/runner/objc_runtime.c.v',
		'source/compat/ios/runner/objc_storage.c.v', 'source/compat/ios/runner/scenes.c.v',
		'source/compat/ios/runner/uikit.v', 'source/tests/ios/native-checks.v',
		'source/tests/ios/native-init.v', 'source/tests/ios/notification-checks.v',
		'source/tests/ios/notification-vm.v', 'source/tests/ios/inspect-audio-application.v',
		'source/tests/ios/inspect-user-notifications.v', 'build-inputs.sha256',
		'notification-checks', 'notification-vm', 'native-checks',
		'inspect-audio-application', 'inspect-user-notifications',
		'audio-application-evidence.v', 'inventory-inputs.v',
		'payload/center-host.c', 'NotificationChecks.app/Contents/Info.plist',
		'NotificationChecks.app/Contents/MacOS/center-host'] {
		if !os.is_file(out + '/' + file) { return error('missing ' + file) }
	}
	for i in 0 .. 4 {
		if !os.is_file(out + '/payload/host-' + i.str() + '.o') { return error('missing host object') }
	}
	for item in ['audio-application-checks', 'native-init', 'run-ios-gles'] {
		for suffix in ['', '.c'] {
			if !os.is_file(out + '/' + item + suffix) { return error('missing ' + item + suffix) }
		}
	}
	for label in ['host-generate', 'host-object-0', 'host-object-1', 'host-object-2', 'host-object-3',
		'host-link', 'host', 'host-deterministic', 'build-audio-application', 'build-init',
		'build-run-ios-gles', 'audio-application', 'probe', 'AVAudioApplication-metadata',
		'audio-application-inspect', 'driver-build'] {
		if os.read_file(out + '/' + label + '.status.txt')!.trim_space() != '0' { return error(label + ' failed') }
		require_text(out, label + '.log', ['COMMAND: '])!
	}
	for log in ['host.log', 'host-deterministic.log'] {
		require_text(out, log, [runtime_marker, rejection_marker])!
	}
	require_text(out, 'AVAudioApplication-metadata.log', ['AVAudioApplication SIZE 24 PARENT NSObject',
		'IVAR _impl ', 'IVAR _inputMuted B 16',
		'METHOD + sharedInstance @16@0:8',
		'METHOD - recordPermission q16@0:8', 'METHOD - isInputMuted B16@0:8',
		'METHOD + requestRecordPermissionWithCompletionHandler: v24@0:8@?16',
		'METHOD - requestRecordPermissionWithCompletionHandler: v24@0:8@?16',
		'METHOD - microphoneInjectionPermission q16@0:8',
		'METHOD + requestMicrophoneInjectionPermissionWithCompletionHandler: v24@0:8@?16',
		'METHOD - setInputMuted:error: B28@0:8B16^@20',
		'METHOD - setInputMuted:context:error: B36@0:8B16@20^@28',
		'METHOD - setInputMuteStateChangeHandler:error: B32@0:8@?16^@24'])!
	require_text(out, 'audio-application-inspect.log', [
		'AVAudioApplication recordPermission=756e6474 isInputMuted=0',
		'IOS-AUDIO-APPLICATION-INSPECT: 24-byte NSObject singleton, scoped native symbols and read-only permission and mute queries'])!
	for mode in ['audio-application', 'probe'] {
		state := os.file_name(os.read_file(out + '/' + mode + '-state.txt')!.trim_space())
		if !state.starts_with(mode + '-') || state.split('/').any(it in ['', '.', '..']) { return error('invalid VM pointer') }
		for file in ['boot.img', 'efivars.fd', 'initramfs.tar.gz', 'limine.conf', 'serial.log'] {
			if !os.is_file(out + '/' + state + '/' + file) { return error('missing VM artifact ' + state + '/' + file) }
		}
		if mode == 'audio-application' {
			require_text(out, state + '/serial.log', [runtime_marker, rejection_marker,
				'IOS-NATIVE: /opt/ios/audio-application-checks wait status 0', 'VINIX iOS AUDIOAPPLICATION: PASS'])!
		} else {
			require_text(out, state + '/serial.log', ['iOS: linking /opt/ios/FortniteClient-IOS-Shipping:',
				next_blocker, 'IOS-NATIVE: /opt/ios/run-ios wait status 256',
				'FORTNITE PROBE: process exit status 1', 'FORTNITE PROBE COMPLETE'])!
		}
	}
}

const next_blocker = 'iOS: framework symbol is not implemented: _OBJC_CLASS_$_UIStoryboard'

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
	state := os.file_name(os.read_file(out + '/audio-application-state.txt')!.trim_space())
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
	if os.args.len != 3 { eprintln('usage: audio-application-evidence seal|check|selftest DIR'); exit(2) }
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
	println('AVAudioApplication evidence ' + os.args[1] + ': PASS')
}
