// SPDX-License-Identifier: GPL-2.0-or-later
// Small real process controls, never a native build or VM.
module main

import json2
import os
import time

#include <signal.h>
#include <unistd.h>

fn C.fork() int
fn C.alarm(u32) u32

struct Result {
	exit_code int
	child_exit_code int
	reason string
	cleanup_complete bool
	pid int
	peak_sampled_rss_bytes u64
	output_bytes u64
}

fn fixture(mode string) {
	C.alarm(10)
	match mode {
		'literal' { print(os.args[3]); eprint(':stderr'); exit(37) }
		'flood' { for _ in 0 .. 1024 { print('x'.repeat(8192)) } }
		'wall' { time.sleep(5 * time.second) }
		'leader' {
			pid := C.fork()
			if pid < 0 { exit(70) }
			if pid > 0 { exit(0) }
			time.sleep(5 * time.second)
		}
		'rss' {
			for _ in 0 .. 2 {
				pid := C.fork()
				if pid < 0 { exit(70) }
				if pid == 0 {
					mut data := []u8{len: 32 * 1024 * 1024, init: 42}
					time.sleep(5 * time.second)
					println(data[os.getpid() % data.len])
					exit(0)
				}
			}
			time.sleep(5 * time.second)
		}
		else { exit(71) }
	}
}

fn control(runner string, out string, mode string, options []string, expected string) ! {
	root := out + '/' + mode + '-generated'
	log := out + '/' + mode + '.log'
	receipt := out + '/' + mode + '.json'
	mut args := ['root=' + root, 'log=' + log, 'receipt=' + receipt]
	args << options
	args << ['--', os.executable(), '--fixture', mode]
	if mode == 'literal' { args << 'literal $(no-shell) `no-shell` $HOME' }
	result := os.exec([runner, ...args])
	report := json2.decode[Result](os.read_file(receipt)!)!
	if mode == 'literal' {
		if result.exit_code != 37 || report.exit_code != 37 || report.child_exit_code != 37 ||
			os.read_file(log)! != 'literal $(no-shell) `no-shell` $HOME:stderr' {
			return error('literal argv, merged output or exit code differs')
		}
	} else if result.exit_code != 125 || report.exit_code != 125 || report.reason != expected {
		return error(mode + ': expected ' + expected + ', got ' + report.reason)
	}
	// An independent ps check also works when policy rejects negative-PID probes.
	group := os.exec(['/bin/ps', '-o', 'pgid=', '-g', report.pid.str()])
	if !report.cleanup_complete || group.exit_code !in [0, 1] || group.output.trim_space() != '' {
		return error(mode + ': process group survived')
	}
	if os.exists(root) { return error('runner created producer fresh output root') }
	if mode == 'rss' && report.peak_sampled_rss_bytes <= 48 * 1024 * 1024 { return error('descendant memory was not measured') }
	if mode == 'flood' && (os.file_size(log) != 4096 || report.output_bytes != 4096) { return error('output bound differs') }
	before := os.read_file(receipt)!
	again := os.exec([runner, ...args])
	if again.exit_code != 125 || os.read_file(receipt)! != before { return error('fresh receipt guard failed') }
	println('BOUNDED-COMMAND-CONTROL-PASS ' + mode)
}

fn main() {
	C.alarm(30)
	if os.args.len >= 3 && os.args[1] == '--fixture' { fixture(os.args[2]); return }
	if os.args.len != 3 { eprintln('usage: check-bounded-command RUNNER FRESH_EXTERNAL_DIR'); exit(2) }
	runner := os.real_path(os.args[1]); out := os.args[2]
	if os.exists(out) { eprintln('fresh output directory required'); exit(2) }
	os.mkdir_all(out) or { eprintln(err); exit(1) }
	control(runner, out, 'literal', []string{}, '') or { eprintln(err); exit(1) }
	control(runner, out, 'flood', ['output=4096'], 'output limit') or { eprintln(err); exit(1) }
	control(runner, out, 'wall', ['wall_ms=250'], 'wall time') or { eprintln(err); exit(1) }
	control(runner, out, 'leader', ['wall_ms=250'], 'wall time') or { eprintln(err); exit(1) }
	control(runner, out, 'rss', ['rss=50331648'], 'aggregate RSS') or { eprintln(err); exit(1) }
	// An existing log alone must survive even when the receipt is fresh.
	sentinel := out + '/existing.log'
	os.write_file(sentinel, 'retained-sentinel') or { eprintln(err); exit(1) }
	refused := os.exec([runner, 'root=' + out + '/absent', 'log=' + sentinel,
		'receipt=' + out + '/existing-log.json', '--', '/usr/bin/true'])
	if refused.exit_code != 125 || (os.read_file(sentinel) or { '' }) != 'retained-sentinel' {
		eprintln('existing log was not preserved'); exit(1)
	}
	// Initial reserve refusal must happen before the fixture can run.
	reserve := os.exec([runner, 'root=' + out + '/absent', 'log=' + out + '/reserve.log',
		'receipt=' + out + '/reserve.json', 'reserve=18446744073709551615', '--', '/usr/bin/true'])
	reserve_report := json2.decode[Result](os.read_file(out + '/reserve.json') or { eprintln(err); exit(1) }) or { eprintln(err); exit(1) }
	if reserve.exit_code != 125 || reserve_report.pid != 0 || reserve_report.reason != 'disk reserve' {
		eprintln('initial disk reserve did not refuse before spawn'); exit(1)
	}
	println('BOUNDED-COMMAND-PASS literal exit37 fresh-root fresh-evidence flood wall exited-leader descendant-rss')
}
