// SPDX-License-Identifier: GPL-2.0-or-later
// Generated data and the host helper below test capture behavior, not Fortnite.
module linuxcheck

import crypto.sha256
import json2
import os
import time

fn C.mkfifo(&char, u32) int

fn testsuite_begin() {
	mode := os.getenv('VINIX_IOS_PROBE_TEST_HELPER')
	if mode == '' { return }
	if os.args.len != 3 { C._exit(90) }
	stage := os.args[1]
	if stage !in ['--inspect', '--audit', '--probe-no-ads'] { C._exit(91) }
	mut calls := os.open_append(os.getenv('VINIX_IOS_PROBE_TEST_CALLS')) or { exit(92) }
	calls.writeln(stage) or { exit(93) }
	calls.close()
	if stage == '--inspect' {
		println('synthetic harness inspection control')
		C.fflush(unsafe { nil })
		C._exit(if mode == 'inspect-failure' { 12 } else { 0 })
	}
	if stage == '--audit' {
		println('synthetic harness unresolved-import control')
		C.fflush(unsafe { nil })
		C._exit(1)
	}
	if mode == 'mutation' {
		os.write_file(os.dir(os.args[2]) + '/.hidden/resource', 'changed by harness control') or { exit(94) }
	}
	if mode == 'timeout' { time.sleep(5 * time.second) }
	println('V panic: intentional synthetic harness diagnostic')
	C.fflush(unsafe { nil })
	C._exit(37)
}

fn probe_test_directory(label string) string {
	path := os.join_path(os.temp_dir(), 'vinix-ios-probe-${os.getpid()}-${time.sys_mono_now()}-${label}')
	os.mkdir(path) or { panic(err) }
	return path
}

fn probe_test_app(base string) !ProbeInput {
	app := base + '/Supplied.app'
	os.mkdir(app)!
	os.mkdir(app + '/Frameworks')!
	os.mkdir(app + '/.hidden')!
	os.write_file(app + '/.hidden/resource', 'original hidden resource')!
	os.write_file(app + '/Info.plist', '<?xml version="1.0"?><plist version="1.0"><dict>' +
		'<key>CFBundleExecutable</key><string>Application</string>' +
		'<key>CFBundleIdentifier</key><string>org.vinix.synthetic-probe-control</string>' +
		'</dict></plist>')!
	write_smoke(app + '/Application')!
	return probe_input(app, 'Application')
}

fn probe_test_runtime(base string, mode string) ProbeRuntime {
	mut env := os.environ()
	env['VINIX_IOS_PROBE_TEST_HELPER'] = mode
	env['VINIX_IOS_PROBE_TEST_CALLS'] = base + '/calls.txt'
	return ProbeRuntime{
		invocation:        [os.real_path(os.args[0])]
		environment:       env
		profile:           'generated host helper: capture controls only; not an ARM64 game runtime'
		built_backends:    ['gles']
		required_backends: ['gles']
		deadline_seconds:  3
	}
}

fn probe_test_input_refused(bundle string, executable string) bool {
	probe_input(bundle, executable) or { return true }
	return false
}

fn test_probe_requires_explicit_matching_plist_and_valid_main_before_launch() {
	base := probe_test_directory('validation')
	defer { os.rmdir_all(base) or {} }
	assert probe_test_input_refused('', '')
	assert probe_test_input_refused(base + '/missing', 'Application')
	input := probe_test_app(base) or { panic(err) }
	assert input.bundle_identifier == 'org.vinix.synthetic-probe-control'
	assert input.executable == input.bundle + '/Application'
	assert probe_test_input_refused(input.bundle, '')
	assert probe_test_input_refused(input.bundle, '../Application')
	assert probe_test_input_refused(input.bundle, base + '/Application')
	assert probe_test_input_refused(input.bundle, 'Frameworks/Application')
	assert probe_test_input_refused(input.bundle, 'Missing')
	info := os.read_file(input.bundle + '/Info.plist') or { panic(err) }
	for invalid in ['', 'malformed plist',
		info.replace('<string>Application</string>', '<string>Other</string>')] {
		os.write_file(input.bundle + '/Info.plist', invalid) or { panic(err) }
		assert probe_test_input_refused(input.bundle, 'Application')
	}
	os.write_file(input.bundle + '/Info.plist', info) or { panic(err) }
	os.write_file(input.executable, 'not Mach-O') or { panic(err) }
	assert probe_test_input_refused(input.bundle, 'Application')
	for kind in ['wrong-cpu', 'arm64e', 'encrypted', 'missing-entry'] {
		mut bytes := smoke_image()
		match kind {
			'wrong-cpu' { smoke_put(mut bytes, 4, 0x1000007, 4) }
			'arm64e' { smoke_put(mut bytes, 8, 2, 4) }
			'encrypted' {
				smoke_put(mut bytes, 16, 5, 4)
				smoke_put(mut bytes, 20, 296, 4)
				smoke_put(mut bytes, 304, 0x2c, 4)
				smoke_put(mut bytes, 308, 24, 4)
				smoke_put(mut bytes, 320, 1, 4)
			}
			else { smoke_put(mut bytes, 256, 0x1b, 4) }
		}
		os.write_file_array(input.executable, bytes) or { panic(err) }
		assert probe_test_input_refused(input.bundle, 'Application')
		unsafe { bytes.free() }
	}
	mut refused := false
	probe_capture(base + '/out', input, probe_test_runtime(base, 'capture')) or { refused = true }
	assert refused && !os.exists(base + '/out') && !os.exists(base + '/calls.txt')
}

fn test_probe_inventories_hidden_files_empty_directories_and_streamed_bytes() {
	base := probe_test_directory('inventory')
	defer { os.rmdir_all(base) or {} }
	input := probe_test_app(base) or { panic(err) }
	data := []u8{len: 1024 * 1024 + 7, init: u8(index % 251)}
	os.write_file_array(input.bundle + '/.hidden/large', data) or { panic(err) }
	pinned := probe_input(input.bundle, input.executable) or { panic(err) }
	assert pinned.entries.any(it.path == '.hidden/resource' && it.kind == 'file')
	assert pinned.entries.any(it.path == 'Frameworks' && it.kind == 'directory')
	assert pinned.entries.any(it.path == '.' && it.kind == 'directory')
	large := pinned.entries.filter(it.path == '.hidden/large')
	assert large.len == 1 && large[0].size == u64(data.len)
	assert large[0].sha256 == sha256.sum(data).hex()
	assert pinned.entries == probe_snapshot(input.bundle) or { panic(err) }
	os.chmod(input.bundle + '/.hidden/large', int(large[0].mode ^ 0o100)) or { panic(err) }
	assert pinned.entries != probe_snapshot(input.bundle) or { panic(err) }
}

fn test_probe_releases_nonempty_macho_runpaths_once() {
	base := probe_test_directory('runpath-ownership')
	defer { os.rmdir_all(base) or {} }
	original := probe_test_app(base) or { panic(err) }
	mut bytes := smoke_image()
	defer { unsafe { bytes.free() } }
	// Append two valid LC_RPATH commands in the unused header padding. The
	// application entry and existing executable/segment layout stay intact.
	paths := ['@loader_path/Frameworks', '@executable_path/Frameworks']
	smoke_put(mut bytes, 16, 6, 4)
	smoke_put(mut bytes, 20, 272 + 80, 4)
	for index, path in paths {
		offset := 304 + index * 40
		smoke_put(mut bytes, offset, 0x8000001c, 4)
		smoke_put(mut bytes, offset + 4, 40, 4)
		smoke_put(mut bytes, offset + 8, 12, 4)
		smoke_name(mut bytes, offset + 12, path)
	}
	os.write_file_array(original.executable, bytes) or { panic(err) }
	for _ in 0 .. 2 {
		input := probe_input(original.bundle, original.executable) or { panic(err) }
		assert input.bundle_identifier == original.bundle_identifier
		assert input.executable == original.executable
		assert input.entries.any(it.path == 'Application' && it.sha256 == sha256.sum(bytes).hex())
	}
}

fn test_probe_build_output_cannot_mutate_the_supplied_app() {
	base := probe_test_directory('build-output')
	defer { os.rmdir_all(base) or {} }
	input := probe_test_app(base) or { panic(err) }
	repository := base + '/repository'
	os.mkdir(repository) or { panic(err) }
	os.symlink(input.bundle, base + '/alias') or { panic(err) }
	for destination in [input.bundle, input.bundle + '/capture', input.bundle + '/.hidden/capture',
		base + '/alias/capture'] {
		mut rejected := false
		fresh_output_outside_app(repository, destination, input.bundle) or {
			rejected = err.msg().contains('outside the supplied application')
		}
		assert rejected
	}
	assert !os.exists(input.bundle + '/capture')
	assert !os.exists(input.bundle + '/.hidden/capture')
	assert input.entries == probe_snapshot(input.bundle) or { panic(err) }
	// A sibling sharing the app's name prefix is outside the protected tree.
	outside := fresh_output_outside_app(repository, input.bundle + '-capture', input.bundle) or { panic(err) }
	assert os.is_dir(outside + '/payload') && os.is_dir(outside + '/tmp')
}

fn test_probe_rejects_root_and_nested_symlinks_and_special_entries_without_opening_fifo() {
	base := probe_test_directory('types')
	defer { os.rmdir_all(base) or {} }
	input := probe_test_app(base) or { panic(err) }
	os.symlink(input.bundle, base + '/alias') or { panic(err) }
	assert probe_test_input_refused(base + '/alias', 'Application')
	for target in [input.executable, base + '/absent', input.bundle + '/Frameworks'] {
		os.symlink(target, input.bundle + '/.hidden/alias') or { panic(err) }
		assert probe_test_input_refused(input.bundle, 'Application')
		os.rm(input.bundle + '/.hidden/alias') or { panic(err) }
	}
	pipe := input.bundle + '/.hidden/fifo'
	assert unsafe { C.mkfifo(pipe.str, 0o600) } == 0
	// No writer exists. A scanner that opens a FIFO before rejecting its type hangs.
	assert probe_test_input_refused(input.bundle, 'Application')
}

fn test_probe_rejects_unqualified_runtime_and_changed_input_without_starting_helper() {
	base := probe_test_directory('prelaunch')
	defer { os.rmdir_all(base) or {} }
	input := probe_test_app(base) or { panic(err) }
	valid := probe_test_runtime(base, 'capture')
	for invalid in [
		ProbeRuntime{ ...valid, profile: '' },
		ProbeRuntime{ ...valid, built_backends: []string{} },
		ProbeRuntime{ ...valid, required_backends: []string{} },
		ProbeRuntime{ ...valid, required_backends: ['cxx'] },
		ProbeRuntime{ ...valid, built_backends: ['gles', 'gles'] },
		ProbeRuntime{ ...valid, required_backends: ['unknown'] },
		ProbeRuntime{ ...valid, deadline_seconds: 0 },
		ProbeRuntime{ ...valid, deadline_seconds: 1801 },
	] {
		mut refused := false
		probe_capture(base + '/out', input, invalid) or { refused = true }
		assert refused
		assert !os.exists(base + '/out') && !os.exists(base + '/calls.txt')
	}
	os.write_file(input.bundle + '/.hidden/resource', 'changed before launch') or { panic(err) }
	mut changed := false
	probe_capture(base + '/out', input, valid) or { changed = err.msg().contains('changed since') }
	assert changed
	assert !os.exists(base + '/out') && !os.exists(base + '/calls.txt')
}

fn test_probe_captures_nonzero_app_and_strict_audit_without_claiming_game_success() {
	base := probe_test_directory('status')
	defer { os.rmdir_all(base) or {} }
	input := probe_test_app(base) or { panic(err) }
	out := base + '/out'
	result := probe_capture(out, input, probe_test_runtime(base, 'capture')) or { panic(err) }
	assert result.capture_complete && result.inspection_exit == 0 && result.audit_exit == 1
	assert result.application_attempted && result.application_exit == 37 && result.application_diagnostic
	assert result.qualification.contains('does not establish')
	assert os.read_file(base + '/calls.txt') or { panic(err) } == '--inspect\n--audit\n--probe-no-ads\n'
	assert os.read_file(out + '/application.status.txt') or { panic(err) } == '37\n'
	assert (os.read_file(out + '/application.guard.txt') or { panic(err) }).contains('cleanup_complete=true')
	assert input.entries == probe_snapshot(input.bundle) or { panic(err) }
	stored := json2.decode[ProbeResult](os.read_file(out + '/probe-result.json') or { panic(err) }) or { panic(err) }
	assert stored == result
	mut replay := false
	probe_capture(out, input, probe_test_runtime(base, 'capture')) or { replay = true }
	assert replay
	mut inside := false
	probe_capture(input.bundle + '/output', input, probe_test_runtime(base, 'capture')) or { inside = true }
	assert inside && !os.exists(input.bundle + '/output')
}

fn test_probe_preserves_failed_inspection_mutation_and_timeout_receipts() {
	for mode in ['inspect-failure', 'mutation', 'timeout'] {
		base := probe_test_directory(mode)
		input := probe_test_app(base) or { panic(err) }
		runtime := probe_test_runtime(base, mode)
		out := base + '/out'
		mut refused := false
		probe_capture(out, input, ProbeRuntime{ ...runtime, deadline_seconds: 1 }) or { refused = true }
		assert refused
		result := json2.decode[ProbeResult](os.read_file(out + '/probe-result.json') or { panic(err) }) or { panic(err) }
		assert !result.capture_complete && result.failure != ''
		assert os.is_file(out + '/app-after.json') && os.is_file(out + '/runtime-after.json')
		if mode == 'inspect-failure' {
			assert result.inspection_exit == 12 && !result.application_attempted
			assert os.read_file(base + '/calls.txt') or { panic(err) } == '--inspect\n'
			assert !os.exists(out + '/audit.command.txt') && !os.exists(out + '/application.command.txt')
		} else if mode == 'mutation' {
			assert result.application_exit == 37 && result.failure.contains('app changed')
		} else {
			assert result.application_attempted && result.application_exit >= 128
			assert result.failure.contains('deadline')
			assert (os.read_file(out + '/application.guard.txt') or { panic(err) }).contains('cleanup_complete=true')
		}
		os.rmdir_all(base) or { panic(err) }
	}
}
