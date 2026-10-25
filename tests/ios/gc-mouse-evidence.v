// SPDX-License-Identifier: GPL-2.0-or-later
// Complete, external evidence for the GCMouse startup checkpoint.
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

const runtime_marker = 'IOS-GAME-CONTROLLER: scoped imports, typed class methods, immutable empty discovery, notification constants, four concurrent readers, inherited state, overrides, saved IMP and two drained runtimes'
const native_marker = 'IOS-GAME-CONTROLLER-NATIVE: 232-byte NSObject class, empty discovery, nil current, background flag and three notification values'
const rejection_marker = 'IOS-GAME-CONTROLLER-REJECT: ten construction, caller storage, subclass, copying, coding, factory and wireless discovery cases fail explicitly'
const gamepad_marker = 'IOS-GAMEPAD: four scoped class/metaclass imports, inherited metadata, honest method lookup, subclass overrides and two drained runtimes'
const native_gamepad_marker = 'IOS-GAMEPAD-NATIVE: physical, extended, DualShock and DualSense class imports, superclass links and 680/872/896/896-byte layouts'
const gamepad_rejection_marker = 'IOS-GAMEPAD-REJECT: 36 construction, caller storage, subclass, copying, coding and touchpad cases fail explicitly'
const color_native_marker = 'IOS-GC-COLOR-NATIVE: 24-byte NSObject, zero default, exact RGB float bits, independent copies and description'
const color_marker = 'IOS-GC-COLOR: scoped imports, float ABI and ivars, exact bits, copy ownership, caller storage, subclass overrides, saved IMP and two drained runtimes'
const color_rejection_marker = 'IOS-GC-COLOR-REJECT: eight mutable copying, coding, preset and incompatible storage cases fail explicitly'
const mouse_native_marker = 'IOS-GC-MOUSE-NATIVE: 40-byte NSObject, empty discovery, nil current and four notification values'
const mouse_marker = 'IOS-GC-MOUSE: scoped imports, typed class methods and ivars, immutable empty discovery, four constants, concurrent readers, subclass overrides, saved IMP and two drained runtimes'
const mouse_rejection_marker = 'IOS-GC-MOUSE-REJECT: nine construction, caller storage, subclass, copying, coding and input cases fail explicitly'

fn results(out string) ! {
	revision := os.read_file(out + '/source-revision.txt')!.trim_space()
	if revision.len != 40 || revision.bytes().any(!it.is_hex_digit()) { return error('invalid source revision') }
	for file in ['source/compat/ios/runner/game_controller.c.v', 'source/compat/ios/runner/game_controller_test.v',
		'source/compat/ios/runner/objc.c.v', 'source/compat/ios/runner/gc_color.c.v', 'source/tests/ios/native-checks.v',
		'source/tests/ios/native-init.v', 'source/tests/ios/notification-checks.v',
		'source/tests/ios/notification-vm.v', 'build-inputs.sha256', 'notification-checks', 'notification-vm', 'native-checks',
		'source/tests/ios/inspect-game-controller.v', 'source/tests/ios/inspect-user-notifications.v',
		'source/compat/ios/runner/frameworks.c.v', 'source/compat/ios/runner/objc_runtime.c.v',
		'source/compat/ios/runner/objc_storage.c.v', 'source/compat/ios/runner/scenes.c.v',
		'source/compat/ios/runner/uikit.v', 'inspect-game-controller',
		'inspect-user-notifications', 'inspect-gc-color', 'source/tests/ios/inspect-gc-color.v',
		'inspect-gc-mouse', 'source/tests/ios/inspect-gc-mouse.v',
		'gc-mouse-evidence.v', 'inventory-inputs.v',
		'payload/center-host.c', 'NotificationChecks.app/Contents/Info.plist',
		'NotificationChecks.app/Contents/MacOS/center-host'] {
		if !os.is_file(out + '/' + file) { return error('missing ' + file) }
	}
	for i in 0 .. 4 {
		if !os.is_file(out + '/payload/host-' + i.str() + '.o') { return error('missing host object') }
	}
	for item in ['game-controller-checks', 'native-init', 'run-ios-gles'] {
		for suffix in ['', '.c'] {
			if !os.is_file(out + '/' + item + suffix) { return error('missing ' + item + suffix) }
		}
	}
	for label in ['host-generate', 'host-object-0', 'host-object-1', 'host-object-2', 'host-object-3',
		'host-link', 'host', 'host-deterministic', 'build-game-controller', 'build-init', 'build-run-ios-gles',
		'game-controller', 'probe', 'GCController-metadata', 'inspect',
		'GCPhysicalInputProfile-metadata', 'GCExtendedGamepad-metadata', 'GCDualShockGamepad-metadata',
		'GCDualSenseGamepad-metadata', 'GCColor-metadata', 'gc-color-inspect',
		'GCMouse-metadata', 'gc-mouse-inspect'] {
		if os.read_file(out + '/' + label + '.status.txt')!.trim_space() != '0' { return error(label + ' failed') }
		require_text(out, label + '.log', ['COMMAND: '])!
	}
	for log in ['host.log', 'host-deterministic.log'] {
		require_text(out, log, [native_marker, runtime_marker, rejection_marker,
			native_gamepad_marker, gamepad_marker, gamepad_rejection_marker,
			color_native_marker, color_marker, color_rejection_marker,
			mouse_native_marker, mouse_marker, mouse_rejection_marker])!
	}
	require_text(out, 'GCMouse-metadata.log', ['GCMouse SIZE 40 PARENT NSObject',
		'IVAR _creationSequence I 8', 'IVAR _vendorName @"NSString" 16',
		'IVAR _handlerQueue @"NSObject<OS_dispatch_queue>" 24',
		'IVAR _mouseInput @"GCMouseInput" 32',
		'METHOD + mice @16@0:8', 'METHOD + current @16@0:8'])!
	require_text(out, 'gc-mouse-inspect.log', ['GCMouse mice count=0', 'GCMouse current nil=true',
		'IOS-GC-MOUSE-INSPECT: empty discovery, nil current and four notification values'])!
	for name in ['GCMouseDidConnectNotification', 'GCMouseDidDisconnectNotification',
		'GCMouseDidBecomeCurrentNotification', 'GCMouseDidStopBeingCurrentNotification']! {
		require_text(out, 'gc-mouse-inspect.log', ['CONSTANT ' + name + '=' + name])!
	}
	require_text(out, 'GCColor-metadata.log', ['GCColor SIZE 24 PARENT NSObject',
		'IVAR _red f 8', 'IVAR _green f 12', 'IVAR _blue f 16',
		'METHOD - initWithRed:green:blue: @28@0:8f16f20f24',
		'METHOD - red f16@0:8', 'METHOD - green f16@0:8', 'METHOD - blue f16@0:8',
		'METHOD - copyWithZone: @24@0:8^{_NSZone=}16'])!
	require_text(out, 'gc-color-inspect.log', [
		'VALUE 0 3e800000 -> 3e800000', 'VALUE 1 3f000000 -> 3f000000',
		'VALUE 2 3f400000 -> 3f400000', 'VALUE 0 bf800000 -> bf800000',
		'VALUE 1 40000000 -> 40000000', 'VALUE 0 7fc01234 -> 7fc01234',
		'VALUE 1 7f800000 -> 7f800000', 'VALUE 2 ff800000 -> ff800000',
		'VALUE 0 80000000 -> 80000000', 'COPY same=false', 'DEFAULT 0',
		'DESCRIPTION <GCColor r=0.250000 g=0.500000 b=0.750000>',
		'SUBCLASS COPY preserved=true', 'SUBCLASS COPY init-calls=0 stored-red=3e800000',
		'SUBCLASS COPY extra=0000000000000000',
		'IOS-GC-COLOR-INSPECT: exact float bits, independent copy, zero default and preserved subclass'])!
	for marker in ['GCPhysicalInputProfile SIZE 680 PARENT NSObject',
		'GCExtendedGamepad SIZE 872 PARENT GCPhysicalInputProfile',
		'GCDualShockGamepad SIZE 896 PARENT GCExtendedGamepad',
		'GCDualSenseGamepad SIZE 896 PARENT GCExtendedGamepad'] {
		require_text(out, marker.all_before(' ') + '-metadata.log', [marker])!
	}
	require_text(out, 'GCController-metadata.log', ['GCController SIZE 232 PARENT NSObject',
		'METHOD + controllers @16@0:8', 'METHOD + current @16@0:8',
		'METHOD + shouldMonitorBackgroundEvents B16@0:8',
		'METHOD + setShouldMonitorBackgroundEvents: v20@0:8B16'])!
	require_text(out, 'inspect.log', ['GCController controllers count=0',
		'GCController current nil=true', 'GCController shouldMonitorBackgroundEvents=0',
		'GCController set background=1 read=1', 'GCController set background=0 read=0'])!
	for name in ['GCControllerDidBecomeCurrentNotification', 'GCControllerDidConnectNotification',
		'GCControllerDidDisconnectNotification']! {
		require_text(out, 'inspect.log', ['CONSTANT ' + name + '=' + name])!
	}
	for mode in ['game-controller', 'probe'] {
		state := os.file_name(os.read_file(out + '/' + mode + '-state.txt')!.trim_space())
		if !state.starts_with(mode + '-') || state.split('/').any(it in ['', '.', '..']) { return error('invalid VM pointer') }
		for file in ['boot.img', 'efivars.fd', 'initramfs.tar.gz', 'limine.conf', 'serial.log'] {
			if !os.is_file(out + '/' + state + '/' + file) { return error('missing VM artifact ' + state + '/' + file) }
		}
		if mode == 'game-controller' {
			require_text(out, state + '/serial.log', [runtime_marker, rejection_marker,
				gamepad_marker, gamepad_rejection_marker, color_marker, color_rejection_marker,
				mouse_marker, mouse_rejection_marker,
				'IOS-NATIVE: /opt/ios/game-controller-checks wait status 0', 'VINIX iOS GAMECONTROLLER: PASS'])!
		} else {
			require_text(out, state + '/serial.log', ['iOS: linking /opt/ios/FortniteClient-IOS-Shipping:',
				next_blocker,
				'IOS-NATIVE: /opt/ios/run-ios wait status 256',
				'FORTNITE PROBE: process exit status 1', 'FORTNITE PROBE COMPLETE'])!
		}
	}
}

const next_blocker = 'iOS: library is not implemented: /System/Library/Frameworks/AVFAudio.framework/AVFAudio (_OBJC_CLASS_$_AVAudioApplication)'

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
	state := os.file_name(os.read_file(out + '/game-controller-state.txt')!.trim_space())
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
	if os.args.len != 3 { eprintln('usage: gc-mouse-evidence seal|check|selftest DIR'); exit(2) }
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
	println('GCMouse evidence ' + os.args[1] + ': PASS')
}
