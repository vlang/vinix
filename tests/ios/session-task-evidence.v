// SPDX-License-Identifier: GPL-2.0-or-later
// Complete, external evidence for the URL session task startup checkpoint.
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

const runtime_marker = 'IOS-SESSION-TASK: four class imports and metadata, typed float ABI and saved IMPs, copied properties, eight concurrent writers/readers, guarded caller storage, isa changes, overrides and two drained runtimes'
const native_marker = 'IOS-SESSION-TASK-NATIVE: four 720-byte classes, hierarchy, base init/copy identity, copied description, signed client counts and float priority including nonfinite inputs'
const rejection_marker = 'IOS-SESSION-TASK-REJECT: fourteen unsupported operation, type, copy, subclass and spoof cases fail explicitly'

fn results(out string) ! {
	revision := os.read_file(out + '/source-revision.txt')!.trim_space()
	if revision.len != 40 || revision.bytes().any(!it.is_hex_digit()) { return error('invalid source revision') }
	for file in ['source/compat/ios/runner/ns_url_session_task.c.v', 'source/compat/ios/runner/ns_url_session_task_test.v',
		'source/compat/ios/runner/objc.c.v', 'source/tests/ios/native-checks.v',
		'source/tests/ios/native-init.v', 'source/tests/ios/notification-checks.v',
		'source/tests/ios/notification-vm.v', 'build-inputs.sha256', 'notification-checks', 'notification-vm',
		'source/tests/ios/inspect-session-task.v', 'source/tests/ios/inspect-user-notifications.v',
		'inspect-session-task', 'inspect-user-notifications', 'session-task-evidence.v',
		'payload/center-host.c', 'NotificationChecks.app/Contents/Info.plist',
		'NotificationChecks.app/Contents/MacOS/center-host'] {
		if !os.is_file(out + '/' + file) { return error('missing ' + file) }
	}
	for i in 0 .. 4 {
		if !os.is_file(out + '/payload/host-' + i.str() + '.o') { return error('missing host object') }
	}
	for item in ['session-task-checks', 'native-init', 'run-ios-gles'] {
		for suffix in ['', '.c'] {
			if !os.is_file(out + '/' + item + suffix) { return error('missing ' + item + suffix) }
		}
	}
	for label in ['host-generate', 'host-object-0', 'host-object-1', 'host-object-2', 'host-object-3',
		'host-link', 'host', 'host-deterministic', 'build-session-task', 'build-init', 'build-run-ios-gles',
		'session-task', 'probe'] {
		if os.read_file(out + '/' + label + '.status.txt')!.trim_space() != '0' { return error(label + ' failed') }
		require_text(out, label + '.log', ['COMMAND: '])!
	}
	for log in ['host.log', 'host-deterministic.log'] {
		require_text(out, log, [native_marker, runtime_marker, rejection_marker])!
	}
	for index, name in ['NSURLSessionTask', 'NSURLSessionDownloadTask', 'NSURLSessionDataTask', 'NSURLSessionUploadTask']! {
		for mode in ['metadata', 'new', 'init', 'copy', 'copyWithZone', 'priority', 'description', 'lifecycle', 'counts', 'originalRequest', 'currentRequest', 'response', 'error', 'state', 'taskIdentifier']! {
			label := name + '-' + mode
			if os.read_file(out + '/' + label + '.status.txt')!.trim_space() != '0' { return error(label + ' failed') }
			require_text(out, label + '.log', ['COMMAND: '])!
		}
		parent := ['NSObject', 'NSURLSessionTask', 'NSURLSessionTask', 'NSURLSessionDataTask']![index]
		require_text(out, name + '-metadata.log', [name + ' SIZE 720 PARENT ' + parent])!
		require_text(out, name + '-priority.log', ['priority=0.0', 'set bits=3212836864: bits=0',
			'set bits=1048576000: bits=1048576000', 'set bits=1073741824: bits=1048576000',
			'set bits=2143289344: bits=2143289344', 'set bits=2139095040: bits=2143289344',
			'set bits=4286578688: bits=2143289344', 'set bits=1065353216: bits=1065353216', 'set bits=0: bits=0'])!
		require_text(out, name + '-description.log', ['description identity=false', 'description=task'])!
		require_text(out, name + '-counts.log', ['countOfBytesClientExpectsToSend=0',
			'countOfBytesClientExpectsToReceive=0', 'set -1: -1', 'set 42: 42', 'set -2: -2'])!
		// These are diagnostic child results, not proof of safe lifecycle support.
		require_text(out, name + '-lifecycle.log', ['resume delayed child status=', 'suspend delayed child status='])!
	}
	for mode in ['session-task', 'probe'] {
		state := os.file_name(os.read_file(out + '/' + mode + '-state.txt')!.trim_space())
		if !state.starts_with(mode + '-') || state.split('/').any(it in ['', '.', '..']) { return error('invalid VM pointer') }
		for file in ['boot.img', 'efivars.fd', 'initramfs.tar.gz', 'limine.conf', 'serial.log'] {
			if !os.is_file(out + '/' + state + '/' + file) { return error('missing VM artifact ' + state + '/' + file) }
		}
		if mode == 'session-task' {
			require_text(out, state + '/serial.log', [runtime_marker, rejection_marker,
				'IOS-NATIVE: /opt/ios/session-task-checks wait status 0', 'VINIX iOS SESSIONTASK: PASS'])!
		} else {
			require_text(out, state + '/serial.log', ['iOS: linking /opt/ios/FortniteClient-IOS-Shipping:',
				next_blocker,
				'IOS-NATIVE: /opt/ios/run-ios wait status 256',
				'FORTNITE PROBE: process exit status 1', 'FORTNITE PROBE COMPLETE'])!
		}
	}
}

// Exact failure captured after satisfying the URL session task class imports.
const next_blocker = 'iOS: library is not implemented: /System/Library/Frameworks/GameController.framework/GameController (_OBJC_CLASS_$_GCController)'

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
	state := os.file_name(os.read_file(out + '/session-task-state.txt')!.trim_space())
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
	if os.args.len != 3 { eprintln('usage: session-task-evidence seal|check|selftest DIR'); exit(2) }
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
	println('session task evidence ' + os.args[1] + ': PASS')
}
