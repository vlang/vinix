// SPDX-License-Identifier: GPL-2.0-or-later
// Host controls for the standalone controller guard. No target build or VM.
module main

import crypto.sha256
import json2
import os
import tools.packages.winejitstream

#include <unistd.h>
#include <signal.h>

fn C.write(int, voidptr, usize) isize
fn C.fork() int
fn C.getppid() int
fn C.kill(int, int) int
fn C.pause() int
fn C._exit(int)

const control_state_limit = u64(20 * 1024 * 1024)
const control_free_kib = u64(550 * 1024)
const descendant_prefix = 'NATIVE GUARD descendant pid='

fn need(condition bool, message string) ! {
	if !condition { return error(message) }
}

fn control_limits() winejitstream.NativeLimits {
	return winejitstream.NativeLimits{
		timeout_ms:   2000
		file_bytes:   64 * 1024
		total_bytes:  128 * 1024
		log_bytes:    32 * 1024
		serial_bytes: 32 * 1024
		min_free_kib: control_free_kib
	}
}

fn state_bounds(directory string) ! {
	winejitstream.native_require_free(directory, control_free_kib)!
	need(winejitstream.native_state_bytes(directory)! < control_state_limit,
		'host controls reached the 20MiB state ceiling')!
}

fn descendant_gone(directory string, run winejitstream.NativeRun) ! {
	text := os.read_file(directory + '/worker.log')!.trim_space()
	need(text.starts_with(descendant_prefix), 'fixture did not identify its descendant')!
	pid_text := text[descendant_prefix.len..]
	pid := pid_text.int()
	need(pid > 0 && pid.str() == pid_text && pid != run.leader_pid,
		'fixture descendant PID is invalid')!
	need(C.kill(pid, 0) < 0 && C.errno == C.ESRCH, 'fixture descendant survived group cleanup')!
}

fn controls() ! {
	cancel_check := os.args.len == 3 && os.args[1] == '--cancel-check'
	if os.args.len != 2 && !cancel_check {
		return error('usage: wine-fork-jit-stream-native-controls [--cancel-check] NEW_OUTPUT')
	}
	if sha256.hexhash(os.read_file(@FILE)!) != sha256.hexhash($embed_file('wine-fork-jit-stream-native-controls.v').to_string()) {
		return error('compiled native controls source differs')
	}
	output := os.abs_path(os.args[if cancel_check { 2 } else { 1 }])
	if os.exists(output) || os.is_link(output) { return error('control output already exists') }
	if output != os.real_path(os.dir(output)) + '/' + os.file_name(output) {
		return error('control output parent must be canonical')
	}
	winejitstream.native_require_free(os.dir(output), control_free_kib)!
	os.mkdir(output)!
	mut results := map[string]string{}
	mut observations := map[string]winejitstream.NativeRun{}
	self := os.executable()
	limits := control_limits()
	// SIGTERM must be the last fresh control: interrupted state intentionally persists.
	for name in ['success', 'exec-failure', 'timeout-descendant', 'leader-exit-descendant', 'hard-file',
		'log-threshold', 'serial-threshold', 'aggregate-threshold', 'parent-sigterm'] {
		state_bounds(output)!
		directory := output + '/' + name
		os.mkdir(directory)!
		mut command := [self, '--fixture-' + name, directory]
		mut selected := limits
		match name {
			'exec-failure' { command = [output + '/nonexistent-command'] }
			'timeout-descendant' {
				selected = winejitstream.NativeLimits{ ...limits, timeout_ms: if cancel_check {
					5000
				} else {
					250
				} }
			}
			'hard-file' {
				selected = winejitstream.NativeLimits{ ...limits, log_bytes: limits.file_bytes }
			}
			'log-threshold' { selected = winejitstream.NativeLimits{ ...limits, log_bytes: 4096 } }
			'serial-threshold' {
				selected = winejitstream.NativeLimits{ ...limits, serial_bytes: 8192 }
			}
			'aggregate-threshold' {
				selected = winejitstream.NativeLimits{
					...limits
					file_bytes:   16384
					total_bytes:  32768
					log_bytes:    16384
					serial_bytes: 16384
				}
			}
			else {}
		}
		run := winejitstream.native_guard(command, directory, 'worker.log', selected)!
		os.write_file(directory + '/run.json', json2.encode(run))!
		expected_reason := if name == 'parent-sigterm' { 'native guard interrupted' } else { '' }
		need(run.leader_pid > 0 && run.wait_status >= 0 && run.stopped && run.reason == expected_reason,
			name + ': leader/group cleanup was not confirmed')!
		match name {
			'success' {
				need(run.wait_status == 0 && !run.timed_out && !run.size_limited,
					'small successful fixture was refused')!
				need(os.read_file(directory + '/payload.bin')! == 'ok'
					&& os.read_file(directory + '/worker.log')! == 'NATIVE GUARD success\n',
					'successful fixture output differs')!
			}
			'exec-failure' {
				need(run.wait_status == (125 << 8) && !run.timed_out && !run.size_limited,
					'exec failure was not reaped with its expected status')!
			}
			'timeout-descendant' {
				need(run.timed_out && !run.size_limited && run.wait_status != 0,
					'timeout did not terminate the fixture group')!
				descendant_gone(directory, run)!
			}
			'leader-exit-descendant' {
				need(run.wait_status == 0 && !run.timed_out && !run.size_limited,
					'successful leader exit was not retained during descendant cleanup')!
				descendant_gone(directory, run)!
			}
			'hard-file' {
				need(run.size_limited && !run.timed_out
					&& (os.lstat(directory + '/worker.log')!).size == selected.file_bytes,
					'inherited hard per-file limit did not cap the writer')!
				need((run.wait_status & 0x7f) == C.SIGXFSZ || run.wait_status == (91 << 8),
					'fixture did not reach the kernel file-size limit before polling stopped it')!
			}
			'log-threshold' {
				need(run.size_limited && !run.timed_out
					&& (os.lstat(directory + '/worker.log')!).size == 4097,
					'finite ordinary log threshold crossing was admitted')!
			}
			'serial-threshold' {
				need(run.size_limited && !run.timed_out
					&& (os.lstat(directory + '/serial.log')!).size == 8193,
					'finite serial log threshold crossing was admitted')!
			}
			'aggregate-threshold' {
				// The receipt is written after the guard's final byte observation.
				record_bytes := (os.lstat(directory + '/run.json')!).size
				actual := winejitstream.native_state_bytes(directory)! - record_bytes
				need(run.size_limited && !run.timed_out && actual > selected.total_bytes
					&& actual <= 36000 && run.observed_bytes == actual,
					'aggregate threshold crossing or final byte count differs')!
				for entry in os.ls(directory)! {
					need((os.lstat(directory + '/' + entry)!).size < selected.file_bytes,
						'aggregate fixture also crossed a per-file threshold')!
				}
			}
			'parent-sigterm' {
				need(run.wait_status != 0 && !run.timed_out && !run.size_limited,
					'parent SIGTERM did not stop and reap the fixture')!
			}
			else {}
		}
		observations[name] = run
		results[name] = 'PASS'
		state_bounds(output)!
	}
	// Repeated cancellation must also cover children that have not reached exec.
	for attempt in 0 .. 16 {
		state_bounds(output)!
		name := 'pre-cancelled-' + attempt.str()
		directory := output + '/' + name
		os.mkdir(directory)!
		run := winejitstream.native_guard([self, '--fixture-timeout-descendant', directory],
			directory, 'worker.log', limits)!
		os.write_file(directory + '/run.json', json2.encode(run))!
		need(run.leader_pid > 0 && run.wait_status > 0 && run.stopped
			&& run.reason == 'native guard interrupted' && !run.timed_out && !run.size_limited,
			name + ': pre-cancelled guard did not confirm interrupted cleanup')!
		need(C.kill(run.leader_pid, 0) < 0 && C.errno == C.ESRCH,
			name + ': pre-cancelled leader survived cleanup')!
		need(C.kill(-run.leader_pid, 0) < 0 && C.errno == C.ESRCH,
			name + ': pre-cancelled process group survived cleanup')!
		log := directory + '/worker.log'
		if os.exists(log) {
			text := os.read_file(log)!.trim_space()
			if text != '' { descendant_gone(directory, run)! }
		}
		observations[name] = run
		state_bounds(output)!
	}
	results['pre-cancelled'] = 'PASS'
	os.write_file(output + '/results.json', json2.encode({
		'results':                  json2.encode(results)
		'observations':             json2.encode(observations)
		'controller_source_sha256': sha256.hexhash(os.read_file(@FILE)!)
		'controller_binary_sha256': sha256.sum(os.read_bytes(self)!).hex()
		'scope':                    'Host process-group cleanup and disk-admission controls only; no target build, ARM execution, JIT backing or Wine qualification.'
		'limits':                   'The hard ceiling is inherited RLIMIT_FSIZE per file. Smaller log and aggregate thresholds are sampled and may overshoot between polls.'
	}))!
	state_bounds(output)!
	println('PASS ' + results.len.str() + ' standalone native guard controls')
}

fn fixture(mode string, directory string) {
	match mode {
		'success' {
			os.write_file(directory + '/payload.bin', 'ok') or { C._exit(90) }
			text := 'NATIVE GUARD success\n'
			if C.write(1, text.str, usize(text.len)) != text.len { C._exit(90) }
			C._exit(0)
		}
		'timeout-descendant', 'leader-exit-descendant' {
			pid := C.fork()
			if pid < 0 { C._exit(92) }
			if pid == 0 {
				for { C.pause() }
			}
			text := descendant_prefix + pid.str() + '\n'
			if C.write(1, text.str, usize(text.len)) != text.len { C._exit(93) }
			if mode == 'leader-exit-descendant' { C._exit(0) }
			for { C.pause() }
		}
		'hard-file' {
			chunk := 'X'.repeat(4096)
			for { if C.write(2, chunk.str, usize(chunk.len)) <= 0 { C._exit(91) } }
		}
		'log-threshold' {
			text := 'L'.repeat(4097)
			if C.write(1, text.str, usize(text.len)) != text.len { C._exit(94) }
			C._exit(0)
		}
		'serial-threshold' {
			os.write_file(directory + '/serial.log', 'S'.repeat(8193)) or { C._exit(95) }
			C._exit(0)
		}
		'aggregate-threshold' {
			for name in ['a.bin', 'b.bin', 'c.bin'] {
				os.write_file(directory + '/' + name, 'A'.repeat(12000)) or { C._exit(96) }
			}
			C._exit(0)
		}
		'parent-sigterm' {
			if C.kill(C.getppid(), C.SIGTERM) != 0 { C._exit(98) }
			for { C.pause() }
		}
		else { C._exit(97) }
	}
}

fn main() {
	if os.args.len == 3 && os.args[1].starts_with('--fixture-') {
		fixture(os.args[1]['--fixture-'.len..], os.args[2])
		return
	}
	controls() or {
		eprintln(err.msg())
		exit(1)
	}
}
