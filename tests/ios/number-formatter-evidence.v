// SPDX-License-Identifier: GPL-2.0-or-later
// Seal/check complete NSNumberFormatter evidence outside the source tree.
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
	for bad in ['ERROR: AddressSanitizer', 'runtime error:', '> assert ', 'KERNEL PANIC', 'FATAL EXCEPTION', 'V panic:', 'IOS-NATIVE: FAIL', 'iOS FAIL:'] {
		if text.contains(bad) { return error(path + ': ' + bad) }
	}
}

fn results(out string) ! {
	revision := os.read_file(out + '/source-revision.txt')!.trim_space()
	if revision.len != 40 || revision.bytes().any(!it.is_hex_digit()) { return error('invalid source revision') }
	for file in ['source/compat/ios/runner/ns_number_formatter.c.v',
		'source/compat/ios/runner/ns_number_formatter_test.v',
		'source/tests/ios/number-formatter-evidence.v', 'build-inputs.sha256',
		'number-formatter-evidence', 'native-checks', 'notification-checks', 'notification-vm', 'inspect-user-notifications',
		'payload/center-host.c', 'NotificationChecks.app/Contents/Info.plist',
		'NotificationChecks.app/Contents/MacOS/center-host'] {
		if !os.is_file(out + '/' + file) { return error('missing ' + file) }
	}
	for i in 0 .. 4 {
		if !os.is_file(out + '/payload/host-' + i.str() + '.o') { return error('missing host object') }
	}
	for item in ['number-formatter-checks', 'date-formatter-checks', 'lock-checks', 'recursive-lock-checks', 'map-table-checks', 'credential-checks', 'telephony-checks', 'cache-checks', 'calendar-checks', 'calendar-trigger-checks', 'notification-request-checks',
		'notification-center-checks', 'notification-content-checks', 'notification-sound-checks', 'notification-attachment-checks', 'native-init', 'run-ios', 'run-ios-gles'] {
		for suffix in ['', '.c'] {
			if !os.is_file(out + '/' + item + suffix) { return error('missing ' + item + suffix) }
		}
	}
	for label in ['inspect-metadata', 'host-generate', 'host-object-0', 'host-object-1', 'host-object-2',
		'host-object-3', 'host-link', 'host', 'host-deterministic', 'driver-build', 'build', 'notifications', 'probe', 'audit', 'static-audit'] {
		if os.read_file(out + '/' + label + '.status.txt')!.trim_space() != '0' { return error(label + ' failed') }
		require_text(out, label + '.log', ['COMMAND: '])!
	}

	require_text(out, 'inspect-metadata.log', ['NSNumberFormatter SIZE 64 PARENT NSFormatter',
		'IVAR _attributes @"NSMutableDictionary" 8', 'IVAR _formatter ^{__CFNumberFormatter=} 16',
		'IVAR _counter Q 24', 'IVAR _behavior Q 32', 'IVAR _lock @"NSRecursiveLock" 40',
		'IVAR _stateBitMask Q 48', 'IVAR _cacheGeneration q 56'])!
	for record in ['init @16@0:8', 'copyWithZone: @24@0:8^{_NSZone=}16',
		'locale @16@0:8', 'setLocale: v24@0:8@16', 'numberStyle Q16@0:8', 'setNumberStyle: v24@0:8Q16',
		'stringFromNumber: @24@0:8@16', 'numberFromString: @24@0:8@16', 'stringForObjectValue: @24@0:8@16',
		'minimumIntegerDigits Q16@0:8', 'maximumIntegerDigits Q16@0:8',
		'minimumFractionDigits Q16@0:8', 'maximumFractionDigits Q16@0:8',
		'setMinimumIntegerDigits: v24@0:8Q16', 'setMaximumIntegerDigits: v24@0:8Q16',
		'setMinimumFractionDigits: v24@0:8Q16', 'setMaximumFractionDigits: v24@0:8Q16',
		'usesGroupingSeparator B16@0:8', 'setUsesGroupingSeparator: v20@0:8B16',
		'groupingSize Q16@0:8', 'setGroupingSize: v24@0:8Q16',
		'allowsFloats B16@0:8', 'setAllowsFloats: v20@0:8B16',
		'roundingMode Q16@0:8', 'setRoundingMode: v24@0:8Q16',
		'formatterBehavior Q16@0:8', 'setFormatterBehavior: v24@0:8Q16',
		'formattingContext q16@0:8', 'setFormattingContext: v24@0:8q16'] {
		require_text(out, 'inspect-metadata.log', ['METHOD - ' + record])!
	}
	for log in ['host.log', 'host-deterministic.log'] {
		require_text(out, log, ['IOS-NUMBER-FORMATTER-NATIVE: metadata, English no-style/decimal defaults, half-even rounding, grouping, padding, exact integers, parsing and independent copies',
		'IOS-NUMBER-FORMATTER: input snapshots across first-locale callbacks, joined-worker copy/source pin, constructor rollback, guarded storage,32 isa replacements,192 concurrent roundtrips and two drained runtimes',
		'IOS-NUMBER-FORMATTER-REJECT:33 unsupported options, coding, subclasses, provenance, raw setters, parse bounds and active destruction fail explicitly'])!
	}
	for file in ['payload/center-host.c', 'NotificationChecks.app/Contents/Info.plist',
		'NotificationChecks.app/Contents/MacOS/center-host'] {
		if !os.is_file(out + '/date-host/' + file) { return error('missing date formatter regression ' + file) }
	}
	for i in 0 .. 4 {
		if !os.is_file(out + '/date-host/payload/host-' + i.str() + '.o') { return error('missing date formatter host object') }
	}
	for label in ['host-generate', 'host-object-0', 'host-object-1', 'host-object-2', 'host-object-3',
		'host-link', 'host', 'host-deterministic'] {
		if os.read_file(out + '/date-host/' + label + '.status.txt')!.trim_space() != '0' { return error('date formatter ' + label + ' failed') }
		require_text(out, 'date-host/' + label + '.log', ['COMMAND: '])!
	}
	for log in ['date-host/host.log', 'date-host/host-deterministic.log'] {
		require_text(out, log, ['IOS-DATE-FORMATTER-NATIVE: metadata, four consumer formats, local and fixed zones, strict modern parse, fractional rounding, initializer state, copied properties and independent copy lifetime',
		'IOS-DATE-FORMATTER: four measured formats, local/fixed zones, metadata, parser bounds, first-locale callbacks release format/parse input,8 concurrent cache publishers, joined-worker copy snapshots and source pin, constructor rollback, guarded storage,32 isa replacements,192 concurrent roundtrips and two drained runtimes',
		'IOS-DATE-FORMATTER-REJECT:45 unsupported patterns/options/coding/templates/styles, raw setters, subclasses/provenance, property types, failed format copying, named zones, calendar bounds and active destruction fail explicitly'])!
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
			require_text(out, log, ['IOS-NUMBER-FORMATTER:', 'IOS-NUMBER-FORMATTER-REJECT:33 ',
				'IOS-DATE-FORMATTER:', 'IOS-DATE-FORMATTER-REJECT:45 ', 'IOS-LOCK:', 'IOS-LOCK-REJECT: 28 ',
				'IOS-RECURSIVE-LOCK:', 'IOS-RECURSIVE-LOCK-REJECT:23 ',
				'IOS-MAP-TABLE:', 'IOS-MAP-TABLE-REJECT: 27 ', 'IOS-CREDENTIAL:', 'IOS-CREDENTIAL-REJECT: 35 ',
				'IOS-TELEPHONY:', 'IOS-TELEPHONY-REJECT: 19 ', 'IOS-CACHE:', 'IOS-CACHE-REJECT: 31 ',
				'IOS-NS-CALENDAR:', 'IOS-NS-CALENDAR-REJECT:41 ', 'IOS-UN-CALENDAR:', 'IOS-UN-CALENDAR-REJECT: 21 ',
				'IOS-UN-REQUEST:', 'IOS-UN-REQUEST-REJECT: 28 ', 'IOS-UN-CENTER:',
				'IOS-UN-CENTER-REJECT: 31 ', 'IOS-UN-CONTENT:', 'IOS-UN-CONTENT-REJECT: 28 ',
				'IOS-UN-SOUND:', 'IOS-UN-SOUND-REJECT: 33 ', 'IOS-UN-ATTACHMENT:', 'IOS-UN-ATTACHMENT-REJECT: 39 ', 'VINIX iOS NOTIFICATIONS: PASS'])!
			for fixture in ['number-formatter', 'date-formatter', 'lock', 'recursive-lock', 'map-table',
				'credential', 'telephony', 'cache', 'calendar', 'calendar-trigger', 'notification-request',
				'notification-center', 'notification-content', 'notification-sound', 'notification-attachment'] {
				require_text(out, log, ['IOS-NATIVE: /opt/ios/' + fixture + '-checks wait status 0'])!
			}
		} else {
			require_text(out, log, ['FORTNITE PROBE: process exit status 1', 'FORTNITE PROBE COMPLETE'])!
			if mode == 'probe' {
				require_text(out, log, ['iOS: linking /opt/ios/FortniteClient-IOS-Shipping:',
					'iOS: framework symbol is not implemented: _OBJC_CLASS_$_NSBundleResourceRequest'])!
			} else {
				gles := mode == 'audit'
				require_text(out, log, [
					'iOS IMPORT AUDIT IMAGE: /opt/ios/FortniteClient-IOS-Shipping: ' + if gles { '2103 resolved, 58 unresolved strong, 78 unresolved weak' } else { '2092 resolved, 69 unresolved strong, 78 unresolved weak' },
					'iOS IMPORT AUDIT IMAGE: /opt/ios/Frameworks/EOSSDK.framework/EOSSDK: ' + if gles { '664 resolved, 0 unresolved strong, 16 unresolved weak' } else { '661 resolved, 3 unresolved strong, 16 unresolved weak' },
					'iOS IMPORT AUDIT IMAGE: /opt/ios/Frameworks/MarketplaceKitWrapper.framework/MarketplaceKitWrapper: 179 resolved, 0 unresolved strong, 20 unresolved weak'])!
				require_text(out, log, [if mode == 'audit' {
					'iOS IMPORT AUDIT: 2946 resolved, 58 unresolved strong, 114 unresolved weak (app code was not executed)'
				} else {
					'iOS IMPORT AUDIT: 2932 resolved, 72 unresolved strong, 114 unresolved weak (app code was not executed)'
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
	sources << ['tests/ios/native-checks.v', 'tests/ios/native-init.v',
		'tests/ios/inspect-user-notifications.v',
		'tests/ios/notification-checks.v', 'tests/ios/notification-vm.v', 'tests/ios/number-formatter-evidence.v']
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
	path := out + '/inspect-metadata.log'
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
	if os.args.len != 3 { eprintln('usage: number-formatter-evidence snapshot|seal|check|selftest|archive|archive-zstd DIR'); exit(2) }
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
	println('number formatter evidence ' + os.args[1] + ': PASS')
}
