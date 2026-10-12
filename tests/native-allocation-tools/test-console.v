// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hosttest
import json2
import net.unix
import os
import sourcecommand
import time

#include <signal.h>

fn C.kill(i32, i32) i32

fn line(mut connection unix.StreamConn) !map[string]json2.Any {
	mut bytes := []u8{}
	mut buffer := []u8{len: 1}
	for {
		count := connection.read(mut buffer)!
		if count == 0 { return error('console fixture EOF') }
		if buffer[0] == `\n` { return hosttest.decode_json(bytes.bytestr())!.as_map() }
		bytes << buffer[0]
	}
}

fn qmp_fixture(work string, mode string) ! {
	mut server := unix.listen_stream(work + '/qmp.sock')!
	defer { server.close() or {} }
	os.write_file(work + '/server-ready', 'ready')!
	mut connection := server.accept()!
	defer { connection.close() or {} }
	if mode == 'bad-greeting' {
		connection.write_string('not json\n')!
		return
	}
	connection.write_string('{"QMP":{}}\n')!
	mut names := []string{}
	for expected in ['qmp_capabilities', 'cont', 'stop'] {
		request := line(mut connection)!
		assert request.keys() == ['execute']
		assert request['execute']!.str() == expected, request.str()
		names << expected
		os.write_file(work + '/qmp-receipt', names.join('\n') + '\n')!
		if expected == 'cont' {
			if mode in ['signal-2', 'signal-15'] {
				connection.write_string('{"return":{}}\n')!
				deadline := time.sys_mono_now() + u64(30 * time.second)
				for !os.exists(work + '/commands.txt') {
					if time.sys_mono_now() >= deadline {
						return error('measure never queued command')
					}
					time.sleep(20 * time.millisecond)
				}
				pid := os.read_file(work + '/observer-pid')!.int()
				assert C.kill(pid, mode.all_after('signal-').int()) == 0
				continue
			}
			mut console := os.open_append(work + '/console.log')!
			console.write_string(if mode == 'failure' {
				'ALLOC-FAIL controlled\n'
			} else {
				'\xff\n ALLOC-RESULT captured\nALLOC-DONE\n'
			})!
			console.close()
		}
		if expected == 'stop' && mode == 'stop-error' {
			connection.write_string('{"error":{"class":"GenericError","desc":"stop failed"}}\n')!
			return
		}
		connection.write_string('{"event":"ignored"}\n{"return":{}}\n')!
	}
}

fn broker_fixture(work string) ! {
	mut server := unix.listen_stream(work + '/serial.sock')!
	defer { server.close() or {} }
	os.write_file(work + '/server-ready', 'ready')!
	mut connection := server.accept()!
	defer { connection.close() or {} }
	mut data := []u8{len: 65536}
	mut received := []u8{}
	for received.len < 5 {
		count := connection.read(mut data)!
		assert count > 0
		received << data[..count]
	}
	assert received.bytestr() == 'FIRST'
	connection.write_string('first\x00\xff')!
	deadline_first := time.sys_mono_now() + u64(5 * time.second)
	for (os.read_file(work + '/console.log') or { '' }) != 'first\x00\xff' {
		if time.sys_mono_now() >= deadline_first {
			return error('broker did not publish live console data')
		}
		time.sleep(20 * time.millisecond)
	}
	mut commands := os.open_append(work + '/commands.txt')!
	commands.write_string('SECOND')!
	commands.close()
	received.clear()
	for received.len < 6 {
		count := connection.read(mut data)!
		assert count > 0
		received << data[..count]
	}
	assert received.bytestr() == 'SECOND'
	connection.write_string('second\n')!
	deadline := time.sys_mono_now() + u64(5 * time.second)
	for os.read_file(work + '/control.cursor') or { '' } != '11\n' {
		if time.sys_mono_now() >= deadline { return error('broker cursor was not published') }
		time.sleep(20 * time.millisecond)
	}
	os.write_file(work + '/broker-receipt', 'FIRST\nSECOND\n')!
}

struct SignalCase {
	work   string
	signal int
}

fn notify(pid int, pointer voidptr) ! {
	context := unsafe { &SignalCase(pointer) }
	os.write_file(context.work + '/observer-pid', pid.str())!
}

fn wait_ready(work string) ! {
	deadline := time.sys_mono_now() + u64(10 * time.second)
	for !os.exists(work + '/server-ready') {
		if time.sys_mono_now() >= deadline { return error('console fixture did not start') }
		time.sleep(10 * time.millisecond)
	}
}

fn run_owned_fixture(work string, mode string, argv []string) !sourcecommand.Output {
	mut child := os.new_process(os.executable())
	child.set_args(['--server', work, mode])
	child.set_redirect_stdio()
	child.run()
	defer {
		if child.is_alive() { C.kill(child.pid, C.SIGKILL) }
		child.wait()
		child.close()
	}
	wait_ready(work)!
	context := SignalCase{work, if mode.starts_with('signal-') {
		mode.all_after('signal-').int()
	} else {
		0
	}}
	result := sourcecommand.capture_owned(argv, os.environ(), 40, 4 * 1024 * 1024, unsafe { nil }, unsafe { nil }, notify, unsafe { &context }, 0)!
	deadline := time.sys_mono_now() + u64(10 * time.second)
	for child.is_alive() && time.sys_mono_now() < deadline { time.sleep(10 * time.millisecond) }
	assert !child.is_alive(), 'console fixture did not exit'
	stdout := child.stdout_slurp()
	stderr := child.stderr_slurp()
	assert child.code == 0 && !stdout.contains(': fn ') && !stderr.contains(': fn '), stdout + stderr
	return result
}

fn cases(work string) ! {
	os.mkdir(work)!
	for mode in ['success', 'failure', 'bad-greeting', 'stop-error', 'signal-2', 'signal-15'] {
		runtime := work + '/' + mode
		os.mkdir(runtime)!
		os.write_file(runtime + '/console.log', 'old console prefix\n')!
		os.write_file(runtime + '/argv.json', '["qemu","old configuration"]')!
		os.write_file(runtime + '/config.json', '{"guest_compile_command":"gcc /tmp/bench-native.s"}')!
		result := run_owned_fixture(runtime, mode, [
			os.getenv('VINIX_ALLOC_NATIVE_TOOL'),
			'measure',
			runtime + '/state',
			'--runtime',
			runtime,
			'--config',
			runtime + '/config.json',
		])!
		expected := if mode == 'success' {
			0
		} else if mode.starts_with('signal-') {
			128 + mode.all_after('signal-').int()
		} else {
			1
		}
		assert result.status == expected, result.str()
		if mode != 'bad-greeting' {
			assert os.read_file(runtime + '/qmp-receipt')! == 'qmp_capabilities\ncont\nstop\n'
		}
		if mode == 'success' {
			assert os.read_file(runtime + '/state/serial.log')!.bytes() == '\xff\n ALLOC-RESULT captured\nALLOC-DONE\n'.bytes()
		}
		println('RECORDED CONSOLE / offsets / QMP / stop / signals: PASS ' + mode)
		flush_stdout()
	}
	runtime := work + '/broker'
	os.mkdir(runtime)!
	os.write_file(runtime + '/commands.txt', 'FIRST')!
	result := run_owned_fixture(runtime, 'broker', [
		os.getenv('VINIX_ALLOC_NATIVE_TOOL'),
		'control',
		'--runtime',
		runtime,
	])!
	assert result.status == 0, result.str()
	assert os.read_file(runtime + '/control.cursor')! == '11\n'
	assert os.read_file(runtime + '/console.log')!.bytes() == 'first\x00\xffsecond\n'.bytes()
	assert os.read_file(runtime + '/broker-receipt')! == 'FIRST\nSECOND\n'
	println('SERIAL BROKER / raw bytes / queue appends / persistent cursor / EOF: PASS')
}

fn main() {
	if os.args.len == 4 && os.args[1] == '--server' {
		if os.args[3] == 'broker' {
			broker_fixture(os.args[2]) or {
				eprintln(err)
				exit(1)
			}
		} else {
			qmp_fixture(os.args[2], os.args[3]) or {
				eprintln(err)
				exit(1)
			}
		}
		return
	}
	if os.args.len == 3 && os.args[1] == '--drivers' {
		driver_cases(os.args[2]) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len != 2 {
		eprintln('usage: test-console NEW_STATE')
		exit(2)
	}
	cases(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
}

fn driver_cases(work string) ! {
	os.mkdir_all(work + '/scripts')!
	os.mkdir(work + '/build')!
	origin := work + '/scripts/mac-driver'
	os.write_file(origin, 'native driver origin')!
	config := work + '/tests/alloc-bench/results/2026-10-02/user-macos/config.json'
	os.mkdir_all(os.dir(config))!
	os.write_file(config, '{"guest_compile_command":"gcc /tmp/bench-native.s"}')!
	for mode in ['success', 'failure'] {
		runtime := work + '/build/useralloc-macos-runtime'
		if os.exists(runtime) { os.mv(runtime, work + '/build/previous-runtime')! }
		os.mkdir(runtime)!
		os.write_file(runtime + '/console.log', 'old prefix\n')!
		os.write_file(runtime + '/argv.json', '["qemu","saved runtime"]')!
		state := work + '/build/run.' + mode
		result := run_owned_fixture(runtime, mode, [
			os.getenv('VINIX_ALLOC_NATIVE_TOOL'),
			'macos-driver',
			origin,
			'run.' + mode,
		])!
		assert result.status == if mode == 'success' { 0 } else { 1 }, result.str()
		record := hosttest.decode_json(os.read_file(work + '/build/run.exit.json')!)!.as_map()
		assert record['argv']!.as_array()[1]!.str() == 'measure'
		assert record['exit_code']!.int() == result.status
		assert os.read_file(work + '/build/run.runner.log')!.contains(if mode == 'success' {
			'macOS benchmark complete'
		} else {
			'macOS benchmark failed'
		})
		assert os.read_file(runtime + '/qmp-receipt')! == 'qmp_capabilities\ncont\nstop\n'
		assert os.exists(state + '/serial.log')
	}
	println('SAVED MACOS DRIVERS / complete native observer child / QMP stop / logs / success and failure exit records: PASS')
}
