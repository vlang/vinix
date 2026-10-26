// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve measured NSString floatValue behavior and the observed startup boundary.
module main

import crypto.sha256
import os
import strconv
import stringfloatcases

const expected_application_stop = 'V panic: iOS: object has no live runtime metadata'
const receipt_marker = 'IOS-BUNDLE-RECEIPT: unavailable receipt nil, instance metadata, signature, direct IMP, eight workers, pool drain and two balanced lifetimes PASS'
const receipt_native_marker = 'IOS-BUNDLE-RECEIPT-NATIVE: bundled missing receipt URL, instance metadata, signature, direct IMP, eight workers and pool drain PASS'
const inspector_marker = 'BUNDLE-RECEIPT-NATIVE: unbundled=nil reads=256 types=@16@0:8 instance=true class=false'
const cstring_marker = 'IOS-STRING-CSTRING: ASCII 255-byte matrix, UTF8, BOM, invalid input, copy, mutable factory, metadata, direct IMP, eight workers and two balanced lifetimes PASS'
const cstring_native_marker = 'IOS-STRING-CSTRING-NATIVE: ASCII 255-byte matrix, UTF8, BOM, invalid input, copy, mutable factory, metadata, direct IMP and eight workers PASS'
const float_marker = 'IOS-STRING-FLOAT: decimal grammar, BMP digits, whitespace, rounding, metadata, direct IMP, mutation, constants, eight workers and two balanced lifetimes PASS'
const float_native_marker = 'IOS-STRING-FLOAT-NATIVE: decimal grammar, BMP digits, whitespace, rounding, metadata, direct IMP, mutation and eight workers PASS'
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
	for marker in markers {
		if !text.contains(marker) { return error(path + ': missing ' + marker) }
	}
	// Only the selected application's exact, observed stop is permitted.
	mut checked := text
	if path.ends_with('/serial.log') && path == probe_state(out)! + '/serial.log' {
		if text.split_into_lines().filter(it == expected_application_stop).len != 1 {
			return error('missing or repeated application boundary')
		}
		checked = text.replace(expected_application_stop, 'EXPECTED-APPLICATION-STOP')
	}
	for bad in ['runtime error:', '> assert ', 'KERNEL PANIC', 'panic:',
		'FATAL EXCEPTION', 'IOS-NATIVE: FAIL', 'iOS FAIL:', 'ERROR: AddressSanitizer'] {
		if checked.contains(bad) { return error(path + ': ' + bad) }
	}
	return text
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

fn native_case(lines []string, key string, converted int, used int, bytes string) ! {
	expected := 'CF-OUTPUT: text=4100cf80f09f8eae5a ' + key
		+ ' converted=${converted} used=${used} bytes=' + bytes + 'a5'.repeat(32 - bytes.len / 2)
	if lines.filter(it == expected).len != 1 { return error('missing or changed native case: ' + key) }
}

fn native_observations(out string) ! {
	lines := require_text(out, 'native-output.txt', [])!.split_into_lines()
	if lines.len != 1280 { return error('incomplete native output matrix') }
	mut seen := map[string]bool{}
	for line in lines {
		key := line.all_before(' converted=')
		if !key.starts_with('CF-OUTPUT: text=') || key in seen { return error('invalid/duplicate native output case') }
		seen[key] = true
	}
	native_case(lines, 'encoding=0x100 external=false range=0,6 capacity=0 query=false', 0, 0, '')!
	native_case(lines, 'encoding=0x100 external=false range=0,6 capacity=0 query=true', 6, 12, '')!
	native_case(lines, 'encoding=0x100 external=false range=0,6 capacity=7 query=false', 3, 6, '41000000c003')!
	native_case(lines, 'encoding=0x100 external=false range=0,6 capacity=16 query=false', 6, 12, '41000000c0033cd8aedf5a00')!
	// Record the native BOM over-capacity behavior; the runner deliberately bounds it.
	native_case(lines, 'encoding=0x100 external=true range=0,6 capacity=0 query=false', 0, 2, 'fffe')!
	native_case(lines, 'encoding=0x100 external=true range=0,6 capacity=0 query=true', 6, 14, '')!
	native_case(lines, 'encoding=0x100 external=true range=0,6 capacity=16 query=false', 6, 14, 'fffe41000000c0033cd8aedf5a00')!
	native_case(lines, 'encoding=0x14000100 external=false range=0,6 capacity=0 query=true', 6, 12, '')!
	native_case(lines, 'encoding=0x14000100 external=true range=0,6 capacity=16 query=false', 6, 12, '41000000c0033cd8aedf5a00')!
	native_case(lines, 'encoding=0x14000100 external=false range=3,1 capacity=2 query=false', 1, 2, '3cd8')!
	native_case(lines, 'encoding=0x14000100 external=false range=4,1 capacity=2 query=false', 1, 2, 'aedf')!
	native_case(lines, 'encoding=0x14000100 external=false range=3,2 capacity=2 query=false', 1, 2, '3cd8')!
	native_case(lines, 'encoding=0x10000100 external=true range=0,6 capacity=16 query=false', 6, 12, '0041000003c0d83cdfae005a')!
	native_case(lines, 'encoding=0x8000100 external=false range=0,6 capacity=0 query=false', 6, 9, '')!
	native_case(lines, 'encoding=0x600 external=false range=0,6 capacity=0 query=false', 0, 0, '')!
}

fn cstring_observations(out string) ! {
	lines := require_text(out, 'cstring-inspect.log', [])!.split_into_lines().filter(it.starts_with('CSTRING-NATIVE:'))
	mut expected := map[string]bool{}
	for name in ['NSString', 'NSMutableString'] {
		prefix := 'CSTRING-NATIVE: class=' + name
		expected[prefix + ' types=@32@0:8r*16Q24'] = true
		for encoding in [1, 4] {
			for value in 1 .. 256 {
				input := '${value:02x}'
				output := if value < 128 { input } else if encoding == 1 {
					'${(0xc0 | (value >> 6)):02x}${(0x80 | (value & 0x3f)):02x}'
				} else if value == 0xa9 { 'efbfbd' } else { 'nil' }
				expected[prefix + ' encoding=${encoding} input=' + input + ' output=' + output] = true
			}
		}
		inputs := ['efbbbf41', 'efbbbfefbbbf41', '41efbbbf42', 'c3a9f09f9880',
			'c080', 'eda080', 'f4908080', 'e282', 'a9a9', '41a9', 'a941', 'efbbbfa9',
			'c2a9', 'c2a9a9', 'a9c2a9', 'a980', 'c3a9ff']
		outputs := ['41', 'efbbbf41', '41efbbbf42', 'c3a9f09f9880',
			'nil', 'nil', 'nil', 'nil', 'efbfbdefbfbd', '41efbfbd', 'efbfbd41', 'efbfbd',
			'c2a9', 'c2a9efbfbd', 'efbfbdc2a9', 'nil', 'nil']
		for i, input in inputs {
			expected[prefix + ' encoding=4 input=' + input + ' output=' + outputs[i]] = true
		}
	}
	if lines.len != expected.len { return error('incomplete native CString matrix: ${lines.len} records, expected ${expected.len}') }
	mut seen := map[string]bool{}
	for line in lines {
		if line !in expected || line in seen { return error('changed or repeated native CString case: ' + line) }
		seen[line] = true
	}
	if seen.len != expected.len { return error('missing native CString case') }
}

fn float_observations(out string) ! {
	lines := require_text(out, 'inspect.log', [])!.split_into_lines().filter(it.starts_with('FLOAT-'))
	cases := stringfloatcases.cases()
	if cases.len != 675 { return error('changed float fixture count') }
	mut expected := []string{}
	for name in ['NSString', 'NSMutableString'] {
		expected << 'FLOAT-METADATA: class=' + name + ' types=f16@0:8'
		for item in cases {
			expected << 'FLOAT-NATIVE: class=' + name + ' input=' + item.input.bytes().hex() + ' bits=' + '${item.bits:08x}'
		}
	}
	expected << 'FLOAT-NATIVE: observations=1350 PASS'
	if lines.len != expected.len { return error('incomplete native float matrix') }
	for i, line in lines {
		if line != expected[i] { return error('changed native float observation at record ' + i.str()) }
	}
}

fn results(out string) ! {
	revision := os.read_file(out + '/source-revision.txt')!.trim_space()
	if revision.len != 40 || revision.bytes().any(!it.is_hex_digit()) { return error('invalid revision') }
	for path in ['source/compat/ios/faultprobe/fault.c.v', 'source/compat/ios/runner/native.c.v',
		'source/compat/ios/runner/vm_probe.c.v', 'source/compat/ios/runner/vm_probe_test.v',
		'source/tests/ios/probefault/check.c.v', 'source/tests/ios/native-init.v',
		'source/tests/ios/notification-checks.v', 'source/tests/ios/notification-vm.v',
		'source/compat/ios/runner/files.c.v', 'source/compat/ios/runner/blocks.c.v',
		'source/tests/ios/string-cstring-evidence.v', 'source/tests/ios/string-cstring-run.v',
		'source/tests/ios/inspect-string-cstring.v', 'source/compat/ios/runner/ns_string_cstring_test.v',
		'source/compat/ios/runner/ns_mutable_string.c.v',
		'source/compat/ios/runner/ns_string_float.c.v', 'source/compat/ios/runner/ns_string_float_test.v',
		'source/compat/ios/stringfloatcases/cases.v', 'source/tests/ios/inspect-string-float.v',
		'source/tests/ios/string-float-run.v', 'source/tests/ios/string-float-evidence.v',
		'source/tests/ios/bundle-receipt-evidence.v', 'source/tests/ios/bundle-receipt-run.v',
		'source/tests/ios/inspect-bundle-receipt.v', 'source/compat/ios/runner/ns_bundle_receipt_test.v',
		'source/compat/ios/runner/platform_frameworks.c.v', 'source/compat/ios/runner/objc_runtime.c.v',
		'source/tests/ios/cf-string-output-run.v',
		'source/tests/ios/inspect-cf-string-output.v', 'source/tests/ios/inspect-search-path-calls.v',
		'source/compat/ios/runner/core_foundation.c.v', 'source/compat/ios/runner/cf_string_output_test.v',
		'source/compat/ios/runner/ns_search_paths.c.v', 'source/compat/ios/runner/ns_search_paths_test.v',
		'source/compat/ios/runner/ns_home_directory.c.v', 'source/compat/ios/runner/ns_home_directory_test.v', 'source/compat/ios/runner/block_byref_test.v',
		'source/compat/ios/runner/foundation.c.v', 'source/compat/ios/runner/scenes.c.v',
		'source/compat/ios/runner/objc_constant_dictionary.c.v',
		'source/compat/ios/runner/objc_constant_dictionary_test.v',
		'source/compat/ios/runner/inline_pthread_self.c.v',
		'source/compat/ios/runner/inline_pthread_self_test.v',
		'source/tests/ios/inline-pthread-self-run.v', 'source-files.txt', 'build-inputs.sha256',
		'notification-checks', 'notification-vm', 'string-cstring-evidence', 'inventory-inputs',
		'inspect-search-path-calls', 'calls-import/search-path-calls.txt', 'calls-thunk/search-path-calls.txt',
		'inspect-cf-string-output', 'native-output.txt', 'cf-string-arguments.txt',
		'string-cstring-checks', 'string-cstring-checks.c', 'inspect-string-cstring',
		'string-float-checks', 'string-float-checks.c', 'inspect-string-float', 'string-float-evidence',
		'bundle-receipt-checks', 'bundle-receipt-checks.c', 'inspect-bundle-receipt', 'inherited-evidence.txt',
		'cf-string-output-checks', 'cf-string-output-checks.c',
		'search-path-checks', 'search-path-checks.c', 'home-directory-checks', 'home-directory-checks.c',
		'checkpoint-run', 'inline-pthread-self-checks', 'inline-pthread-self-checks.c',
		'native-init', 'native-init.c', 'run-ios-gles', 'run-ios-gles.c',
		'vm-probe-checks', 'vm-probe-checks.c', 'block-byref-checks', 'block-byref-checks.c',
		'dictionary-snapshot-checks', 'dictionary-snapshot-checks.c',
		'application/FortniteClient-IOS-Shipping', 'application/Frameworks/EOSSDK.framework/EOSSDK',
		'application/Frameworks/MarketplaceKitWrapper.framework/MarketplaceKitWrapper'] {
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
	for label in ['host-generate', 'host-object-0', 'host-object-1', 'host-object-2', 'host-object-3',
		'host-link', 'host', 'host-deterministic', 'inspect-build', 'inspect', 'build-string-float', 'build-string-cstring', 'build-bundle-receipt', 'build-cf-string-output', 'build-search-path', 'build-home-directory', 'build-init', 'build-inline-pthread-self', 'build-dictionary-snapshot', 'build-block-byref', 'build-vm-probe', 'build-run-ios-gles', 'probe-no-ads'] {
		if os.read_file(out + '/' + label + '.status.txt')!.trim_space() != '0' { return error(label + ' failed') }
		require_text(out, label + '.log', [])!
	}
	for label in ['host', 'host-deterministic'] {
		require_text(out, label + '.log', [float_native_marker, float_marker])!
		require_text(out, 'cstring-' + label + '.log', [cstring_native_marker, cstring_marker])!
		if os.read_file(out + '/cstring-' + label + '.status.txt')!.trim_space() != '0' { return error('inherited CString host failed') }
		require_text(out, 'receipt-' + label + '.log', [receipt_native_marker, receipt_marker])!
		if os.read_file(out + '/receipt-' + label + '.status.txt')!.trim_space() != '0' { return error('inherited receipt host failed') }
	}
	require_text(out, 'receipt-inspect.log', [inspector_marker])!
	cstring_observations(out)!
	float_observations(out)!
	require_text(out, 'inherited-evidence.txt', [
		'CF static/native observations inherited from cf-string-output-20261026',
		'source 0607e5a5ba82b9ac0dbd7c8034ff40d765546890',
		'manifest 4e3cb335b8b506cb371070ba391c2e9ae289e02e1c52d8ac774eb2d7016ecf56',
		'Receipt host/native observations inherited from bundle-receipt-20261026',
		'source 48d373e4860ea8896c3a33c618a71181c57b219c',
		'manifest d10cf1facae48d47a06894efb71b8f7883f67bc25494d8d1c0b4fd0d126cafea',
		'CString host/native observations inherited from string-cstring-20261026',
		'source b25fba5a4c42f2655d1a814b340abeba3173fa90',
		'manifest 911924675d2015f133ebc6a8384ec824dfbd45cf9170adc7b97ba1f8b55db885'])!
	import_call := require_text(out, 'calls-import/search-path-calls.txt', ['SEARCH-PATH-CALL: pc=0x107c28c90 stub=0x10c63b2b0'])!
	callers := require_text(out, 'calls-thunk/search-path-calls.txt', [
		'SEARCH-PATH-CALL: pc=0x1005a856c stub=0x107c28c90',
		'SEARCH-PATH-CALL: pc=0x1005c6608 stub=0x107c28c90',
		'SEARCH-PATH-CALL: pc=0x1005c6640 stub=0x107c28c90'])!
	if import_call.count('SEARCH-PATH-CALL:') != 1 || callers.count('SEARCH-PATH-CALL:') != 3 { return error('unexpected static caller count') }
	require_text(out, 'cf-string-arguments.txt', ['1005cf69c:', 'mov\tw3, #0x100', 'movk\tw3, #0x1400, lsl #16', 'mov\tw4, #0x3f', 'mov\tw5, #0x0'])!
	native_observations(out)!
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
		float_marker, 'IOS-NATIVE: /opt/ios/string-float-checks wait status 0',
		cstring_marker, 'IOS-NATIVE: /opt/ios/string-cstring-checks wait status 0',
		receipt_marker, 'IOS-NATIVE: /opt/ios/bundle-receipt-checks wait status 0',
		output_marker, 'IOS-NATIVE: /opt/ios/cf-string-output-checks wait status 0',
		search_marker, 'IOS-NATIVE: /opt/ios/search-path-checks wait status 0',
		home_marker, 'IOS-NATIVE: /opt/ios/home-directory-checks wait status 0',
		search_trace, 'iOS probe image: base=0x', 'Using MallocBinned3 allocator.',
		expected_application_stop,
		'IOS-NATIVE: /opt/ios/run-ios wait status 256',
		'FORTNITE PROBE: process exit status 1', 'FORTNITE PROBE COMPLETE'])!
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
	mut final_budget := false
	for line in serial.split_into_lines() {
		if line.starts_with('iOS memory: os_proc_available_memory=') {
			value := line.all_after('=')
			if value == '' || value.bytes().any(!it.is_digit()) || value.u64() == 0 || value.u64() > 2147483648 {
				return error('invalid or zero application headroom')
			}
			queries++
		}
		if line.starts_with('IOS-PROBE-BUDGET: final current=') {
			if !line.contains('oom 0;oom_kill 0;') { return error('application cgroup OOM') }
			final_budget = true
		}
	}
	if queries != 7 || !final_budget { return error('changed application memory accounting') }
	if serial.count('iOS +load: ') != 9 || serial.count('iOS startup: initializers for ') != 3
		|| serial.count(entry_trace) != 1 { return error('unexpected startup boundary') }
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
}

fn selftest(out string) ! {
	check(out)!
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
	for changed in [original.replace('size=0x600000000', 'size=0x600000001'),
		original.replace('0xf1000000', '0xf0000000'),
		original.replace(result, 'result=0xffffffffffffffff'),
		original.replace(result, 'result=0x0'),
		original.replace('IOS-PROBE-VM:', 'REMOVED-VM:')] {
		if changed == original { return error('selftest did not change VM diagnostics') }
		rejected = false
		vm_reservation(changed.replace('\r\n', '\n')) or { rejected = true }
		if !rejected { return error('changed VM diagnostics accepted') }
	}
	println('changed VM size, tag, failed/null result and missing trace: rejected')
	native_log := out + '/native-output.txt'
	native_original := os.read_file(native_log)!
	for changed in [native_original.replace('used=12', 'used=13'),
		native_original.all_after('\n'), native_original + native_original.all_before('\n') + '\n'] {
		if changed == native_original { return error('selftest did not change native output') }
		os.write_file(native_log, changed)!
		rejected = false
		native_observations(out) or { rejected = true }
		os.write_file(native_log, native_original)!
		if !rejected { return error('changed native observations accepted') }
	}
	println('changed native bytes-used, missing and repeated matrix cases: rejected')
	cstring_log := out + '/cstring-inspect.log'
	cstring_original := os.read_file(cstring_log)!
	for changed in [cstring_original.replace('encoding=1', 'encoding=2'),
		cstring_original.replace('output=efbfbd', 'output=c2a9'),
		cstring_original.replace('types=@32@0:8r*16Q24', 'types=@32@0:8@16Q24'),
		cstring_original.replace('CSTRING-NATIVE: class=NSString types=', 'REMOVED: types='),
		cstring_original + 'CSTRING-NATIVE: class=NSString types=@32@0:8r*16Q24\n'] {
		if changed == cstring_original { return error('selftest did not change CString observations') }
		os.write_file(cstring_log, changed)!
		rejected = false
		cstring_observations(out) or { rejected = true }
		os.write_file(cstring_log, cstring_original)!
		if !rejected { return error('changed native CString observation accepted') }
	}
	println('changed CString encoding, output, metadata, missing and repeated matrix cases: rejected')
	float_log := out + '/inspect.log'
	float_original := os.read_file(float_log)!
	for changed in [float_original.replace('types=f16@0:8', 'types=d16@0:8'),
		float_original.replace('bits=3fc00000', 'bits=3fc00001'),
		float_original.replace('FLOAT-METADATA: class=NSString', 'REMOVED: class=NSString'),
		float_original.replace('FLOAT-NATIVE: observations=1350 PASS', 'FLOAT-NATIVE: observations=1349 PASS'),
		float_original + 'FLOAT-NATIVE: class=NSString input= bits=00000000\n'] {
		if changed == float_original { return error('selftest did not change float observations') }
		os.write_file(float_log, changed)!
		rejected = false
		float_observations(out) or { rejected = true }
		os.write_file(float_log, float_original)!
		if !rejected { return error('changed native float observation accepted') }
	}
	println('changed float metadata, bits, missing and repeated matrix records: rejected')

	receipt_log := out + '/receipt-inspect.log'
	receipt_original := os.read_file(receipt_log)!
	os.write_file(receipt_log, receipt_original.replace('unbundled=nil', 'unbundled=present'))!
	rejected = false
	results(out) or { rejected = true }
	os.write_file(receipt_log, receipt_original)!
	if !rejected { return error('changed native receipt observation accepted') }
	println('changed native receipt observation: rejected')
	for changed in [original.replace(float_marker, 'REMOVED-FLOAT-VALIDATION'),
		original.replace('/opt/ios/string-float-checks wait status 0', '/opt/ios/string-float-checks wait status 1'),
		original.replace(cstring_marker, 'REMOVED-CSTRING-VALIDATION'),
		original.replace('/opt/ios/string-cstring-checks wait status 0', '/opt/ios/string-cstring-checks wait status 1'),
		original.replace(receipt_marker, 'REMOVED-RECEIPT-VALIDATION'),
		original.replace('/opt/ios/bundle-receipt-checks wait status 0', '/opt/ios/bundle-receipt-checks wait status 1'),
		original.replace(output_marker, 'REMOVED-OUTPUT-VALIDATION'),
		original.replace('/opt/ios/cf-string-output-checks wait status 0', '/opt/ios/cf-string-output-checks wait status 1'),
		original.replace(search_marker, 'REMOVED-SEARCH-PATH-VALIDATION'),
		original.replace(home_marker, 'REMOVED-HOME-VALIDATION'),
		original.replace('/opt/ios/search-path-checks wait status 0', '/opt/ios/search-path-checks wait status 1'),
		original.replace('/opt/ios/home-directory-checks wait status 0', '/opt/ios/home-directory-checks wait status 1'),
		original.replace(search_trace, search_trace.replace('directory=14', 'directory=13')),
		original.replace(search_trace, search_trace.replace('domain=1', 'domain=2')),
		original.replace(search_trace, search_trace.replace('expand=1', 'expand=0')),
		original.replace(search_trace, search_trace.replace('/opt/Library/Application Support', '/opt/Documents')),
		original + '\n' + search_trace + '\n',
		original.replace(documents_trace, documents_trace.replace('directory=9', 'directory=14')),
		original.replace(documents_trace, documents_trace.replace('/opt/Documents', '/opt/Library')),
		original.replace(entry_trace, 'REMOVED-APPLICATION-ENTRY'),
		original + '\n' + entry_trace + '\n',
		original.replace(entry_trace, '') + '\n' + entry_trace + '\n',
		original.replace(inline_marker, 'REMOVED-INLINE-VALIDATION'),
		original.replace(large_image_marker, 'REMOVED-LARGE-IMAGE-VALIDATION'),
		original.replace(translation_marker, translation_marker.replace('13', '12')),
		original.replace(expected_application_stop, 'V panic: changed Foundation boundary'),
		original.replace('FORTNITE PROBE: process exit status 1', 'FORTNITE PROBE: process exit status 0'),
		original + '\nIOS-PROBE-FAULT: signal=unexpected\n',
		original + '\npanic: unexpected\n'] {
		if changed == original { return error('selftest did not change boundary') }
		os.write_file(log, changed)!
		rejected = false
		results(out) or { rejected = true }
		os.write_file(log, original)!
		if !rejected { return error('missing fixture validation or changed boundary accepted') }
	}
	println('missing fixture validation, failed waits, changed search arguments/path/count, missing/repeated/misordered entry, translation/panic/exit and extra fault/panic: rejected')
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
	if os.args.len != 3 { eprintln('usage: string-float-evidence seal|check|selftest DIR | hash FILE'); exit(2) }
	if os.args[1] == 'hash' { println(digest(os.args[2]) or { eprintln(err); exit(1) }); return }
	out := os.real_path(os.args[2]); root := os.real_path(os.getwd())
	if !os.is_dir(out) || out == root || out.starts_with(root + '/') { eprintln('evidence must exist outside the repository'); exit(2) }
	match os.args[1] {
		'seal' { seal(out) or { eprintln(err); exit(1) } }
		'check' { check(out) or { eprintln(err); exit(1) } }
		'selftest' { selftest(out) or { eprintln(err); exit(1) } }
		else { eprintln('unknown mode'); exit(2) }
	}
	println('NSString floatValue evidence ' + os.args[1] + ': PASS (application startup remains incomplete)')
}
