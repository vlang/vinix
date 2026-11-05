// SPDX-License-Identifier: GPL-2.0-or-later
// Protocol controls below are generated V helpers, not game rendering evidence.
module linuxcheck

import encoding.binary
import json2
import os
import probedesktop
import time

fn desktop_test_reply(fd int, payload []u8, invalid bool) {
	mut header := []u8{len: 128}
	binary.little_endian_put_u32(mut header, 0x56415050)
	header[4] = 10
	header[56] = 1
	binary.little_endian_put_u32_at(mut header, u32(payload.len), 124)
	if invalid { header[0] = 0 }
	assert C.write(fd, header.data, usize(header.len)) == header.len
	if payload.len > 0 {
		assert C.write(fd, payload.data, usize(payload.len)) == payload.len
	}
}

fn desktop_test_application(mode string) {
	request := os.getenv('VINIX_REQUEST_FD').int()
	response := os.getenv('VINIX_RESPONSE_FD').int()
	assert request >= 3 && response >= 3 && request != response
	assert os.getenv('VINIX_IOS_EXIT_ON_CLOSE') == '1'
	if path := os.getenv_opt('VINIX_IOS_DESKTOP_TEST_PID') {
		os.write_file(path, '${os.getpid()}\n') or { panic(err) }
	}
	if mode == 'silent' { time.sleep(10 * time.second) }
	if mode == 'delayed' { time.sleep(300 * time.millisecond) }
	desktop_test_reply(response, []u8{}, mode == 'bad-header')
	if mode == 'bad-header' { C._exit(19) }
	for {
		mut command := []u8{len: 136}
		mut offset := 0
		for offset < command.len {
			n := C.read(request, unsafe { &command[offset] }, usize(command.len - offset))
			if n < 0 && C.errno == C.EINTR { continue }
			if n <= 0 { C._exit(21) }
			offset += int(n)
		}
		assert command[..5] == [u8(0x50), 0x50, 0x41, 0x56, 10]
		assert binary.little_endian_u32_at(command, 8) == 1024
		assert binary.little_endian_u32_at(command, 12) == 768
		match command[5] {
			1 { desktop_test_reply(response, []u8{len: 330}, false) }
			4 { desktop_test_reply(response, [u8(0)], false) }
			6 {
				desktop_test_reply(response, []u8{}, false)
				C._exit(37)
			}
			else { C._exit(22) }
		}
	}
}

fn testsuite_begin() {
	if os.args.len > 1 && os.args[1] == '--linux-probe-desktop'
		&& os.getenv('VINIX_IOS_DESKTOP_TEST_SKIP_HOOK') == '1' {
		C._exit(0)
	}
	if maybe_probe_desktop_child() or {
		eprintln(err)
		exit(125)
	} {
		C._exit(0)
	}
	if os.args.len == 3 && os.args[1] == '--peer-control' {
		desktop_test_application(os.args[2])
		C._exit(99)
	}
	mode := os.getenv('VINIX_IOS_DESKTOP_TEST_MODE')
	if mode == '' { return }
	if os.args.len == 3 && os.args[1] == '--inspect' { C._exit(0) }
	if os.args.len == 3 && os.args[1] == '--audit' { C._exit(1) }
	assert os.args.len == 4 && os.args[1] == '--probe-no-ads'
	assert os.args[3] == 'forwarded-argument'
	desktop_test_application(mode)
	C._exit(98)
}

fn desktop_test_directory(label string) string {
	path := os.join_path(os.temp_dir(), 'vinix-linux-desktop-${os.getpid()}-${time.sys_mono_now()}-${label}')
	os.mkdir(path) or { panic(err) }
	return path
}

fn desktop_test_app(base string) !ProbeInput {
	app := base + '/Control.app'
	os.mkdir(app)!
	os.write_file(app + '/Info.plist', '<plist version="1.0"><dict><key>CFBundleExecutable</key>' +
		'<string>Control</string><key>CFBundleIdentifier</key>' +
		'<string>org.vinix.synthetic-desktop-control</string></dict></plist>')!
	write_smoke(app + '/Control')!
	return probe_input(app, 'Control')
}

fn desktop_test_runtime(base string, mode string) ProbeRuntime {
	mut env := os.environ()
	env['VINIX_IOS_DESKTOP_TEST_MODE'] = mode
	env['VINIX_IOS_DESKTOP_TEST_PID'] = base + '/application.pid'
	path := os.real_path(os.args[0])
	return ProbeRuntime{
		invocation:         [path]
		arguments:          ['forwarded-argument']
		environment:        env
		profile:            'generated V protocol helper; not an ARM64 game runtime'
		built_backends:     ['gles']
		required_backends:  ['gles']
		deadline_seconds:   6
		desktop_driver:     path
		desktop_startup_ms: 4000
		desktop_reply_ms:   100
		desktop_session_ms: 100
	}
}

fn test_desktop_probe_allows_slow_startup_and_preserves_actual_app_exit() {
	base := desktop_test_directory('startup')
	defer { os.rmdir_all(base) or {} }
	input := desktop_test_app(base) or { panic(err) }
	out := base + '/out'
	result := probe_capture(out, input, desktop_test_runtime(base, 'delayed')) or { panic(err) }
	assert result.capture_complete && result.desktop_enabled && result.desktop_handshake
	assert !result.desktop_forced && result.wrapper_exit == 0 && result.application_exit == 37
	assert os.read_file(out + '/application-wrapper.status.txt') or { panic(err) } == '0\n'
	assert os.read_file(out + '/application.status.txt') or { panic(err) } == '37\n'
	observed := probe_desktop_observation(out + '/desktop-observation.json') or { panic(err) }
	assert observed.wait_status == 37 << 8 && observed.closed && observed.builds == 1 && observed.polls >= 1
	assert observed.nodes == 1 && observed.images == 0
	assert (os.read_file(out + '/application-wrapper.guard.txt') or { panic(err) }).contains('residual_descendants=0')
	assert input.entries == probe_snapshot(input.bundle) or { panic(err) }
}

fn test_desktop_peer_default_startup_retains_the_existing_reply_limit() {
	// Explicit startup is opt-in. Existing callers with only reply_ms still
	// time out before this generated helper's delayed initial handshake.
	result := probedesktop.run(os.real_path(os.args[0]), ['--peer-control', 'delayed'],
		probe_desktop_setup, '', probedesktop.Config{ reply_ms: 75, session_ms: 0 }) or { panic(err) }
	assert !result.handshake && result.stop == 'desktop reply deadline'
	assert probe_desktop_exit(result.wait_status) or { panic(err) } != 0
}

fn test_desktop_probe_records_protocol_failure_and_bounded_forced_termination() {
	for mode in ['bad-header', 'silent'] {
		base := desktop_test_directory(mode)
		input := desktop_test_app(base) or { panic(err) }
		runtime := desktop_test_runtime(base, mode)
		out := base + '/out'
		result := probe_capture(out, input, ProbeRuntime{ ...runtime, desktop_startup_ms: 100 }) or { panic(err) }
		assert result.capture_complete && result.wrapper_exit == 0 && !result.desktop_handshake
		observed := probe_desktop_observation(out + '/desktop-observation.json') or { panic(err) }
		if mode == 'bad-header' {
			assert result.application_exit == 19 && !result.desktop_forced
			assert observed.stop == 'invalid desktop reply header'
		} else {
			assert result.application_exit == 137 && result.desktop_forced
			assert observed.stop == 'desktop reply deadline'
		}
		pid := (os.read_file(base + '/application.pid') or { panic(err) }).int()
		assert pid > 0 && C.kill(pid, 0) == -1 && C.errno == C.ESRCH
		os.rmdir_all(base) or { panic(err) }
	}
}

fn test_desktop_probe_outer_guard_reaps_wrapper_and_app_without_inventing_app_status() {
	base := desktop_test_directory('outer-timeout')
	defer { os.rmdir_all(base) or {} }
	input := desktop_test_app(base) or { panic(err) }
	runtime := desktop_test_runtime(base, 'silent')
	out := base + '/out'
	mut refused := false
	probe_capture(out, input, ProbeRuntime{ ...runtime, deadline_seconds: 1, desktop_startup_ms: 1000 }) or {
		refused = err.msg().contains('deadline')
	}
	assert refused
	result := json2.decode[ProbeResult](os.read_file(out + '/probe-result.json') or { panic(err) }) or { panic(err) }
	assert !result.capture_complete && result.desktop_enabled && result.wrapper_exit >= 128
	assert result.application_exit == -1 && !os.exists(out + '/application.status.txt')
	assert (os.read_file(out + '/application-wrapper.guard.txt') or { panic(err) }).contains('cleanup_complete=true')
	pid := (os.read_file(base + '/application.pid') or { panic(err) }).int()
	assert pid > 0 && C.kill(pid, 0) == -1 && C.errno == C.ESRCH
}

fn test_desktop_probe_requires_a_real_helper_observation_and_valid_limits() {
	base := desktop_test_directory('admission')
	defer { os.rmdir_all(base) or {} }
	input := desktop_test_app(base) or { panic(err) }
	runtime := desktop_test_runtime(base, 'delayed')
	for invalid in [ProbeRuntime{ ...runtime, desktop_startup_ms: -1 },
		ProbeRuntime{ ...runtime, desktop_startup_ms: 6001 },
		ProbeRuntime{ ...runtime, desktop_reply_ms: 0 },
		ProbeRuntime{ ...runtime, desktop_session_ms: 60001 }] {
		mut rejected := false
		probe_capture(base + '/invalid', input, invalid) or { rejected = true }
		assert rejected && !os.exists(base + '/invalid')
	}
	mut env := runtime.environment.clone()
	env['VINIX_IOS_DESKTOP_TEST_SKIP_HOOK'] = '1'
	mut rejected := false
	probe_capture(base + '/missing-observation', input, ProbeRuntime{ ...runtime, environment: env }) or { rejected = true }
	assert rejected
	result := json2.decode[ProbeResult](os.read_file(base + '/missing-observation/probe-result.json') or { panic(err) }) or { panic(err) }
	assert !result.capture_complete && result.wrapper_exit == 0 && result.application_exit == -1
	path := base + '/observation.json'
	os.write_file(path, '{}') or { panic(err) }
	rejected = false
	probe_desktop_observation(path) or { rejected = err.msg().contains('omitted') }
	assert rejected
	for status in [-1, 127, 65536, 0x7f00 | 9] {
		rejected = false
		probe_desktop_exit(status) or { rejected = true }
		assert rejected
	}
}
