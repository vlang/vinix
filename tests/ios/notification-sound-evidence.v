// SPDX-License-Identifier: GPL-2.0-or-later
// Seal/check complete notification-sound evidence outside the source tree.
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

fn capture(args []string) !string {
	mut p := os.new_process(args[0])
	p.set_args(args[1..]); p.set_redirect_stdio_merged(); p.run()
	output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	if code != 0 { return error(args.join(' ') + ': ' + output) }
	return output
}

fn require_text(out string, path string, markers []string) ! {
	text := os.read_file(out + '/' + path)!
	for marker in markers {
		if !text.contains(marker) { return error(path + ': missing ' + marker) }
	}
	for bad in ['ERROR: AddressSanitizer', 'runtime error:', '> assert ', 'KERNEL PANIC', 'IOS-NATIVE: FAIL', 'iOS FAIL:'] {
		if text.contains(bad) { return error(path + ': ' + bad) }
	}
}

fn results(out string) ! {
	revision := os.read_file(out + '/source-revision.txt')!.trim_space()
	if revision.len != 40 || revision.bytes().any(!it.is_hex_digit()) { return error('invalid source revision') }
	for file in ['source/compat/ios/runner/un_notification_sound.c.v',
		'source/compat/ios/runner/un_notification_sound_test.v',
		'source/tests/ios/notification-sound-evidence.v', 'build-inputs.sha256',
		'notification-sound-evidence', 'notification-checks', 'notification-vm', 'inspect-notification-sound', 'inspect-user-notifications',
		'payload/center-host.c', 'NotificationChecks.app/Contents/Info.plist',
		'NotificationChecks.app/Contents/MacOS/center-host'] {
		if !os.is_file(out + '/' + file) { return error('missing ' + file) }
	}
	for i in 0 .. 4 {
		if !os.is_file(out + '/payload/host-' + i.str() + '.o') { return error('missing host object') }
	}
	for item in ['calendar-checks', 'calendar-trigger-checks', 'notification-request-checks',
		'notification-center-checks', 'notification-content-checks', 'notification-sound-checks', 'native-init', 'run-ios', 'run-ios-gles'] {
		for suffix in ['', '.c'] {
			if !os.is_file(out + '/' + item + suffix) { return error('missing ' + item + suffix) }
		}
	}
	for label in ['inspect', 'inspect-metadata', 'host-generate', 'host-object-0', 'host-object-1', 'host-object-2',
		'host-object-3', 'host-link', 'host', 'host-deterministic', 'build', 'notifications', 'probe', 'audit', 'static-audit'] {
		if os.read_file(out + '/' + label + '.status.txt')!.trim_space() != '0' { return error(label + ' failed') }
		require_text(out, label + '.log', ['COMMAND: '])!
	}
	require_text(out, 'inspect.log', ['DURATION maximum=0.0', 'SOUND defaultSound name=<nil> type=17 volume=0',
		'COPY self=true default-again=false',
		'DEFAULT topic=<nil> category=<nil> identifier=<nil> critical=0 ringer=0 repeat=0 accessibility=0',
		'NAMED  before= after= copy-self=true type=17',
		'NAMED alert.caf before=alert.caf after=alert.caf copy-self=true type=17',
		'NAMED é😀.wav before=é😀.wav after=é😀.wav copy-self=true type=17',
		'CONTENT same=true snapshot-same=true', 'NIL object=true name=<nil> type=17'])!
	require_text(out, 'inspect-metadata.log', ['UNNotificationSound SIZE 104 PARENT NSObject',
		'METHOD - copyWithZone: @24@0:8^{_NSZone=}16', 'METHOD - maximumDuration d16@0:8',
		'METHOD + defaultSound @16@0:8', 'METHOD + soundNamed: @24@0:8@16'])!
	for record in ['_alertType q 8', '_alertTopic @"NSString" 16', '_audioCategory @"NSString" 24',
		'_audioVolume @"NSNumber" 32', '_maximumDuration d 40', '_critical B 48',
		'_shouldIgnoreAccessibilityDisabledVibrationSetting B 49', '_shouldIgnoreRingerSwitch B 50',
		'_shouldRepeat B 51', '_toneFileName @"NSString" 56', '_toneFileURL @"NSURL" 64',
		'_toneIdentifier @"NSString" 72', '_toneMediaLibraryItemIdentifier Q 80',
		'_vibrationIdentifier @"NSString" 88', '_vibrationPatternFileURL @"NSURL" 96'] {
		require_text(out, 'inspect-metadata.log', ['IVAR ' + record])!
	}
	for log in ['host.log', 'host-deterministic.log'] {
		require_text(out, log, ['IOS-UN-SOUND-NATIVE: layout, encodings, defaults, nil names, UTF8 snapshots, immutable copies and content/request ownership PASS',
			'IOS-UN-SOUND: native parity, reentrant and failed constructors, caller storage, isa cleanup, associated copies, native overrides and two balanced lifetimes PASS',
			'IOS-UN-SOUND-REJECT: 33 invalid values, provenance, constructors, copies and unsupported API cases PASS'])!
	}
	mut states := map[string]bool{}
	for mode in ['notifications', 'probe', 'audit', 'static-audit'] {
		state := os.file_name(os.read_file(out + '/' + mode + '-state.txt')!.trim_space())
		if !state.starts_with(mode + '-') || state in states { return error('invalid VM pointer') }
		states[state] = true
		for file in ['boot.img', 'efivars.fd', 'initramfs.tar.gz', 'limine.conf', 'serial.log'] {
			if !os.is_file(out + '/' + state + '/' + file) { return error('missing VM artifact ' + state + '/' + file) }
		}
		log := state + '/serial.log'
		if mode == 'notifications' {
			require_text(out, log, ['IOS-NS-CALENDAR:', 'IOS-NS-CALENDAR-REJECT:41 ', 'IOS-UN-CALENDAR:', 'IOS-UN-CALENDAR-REJECT: 21 ',
				'IOS-UN-REQUEST:', 'IOS-UN-REQUEST-REJECT: 28 ', 'IOS-UN-CENTER:',
				'IOS-UN-CENTER-REJECT: 31 ', 'IOS-UN-CONTENT:', 'IOS-UN-CONTENT-REJECT: 28 ',
				'IOS-UN-SOUND:', 'IOS-UN-SOUND-REJECT: 33 ', 'VINIX iOS NOTIFICATIONS: PASS'])!
		} else {
			require_text(out, log, ['FORTNITE PROBE: process exit status 1', 'FORTNITE PROBE COMPLETE'])!
			if mode == 'probe' {
				require_text(out, log, ['iOS: linking /opt/ios/FortniteClient-IOS-Shipping:',
					'UserNotifications (_OBJC_CLASS_$_UNNotificationAttachment)'])!
			} else {
				require_text(out, log, [if mode == 'audit' {
					'iOS IMPORT AUDIT: 2939 resolved, 65 unresolved strong, 114 unresolved weak (app code was not executed)'
				} else {
					'iOS IMPORT AUDIT: 2925 resolved, 79 unresolved strong, 114 unresolved weak (app code was not executed)'
				}])!
			}
		}
	}
}

fn snapshot(out string) ! {
	root := os.real_path(os.getwd())
	revision := capture(['git', 'rev-parse', 'HEAD'])!.trim_space()
	os.write_file(out + '/source-revision.txt', revision + '\n')!
	mut sources := capture(['git', 'ls-tree', '-r', '--name-only', revision, '--', 'compat/ios'])!.split_into_lines().filter(os.file_ext(it) in ['.v', '.c', '.h', '.S'])
	sources << ['tests/ios/native-checks.v', 'tests/ios/native-init.v', 'tests/ios/inspect-notification-sound.v',
		'tests/ios/inspect-user-notifications.v', 'tests/ios/notification-checks.v', 'tests/ios/notification-vm.v', 'tests/ios/notification-sound-evidence.v']
	for source in sources {
		text := capture(['git', 'show', revision + ':' + source])!
		os.mkdir_all(os.dir(out + '/source/' + source))!
		os.write_file(out + '/source/' + source, text)!
	}
	// Selected inputs only. The complete guest media is retained, but the host
	// dynamic-library and compiler header closures are not independently sealed.
	mut inputs := []string{}
	for path in [root + '/build/ios/fortnite/ns-calendar-checks/toolchain/v',
		root + '/build/ios/fortnite/socket-kernel-arm64/bin/vinix',
		root + '/build/ios/fortnite/date-encoding-checks/sdk/usr/lib/libc.a',
		root + '/build/ios/cxx/libcxx-ios.a', root + '/build/ios/cxx/sysroot/usr/lib/libc++abi.a',
		root + '/build/ios/cxx/sysroot/usr/lib/libunwind.a', root + '/build/ios/sqlite/arm64/libsqlite3.a',
		root + '/boot-image/limine-bin/BOOTAA64.EFI',
		'/opt/homebrew/share/qemu/edk2-aarch64-code.fd', '/opt/homebrew/bin/qemu-system-aarch64',
		'/opt/homebrew/opt/llvm/bin/clang', '/usr/bin/clang'] {
		inputs << digest(path)! + '  ' + path
	}
	os.write_file(out + '/build-inputs.sha256', inputs.join('\n') + '\n')!
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
	for line in os.read_lines(out + '/manifest.sha256')! {
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
	for line in os.read_lines(out + '/manifest.sha256')! {
		path := line[66..]
		if digest(out + '/' + path)! != line[..64] { return error('checksum mismatch: ' + path) }
	}
	results(out)!
}

fn reject_missing(out string) ! {
	state := os.file_name(os.read_file(out + '/notifications-state.txt')!.trim_space())
	path := out + '/' + state + '/boot.img'
	backup := path + '.selftest'
	if os.exists(backup) { return error('selftest backup already exists') }
	os.mv(path, backup)!
	defer { os.mv(backup, path) or { panic(err) } }
	check(out) or { println('missing guest media: rejected'); return }
	return error('missing guest media passed')
}

fn reject_tamper(out string) ! {
	path := out + '/inspect.log'
	original := os.read_file(path)!
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
	if os.args.len != 3 { eprintln('usage: notification-sound-evidence snapshot|seal|check|selftest|archive|archive-zstd DIR'); exit(2) }
	out := os.real_path(os.args[2]); root := os.real_path(os.getwd())
	if !os.is_dir(out) || out == root || out.starts_with(root + '/') { eprintln('evidence directory must exist outside the repository'); exit(2) }
	match os.args[1] {
		'snapshot' { snapshot(out) or { eprintln(err); exit(1) } }
		'seal' { seal(out) or { eprintln(err); exit(1) } }
		'check' { check(out) or { eprintln(err); exit(1) } }
		'selftest' {
			check(out) or { eprintln(err); exit(1) }
			reject_missing(out) or { eprintln(err); exit(1) }
			reject_tamper(out) or { eprintln(err); exit(1) }
			reject_extra(out) or { eprintln(err); exit(1) }
			check(out) or { eprintln(err); exit(1) }
		}
		'archive', 'archive-zstd' {
			check(out) or { eprintln(err); exit(1) }
			compact := os.args[1] == 'archive-zstd'
			archive := out + if compact { '.tar.zst' } else { '.tar.gz' }
			if os.exists(archive) { eprintln('archive already exists'); exit(1) }
			// A long compression window preserves complete repeated VM media
			// without requiring another full-size copy on the persistent disk.
			mut args := ['/usr/bin/tar']
			if compact {
				args << ['--use-compress-program', '/opt/homebrew/bin/zstd -T2 --long=31 -10', '-cf']
			} else { args << '-czf' }
			args << [archive, '-C', os.dir(out), os.file_name(out)]
			capture(args) or { eprintln(err); exit(1) }
			hash := digest(archive) or { eprintln(err); exit(1) }
			os.write_file(archive + '.sha256', hash + '  ' + os.file_name(archive) + '\n') or { eprintln(err); exit(1) }
			println(hash + '  ' + archive)
		}
		else { eprintln('unknown mode'); exit(2) }
	}
	println('notification evidence ' + os.args[1] + ': PASS')
}
