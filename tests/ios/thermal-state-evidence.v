// SPDX-License-Identifier: GPL-2.0-or-later
// Seal the thermal-state checkpoint, all guest regressions and the observed next boundary.
module main

import crypto.sha256
import os
import strconv

const expected_application_stop = 'iOS: UIKit apps must be launched by the Vinix desktop (VINIX_REQUEST_FD/VINIX_RESPONSE_FD)'
const badge_marker = 'IOS-APPLICATION-BADGE: absent badge getter, zero/minus-one clears, metadata, signatures, direct IMP, subclass, idle timer independence and two drained runtimes PASS'
const badge_reject_marker = 'IOS-APPLICATION-BADGE-REJECT: counts outside zero/minus-one fail explicitly across signed 64-bit boundaries without a badge backend PASS'
const receipt_marker = 'IOS-BUNDLE-RECEIPT: unavailable receipt nil, instance metadata, signature, direct IMP, eight workers, pool drain and two balanced lifetimes PASS'
const cstring_marker = 'IOS-STRING-CSTRING: ASCII 255-byte matrix, UTF8, BOM, invalid input, copy, mutable factory, metadata, direct IMP, eight workers and two balanced lifetimes PASS'
const float_marker = 'IOS-STRING-FLOAT: decimal grammar, BMP digits, whitespace, rounding, metadata, direct IMP, mutation, constants, eight workers and two balanced lifetimes PASS'
const entry_trace = 'iOS startup: application entry'
const output_marker = 'IOS-CF-STRING-OUTPUT: UTF-16 ranges including surrogate halves, endian/BOM, null sizing, zero/odd capacities, unaligned canaries, guard pages, null used pointer, game call sequence, UTF-8/ASCII capacity regression, concurrent readers and two drained runtimes PASS'
const inline_marker = 'IOS-INLINE-PTHREAD-SELF: both idioms, registers, vectors, FP state, flags, SP/LR, red zone, native TLS/errno, workers and unload PASS'
const large_image_marker = 'IOS-INLINE-PTHREAD-SELF: large image reserved trampoline placement PASS'
const search_marker = 'IOS-SEARCH-PATHS: user application directories, Documents override, tilde expansion, bounded Unicode/root/borrowed paths, rejection, no filesystem effects, retained arrays, concurrent readers and two drained runtimes PASS'
const search_trace = 'iOS: search path directory=14 domain=1 expand=1: /opt/Library/Application Support'
const documents_trace = 'iOS: search path directory=9 domain=1 expand=1: /opt/Documents'
const home_marker = 'IOS-HOME-DIRECTORY: Foundation-only C export, bounded borrowed parent paths, existing app Documents convention, copied autoreleased NSString results, Unicode/space/root/trailing-slash/1023-byte/protected-prefix cases, no directory creation, Documents integration, invalid/lifetime rejection, concurrent readers and two drained runtimes'
const translation_marker = 'iOS: translated 13 inline pthread_self operations in /opt/ios/FortniteClient-IOS-Shipping'
const snapshot_marker = 'IOS-DICTIONARY-SNAPSHOT: empty/populated immutable/mutable dictionaries, unordered keys, duplicate value identities, selector scope and snapshots surviving mutation, owner release and pool drain PASS'
const constant_marker = 'IOS-CONSTANT-DICTIONARY: read-only image registration, bounded native behavior, nested/empty records, class identity, eight concurrent registrations, unchanged bytes and two drained lifetimes passed'
const invalid_marker = 'IOS-CONSTANT-DICTIONARY-INVALID: malformed class/options/count/arrays/member pointers and section bounds rejected before dictionary metadata publication'

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

fn require_text(out string, path string, markers []string) !string {
	text := os.read_file(out + '/' + path)!.replace('\r\n', '\n')
	return checked_text(path, text, markers)
}

fn checked_text(path string, text string, markers []string) !string {
	for marker in markers {
		if !text.contains(marker) { return error(path + ': missing ' + marker) }
	}
	for bad in ['runtime error:', '> assert ', 'KERNEL PANIC', 'panic:',
		'FATAL EXCEPTION', 'IOS-NATIVE: FAIL', 'iOS FAIL:', 'ERROR: AddressSanitizer'] {
		if text.contains(bad) { return error(path + ': ' + bad) }
	}
	return text
}

fn timeout_observation(out string) ! {
	if os.read_file(out + '/probe-no-ads.status.txt')!.trim_space() != '1' {
		return error('expected incomplete probe with harness status 1')
	}
	text := os.read_file(out + '/probe-no-ads.log')!.replace('\r\n', '\n')
	expected := 'V panic: VM timeout: ' + out + '/' + probe_state(out)! + '/serial.log'
	if text.split_into_lines().filter(it == expected).len != 1 {
		return error('missing or repeated exact harness timeout')
	}
	// Only this host harness timeout is expected; no guest panic is permitted.
	checked_text('probe-no-ads.log', text.replace(expected, 'EXPECTED-HARNESS-TIMEOUT'), ['COMMAND: '])!
}

fn probe_state(out string) !string {
	state := os.file_name(os.read_file(out + '/probe-no-ads-state.txt')!.trim_space())
	if !state.starts_with('probe-no-ads-') || !safe_path(state) { return error('invalid VM pointer') }
	for name in ['boot.img', 'efivars.fd', 'initramfs.tar.gz', 'limine.conf', 'serial.log'] {
		if !os.is_file(out + '/' + state + '/' + name) { return error('missing guest media: ' + name) }
	}
	return state
}

fn field(line string, name string) !u64 {
	if !line.contains(name + '=0x') { return error('missing ' + name) }
	return strconv.parse_uint(line.all_after(name + '=0x').all_before(' ').trim_space(), 16, 64)
}

fn vm_reservation(serial string) ! {
	expected := 'IOS-PROBE-VM: op=mmap address=0x0 size=0x600000000 args=0x3,0x1042,0xf1000000,0x0,0x0,0x0,0x0,0x0,0x0,0x0 result='
	mut found := 0
	for line in serial.split_into_lines() {
		if !line.starts_with(expected) { continue }
		result := field(line, 'result')!
		if result == 0 || result == ~u64(0) || result % 4096 != 0 {
			return error('tagged anonymous reservation failed')
		}
		found++
	}
	if found != 1 { return error('missing or repeated 24 GiB tagged reservation') }
	allocator := serial.index('Using MallocBinned3 allocator.') or { return error('missing allocator') }
	reservation := serial.index(expected) or { return error('missing reservation') }
	stop := serial.index(expected_application_stop) or { return error('missing next boundary') }
	if allocator >= reservation || reservation >= stop { return error('unexpected reservation order') }
	if serial.contains('result=0xffffffffffffffff') { return error('VM call failure in tagged checkpoint') }
}

fn search_observation(serial string) ! {
	if serial.count('iOS: search path directory=') != 2 || serial.count(search_trace) != 1
		|| serial.count(documents_trace) != 1 || serial.count(entry_trace) != 1 {
		return error('missing or changed application search-path observation')
	}
	initializers := serial.last_index('iOS startup: initializers for ') or { return error('missing initializers') }
	lookup := serial.index(search_trace) or { return error('missing search path') }
	entry := serial.index(entry_trace) or { return error('missing application entry') }
	documents := serial.index(documents_trace) or { return error('missing Documents path') }
	stop := serial.index(expected_application_stop) or { return error('missing application boundary') }
	if initializers >= lookup || lookup >= entry || entry >= documents || documents >= stop {
		return error('unexpected application entry/search-path order')
	}
}

const window_marker = 'IOS-WINDOW: controllerless visibility/layout/touches, direct subviews, late root assignment, replacement/removal, callbacks, strong ownership and two drained runtimes'

const process_markers = ['IOS-PROCESSINFO: copied app arguments, guarded version result, 8,000 concurrent queries, caller storage, isa changes and two zero-live-object shutdowns',
'IOS-PROCESSINFO-MEMORY: reflected scalar ABI, preserved indirect buffer and errno, 8,000 concurrent queries without new objects',
'IOS-PROCESSINFO-THERMAL: nominal fallback, signed ABI, instance reflection, signature, direct IMP, subclass, preserved registers and errno, concurrent readers and zero-live teardown PASS',
'IOS-PROCESSINFO-REJECT: late argument replacement, unsupported copies, missing aggregate buffers and snapshot mutation fail explicitly']
const native_markers = ['IOS-PROCESSINFO-NATIVE: distinct allocation, singleton instance, owned argument snapshots, typed 24-byte version ABI and signed comparisons',
'IOS-PROCESSINFO-MEMORY-NATIVE: unsigned 64-bit scalar matches physical pages times page size',
'IOS-PROCESSINFO-THERMAL-NATIVE: signed 64-bit enum, instance reflection, signature and direct IMP PASS']

fn guest_resources(out string) ! {
	// The VM removes its staging directory after preserving this archive.
	temporary := os.join_path(os.temp_dir(), 'thermal-state-evidence-' + os.getpid().str())
	if os.exists(temporary) { return error('resource check temporary directory exists') }
	os.mkdir(temporary)!
	defer { os.rmdir_all(temporary) or {} }
	paths := ['Info.plist', 'LaunchScreen.storyboardc/Info.plist', 'LaunchScreen.storyboardc/LaunchScreen.nib',
		'LaunchScreen.storyboardc/01J-lp-oVM-view-Ze5-6b-2t3.nib', 'LaunchScreenIOS.png']
	mut args := ['/usr/bin/tar', '-xzf', out + '/' + probe_state(out)! + '/initramfs.tar.gz', '-C', temporary, '--']
	for path in paths { args << './opt/ios/' + path }
	args << './opt/ios/processinfo-checks'
	extracted := os.exec(args)
	if extracted.exit_code != 0 { return error('extract preserved guest resources: ' + extracted.output) }
	for path in paths {
		if digest(out + '/application/' + path)! != digest(temporary + '/opt/ios/' + path)! {
			return error('probe resource differs from preserved application: ' + path)
		}
	}
	if digest(out + '/processinfo-checks')! != digest(temporary + '/opt/ios/processinfo-checks')! {
		return error('guest process-info fixture differs from preserved build')
	}
}

fn results(out string) ! {
	revision := os.read_file(out + '/source-revision.txt')!.trim_space()
	if revision.len != 40 || revision.bytes().any(!it.is_hex_digit()) { return error('invalid revision') }
	for path in ['source-files.txt', 'build-inputs.sha256', 'notification-checks', 'notification-vm',
		'inventory-inputs', 'checkpoint-run', 'thermal-state-evidence', 'provenance.txt',
		'source/compat/ios/runner/ns_process_info.c.v', 'source/compat/ios/runner/ns_process_info_test.v',
		'source/tests/ios/thermal-state-evidence.v', 'source/tests/ios/thermal-state-prepare.v',
		'source/tests/ios/compiled-storyboard-input-inventory.v', 'source/tests/ios/application-badge-run.v',
		'source/tests/ios/native-init.v', 'source/tests/ios/notification-vm.v',
		'source/tests/ios/notification-checks.v', 'application/FortniteClient-IOS-Shipping',
		'application/Frameworks/EOSSDK.framework/EOSSDK', 'application/Frameworks/MarketplaceKitWrapper.framework/MarketplaceKitWrapper'] {
		if !os.is_file(out + '/' + path) { return error('missing ' + path) }
	}
	mut seen := map[string]bool{}
	for path in os.read_lines(out + '/source-files.txt')! {
		if !safe_path(path) || path in seen { return error('invalid source path') }
		seen[path] = true
		if !os.is_file(out + '/source/' + path) { return error('missing source ' + path) }
	}
	if seen.len == 0 { return error('empty source inventory') }
	inputs := os.read_lines(out + '/build-inputs.sha256')!
	if inputs.len == 0 { return error('empty selected input inventory') }
	for line in inputs {
		if line.len < 67 || line[64..66] != '  ' || line[..64].bytes().any(!it.is_hex_digit()) {
			return error('invalid selected input record')
		}
	}
	for label in ['prior-check', 'tool-notification-checks', 'tool-notification-vm', 'tool-checkpoint-run', 'tool-inventory-inputs', 'tool-thermal-state-evidence'] {
		if os.read_file(out + '/' + label + '.status.txt')!.trim_space() != '0' { return error(label + ' failed') }
		require_text(out, label + '.log', ['COMMAND: '])!
	}
	require_text(out, 'prior-check.log', ['Compiled storyboard evidence check: PASS'])!
	for label in ['build-init', 'build-application-badge', 'build-window', 'build-string-float', 'build-string-cstring',
		'build-bundle-receipt', 'build-cf-string-output', 'build-search-path', 'build-home-directory',
		'build-inline-pthread-self', 'build-dictionary-snapshot', 'build-block-byref',
		'build-processinfo', 'build-vm-probe', 'build-run-ios-gles'] {
		if os.read_file(out + '/' + label + '.status.txt')!.trim_space() != '0' { return error(label + ' failed') }
		require_text(out, label + '.log', [])!
	}
	for name in ['native-init', 'application-badge-checks', 'window-checks', 'string-float-checks', 'string-cstring-checks',
		'bundle-receipt-checks', 'cf-string-output-checks', 'search-path-checks', 'home-directory-checks',
		'inline-pthread-self-checks', 'dictionary-snapshot-checks', 'block-byref-checks', 'processinfo-checks', 'vm-probe-checks', 'run-ios-gles'] {
		for suffix in ['', '.c'] {
			if !os.is_file(out + '/' + name + suffix) { return error('missing guest build ' + name + suffix) }
		}
	}

	for label in ['host-generate', 'host-object-0', 'host-object-1', 'host-object-2', 'host-object-3', 'host-link', 'host', 'host-deterministic'] {
		if os.read_file(out + '/host/' + label + '.status.txt')!.trim_space() != '0' { return error('host/' + label + ' failed') }
		mut markers := ['COMMAND: ']
		if label in ['host', 'host-deterministic'] {
			markers << process_markers
			markers << native_markers
		}
		require_text(out, 'host/' + label + '.log', markers)!
	}
	require_text(out, 'host/host-object-0.log', ['-fsanitize=address,undefined'])!
	require_text(out, 'host/host-link.log', ['-fsanitize=address,undefined'])!
	for path in ['payload/center-host.c', 'payload/host-0.o', 'payload/host-1.o', 'payload/host-2.o', 'payload/host-3.o',
		'NotificationChecks.app/Contents/Info.plist', 'NotificationChecks.app/Contents/MacOS/center-host'] {
		if !os.is_file(out + '/host/' + path) { return error('missing host artifact ' + path) }
	}
	archives := os.walk_ext(out + '/host/payload/tls', '.a')
	if archives.len != 1 || os.file_name(archives[0]) != 'libios-tls.a' { return error('missing host TLS archive') }
	if os.read_file(os.dir(archives[0]) + '/compile.status.txt')!.trim_space() != '0' { return error('host TLS build failed') }
	require_text(out, 'provenance.txt', ['Prior manifest SHA-256: 3ae5be94ecc0c7664a0c41ecdef94fac56e660e7319596ae8824a028a8816619',
		'Fresh host and guest tests; advertising skipped by diagnostic probe.',
		'NSProcessInfo thermalState uses the documented nominal fallback without a Darwin thermal-awareness provider.',
		'ASan leak detection disabled; ASan/UBSan errors remain fatal.'])!
	if digest(out + '/application/FortniteClient-IOS-Shipping')! != '6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373' {
		return error('unexpected application executable')
	}
	state := probe_state(out)!
	serial := require_text(out, state + '/serial.log', [
		'IOS-PROBE-BUDGET: check exceed=false wait=0',
		'IOS-PROBE-BUDGET: check exceed=true wait=9', 'oom_kill 1;',
		'IOS-PROBE-BUDGET: enforcement and supervisor isolation PASS', 'max=2147483648 ',
		'IOS-PROBE-FAULT: signal context and restoration PASS',
		'IOS-PROBE-FAULT: signal=0x000000000000000b code=0x0000000000000002',
		'IOS-VM-PROBE: disabled mode, reserve/commit/release, Mach results, errno and failed diagnostic write PASS',
		'IOS-VM-TAGS: anonymous tags, ignored offset, unsupported flags, file descriptor/offset and fixed mapping guard PASS',
		'IOS-NATIVE: /opt/ios/vm-probe-checks wait status 0',
		'IOS-BLOCK-BYREF: stack/heap ownership orders, shared mutation, four concurrent retainers, saturated counts, ARC strong/weak moves, helper reentry and cleanup PASS',
		'IOS-NATIVE: /opt/ios/block-byref-checks wait status 0',
		snapshot_marker, constant_marker, invalid_marker,
		'IOS-NATIVE: /opt/ios/dictionary-snapshot-checks wait status 0',
		inline_marker, large_image_marker, translation_marker,
		'IOS-NATIVE: /opt/ios/inline-pthread-self-checks wait status 0',
		badge_marker, badge_reject_marker, 'IOS-NATIVE: /opt/ios/application-badge-checks wait status 0',
		window_marker, 'IOS-NATIVE: /opt/ios/window-checks wait status 0',
		float_marker, 'IOS-NATIVE: /opt/ios/string-float-checks wait status 0',
		cstring_marker, 'IOS-NATIVE: /opt/ios/string-cstring-checks wait status 0',
		receipt_marker, 'IOS-NATIVE: /opt/ios/bundle-receipt-checks wait status 0',
		output_marker, 'IOS-NATIVE: /opt/ios/cf-string-output-checks wait status 0',
		search_marker, 'IOS-NATIVE: /opt/ios/search-path-checks wait status 0',
		home_marker, 'IOS-NATIVE: /opt/ios/home-directory-checks wait status 0',
		'IOS-NATIVE: /opt/ios/processinfo-checks wait status 0',
		search_trace, 'iOS probe image: base=0x', 'Using MallocBinned3 allocator.',
		expected_application_stop])!
	timeout_observation(out)!
	if serial.split_into_lines().filter(it == expected_application_stop).len != 1 {
		return error('missing or repeated application boundary')
	}
	// The VM was stopped before wait/finish returned. Do not infer an exit or final OOM counters.
	for unexpected in ['IOS-NATIVE: /opt/ios/run-ios wait status', 'FORTNITE PROBE:',
		'FORTNITE PROBE COMPLETE', 'IOS-PROBE-BUDGET: final current='] {
		if serial.contains(unexpected) { return error('unexpected completion in timed-out probe: ' + unexpected) }
	}
	for marker in process_markers { if !serial.contains(marker) { return error('missing guest process-info case: ' + marker) } }
	if serial.count('IOS-PROBE-FAULT: signal=') != 1 || serial.count('IOS-PROBE-REGS:') != 1 {
		return error('missing deliberate fixture context or unexpected application fault')
	}
	if serial.count(translation_marker) != 1 || serial.count('iOS probe image: base=') != 3 {
		return error('unexpected translation or image count')
	}
	vm_reservation(serial)!
	search_observation(serial)!
	for line in serial.split_into_lines() {
		if line.starts_with('IOS-PROBE-REGS:') && line.count(' x') != 31 {
			return error('incomplete ARM64 registers')
		}
	}
	mut queries := 0
	for line in serial.split_into_lines() {
		if line.starts_with('iOS memory: os_proc_available_memory=') {
			value := line.all_after('=')
			if value == '' || value.bytes().any(!it.is_digit()) || value.u64() == 0 || value.u64() > 2147483648 {
				return error('invalid or zero application headroom')
			}
			queries++
		}
	}
	if queries != 7 { return error('changed application memory accounting') }
	if serial.count('iOS +load: ') != 9 || serial.count('iOS startup: initializers for ') != 3
		|| serial.count(entry_trace) != 1 { return error('unexpected startup boundary') }
}
fn seal(out string) ! {
	results(out)!
	guest_resources(out)!
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
		path := line[66..]
		if line[..64].bytes().any(!it.is_hex_digit()) || !safe_path(path) || path == 'manifest.sha256' || path in seen {
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
	guest_resources(out)!
}

fn selftest(out string) ! {
	check(out)!
	image := out + '/application/LaunchScreenIOS.png'
	image_before := os.read_file(image)!
	os.write_file(image, 'SELFTEST-CHANGED-RESOURCE')!
	mut resource_rejected := false
	guest_resources(out) or { resource_rejected = true }
	os.write_file(image, image_before)!
	if !resource_rejected { return error('changed application resource accepted') }
	println('application resource differing from preserved guest archive: rejected')
	media := out + '/' + probe_state(out)! + '/boot.img'
	backup := media + '.selftest'
	if os.exists(backup) { return error('selftest backup exists') }
	os.mv(media, backup)!
	mut rejected := false
	check(out) or { rejected = true }
	os.mv(backup, media)!
	if !rejected { return error('missing guest media accepted') }
	println('missing guest media: rejected')
	log := out + '/' + probe_state(out)! + '/serial.log'
	original := os.read_file(log)!
	reservation := original.split_into_lines().filter(it.starts_with('IOS-PROBE-VM: op=mmap address=0x0 size=0x600000000 '))[0]
	result := 'result=' + reservation.all_after('result=').all_before(' ')
	for changed in [original.replace('size=0x600000000', 'size=0x600000001'), original.replace('0xf1000000', '0xf0000000'), original.replace(result, 'result=0xffffffffffffffff'), original.replace(result, 'result=0x0'), original.replace('IOS-PROBE-VM:', 'REMOVED-VM:')] {
		if changed == original { return error('selftest did not change VM diagnostics') }
		rejected = false
		vm_reservation(changed.replace('\r\n', '\n')) or { rejected = true }
		if !rejected { return error('changed VM diagnostics accepted') }
	}
	println('changed VM size, tag, failed/null result and missing trace: rejected')
	mut mutations := [original.replace(process_markers[2], 'REMOVED-THERMAL'), original.replace(' x30=', ' removed30='), original.replace(badge_marker, 'REMOVED-BADGE'),
		original.replace(badge_reject_marker, 'REMOVED-BADGE-REJECT'),
		original.replace('/opt/ios/application-badge-checks wait status 0', '/opt/ios/application-badge-checks wait status 1'),
		original.replace(window_marker, 'REMOVED-WINDOW'),
		original.replace('/opt/ios/window-checks wait status 0', '/opt/ios/window-checks wait status 1'),
		original.replace(search_trace, 'REMOVED-SEARCH'), original.replace(documents_trace, 'REMOVED-DOCUMENTS'),
		original.replace(entry_trace, 'REMOVED-ENTRY'), original + '\n' + entry_trace + '\n',
		original.replace(entry_trace, '') + '\n' + entry_trace + '\n',
		original.replace(translation_marker, translation_marker.replace('13', '12')),
		original.replace(expected_application_stop, 'V panic: changed boundary'),
		original + '\n' + expected_application_stop + '\n',
		original + '\nFORTNITE PROBE: process exit status 0\n',
		original + '\nFORTNITE PROBE COMPLETE\n',
		original + '\nIOS-NATIVE: /opt/ios/run-ios wait status 256\n',
		original + '\nIOS-PROBE-BUDGET: final current=0 oom 0;oom_kill 0;\n',
		original.replace('iOS +load: ', 'REMOVED-LOAD: '),
		original.replace('iOS startup: initializers for ', 'REMOVED-INITIALIZER: '),
		original + '\nIOS-PROBE-FAULT: signal=unexpected\n', original + '\npanic: unexpected\n']
	for name in ['string-float', 'string-cstring', 'bundle-receipt', 'cf-string-output', 'search-path', 'home-directory', 'inline-pthread-self', 'dictionary-snapshot', 'block-byref', 'processinfo', 'vm-probe'] {
		mutations << original.replace('/opt/ios/' + name + '-checks wait status 0', '/opt/ios/' + name + '-checks wait status 1')
	}
	for changed in mutations {
		if changed == original { return error('selftest did not change boundary') }
		os.write_file(log, changed)!
		rejected = false
		results(out) or { rejected = true }
		os.write_file(log, original)!
		if !rejected { return error('changed guest validation accepted') }
	}
	println('missing thermal/badge/rejection/window markers, incomplete registers, all failed fixture waits, entry/load/initializer/search/translation changes, changed/repeated boundary, invented completion/accounting and extra faults/panics: rejected')
	timeout_log := out + '/probe-no-ads.log'
	timeout_before := os.read_file(timeout_log)!
	for changed in [timeout_before.replace('V panic: VM timeout:', 'REMOVED-TIMEOUT:'),
		timeout_before.replace('/serial.log\n v hash:', '/wrong.log\n v hash:'),
		timeout_before + '\nV panic: unexpected\n'] {
		if changed == timeout_before { return error('selftest did not change timeout') }
		os.write_file(timeout_log, changed)!
		rejected = false
		timeout_observation(out) or { rejected = true }
		os.write_file(timeout_log, timeout_before)!
		if !rejected { return error('changed timeout accepted') }
	}
	timeout_status := out + '/probe-no-ads.status.txt'
	status_before := os.read_file(timeout_status)!
	for changed in ['0\n', '2\n'] {
		os.write_file(timeout_status, changed)!
		rejected = false
		timeout_observation(out) or { rejected = true }
		os.write_file(timeout_status, status_before)!
		if !rejected { return error('changed timeout status accepted') }
	}
	println('missing/changed timeout, unexpected harness panic and changed timeout status: rejected')

	for path in ['host/host.log', 'host/host-deterministic.log', 'host/host.status.txt',
		'build-processinfo.status.txt', 'tool-thermal-state-evidence.status.txt', 'prior-check.log', 'provenance.txt'] {
		file := out + '/' + path
		before := os.read_file(file)!
		os.write_file(file, 'SELFTEST-REMOVED\n')!
		rejected = false
		results(out) or { rejected = true }
		os.write_file(file, before)!
		if !rejected { return error('missing validation accepted: ' + path) }
	}
	mut host_markers := process_markers.clone()
	host_markers << native_markers
	for marker in host_markers {
		path := out + '/host/host-deterministic.log'
		before := os.read_file(path)!
		changed := before.replace(marker, 'REMOVED-PROCESSINFO-CASE')
		if before == changed { return error('selftest did not change process-info case') }
		os.write_file(path, changed)!
		rejected = false
		results(out) or { rejected = true }
		os.write_file(path, before)!
		if !rejected { return error('missing process-info case accepted') }
	}
	println('missing native/runtime thermal and process-info cases, provenance and failed statuses: rejected')
	os.write_file(log, original + '\nSELFTEST-TAMPER\n')!
	rejected = false
	check(out) or { rejected = true }
	os.write_file(log, original)!
	if !rejected { return error('changed log accepted') }
	println('changed log: rejected')
	extra := out + '/selftest-unmanifested.txt'
	if os.exists(extra) { return error('selftest extra file exists') }
	os.write_file(extra, 'unmanifested\n')!
	rejected = false
	check(out) or { rejected = true }
	os.rm(extra)!
	if !rejected { return error('unmanifested file accepted') }
	println('unmanifested file: rejected')
	check(out)!
}

fn main() {
	if os.args.len != 3 { eprintln('usage: thermal-state-evidence seal|check|selftest DIR | hash FILE'); exit(2) }
	if os.args[1] == 'hash' { println(digest(os.args[2]) or { eprintln(err); exit(1) }); return }
	out := os.real_path(os.args[2]); root := os.real_path(os.getwd())
	if !os.is_dir(out) || out == root || out.starts_with(root + '/') { eprintln('evidence must exist outside the repository'); exit(2) }
	match os.args[1] {
		'seal' { seal(out) or { eprintln(err); exit(1) } }
		'check' { check(out) or { eprintln(err); exit(1) } }
		'selftest' { selftest(out) or { eprintln(err); exit(1) } }
		else { eprintln('unknown mode'); exit(2) }
	}
	println('Thermal-state evidence ' + os.args[1] + ': PASS (application startup remains incomplete)')
}
