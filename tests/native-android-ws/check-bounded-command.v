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
fn C.setpgid(int, int) int
fn C.waitpid(int, &int, int) int

struct Result {
	exit_code int
	child_exit_code int
	reason string
	cleanup_complete bool
	pid int
	peak_sampled_rss_bytes u64
	output_bytes u64
	initial_free_bytes u64
	limits ObservedLimits
	supervised_groups []int
}

struct ObservedLimits { reserve u64; growth u64; wall_ms i64 }

fn fixture(mode string) {
	C.alarm(10)
	match mode {
		'literal' { print(os.args[3]); eprint(':stderr'); exit(37) }
		'growth', 'long-wall', 'audit-wall' { exit(0) }
		'flood' { for _ in 0 .. 1024 { print('x'.repeat(8192)) } }
		'wall' { time.sleep(5 * time.second) }
		'leader' {
			pid := C.fork()
			if pid < 0 { exit(70) }
			if pid > 0 { exit(0) }
			time.sleep(5 * time.second)
		}
		'nested-success', 'nested-orphan' {
			pid := C.fork()
			if pid < 0 { exit(70) }
			if pid == 0 {
				if C.setpgid(0, 0) != 0 { exit(72) }
				println('NESTED-GROUP ' + os.getpid().str())
				time.sleep(if mode == 'nested-success' { 300 * time.millisecond } else { 5 * time.second })
				exit(0)
			}
			if mode == 'nested-orphan' { time.sleep(400 * time.millisecond); exit(0) }
			mut status := 0
			if C.waitpid(pid, &status, 0) != pid || status != 0 { exit(73) }
		}
		'rss', 'nested-rss' {
			for _ in 0 .. 2 {
				pid := C.fork()
				if pid < 0 { exit(70) }
				if pid == 0 {
					if mode == 'nested-rss' {
						if C.setpgid(0, 0) != 0 { exit(72) }
						println('NESTED-GROUP ' + os.getpid().str())
					}
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
		if report.limits.growth != 512 * u64(1024 * 1024) { return error('default disk growth budget differs') }
		if report.limits.wall_ms != 300_000 { return error('default wall time differs') }
	} else if mode == 'nested-success' {
		if result.exit_code != 0 || report.exit_code != 0 || report.reason != '' { return error('nested command refused') }
	} else if mode == 'long-wall' {
		if result.exit_code != 0 || report.exit_code != 0 || report.reason != '' || report.limits.wall_ms != 900_000 {
			return error('maximum explicit wall time differs')
		}
	} else if mode == 'audit-wall' {
		if result.exit_code != 0 || report.exit_code != 0 || report.reason != '' || report.limits.wall_ms != 1_800_000 {
			return error('explicit audit wall time differs')
		}
	} else if mode == 'growth' {
		if result.exit_code != 0 || report.exit_code != 0 || report.reason != '' ||
			report.limits.growth != 8 * u64(1024 * 1024 * 1024) ||
			report.initial_free_bytes < report.limits.reserve ||
			report.initial_free_bytes - report.limits.reserve < report.limits.growth {
			return error('maximum backed disk growth budget differs')
		}
	} else if result.exit_code != 125 || report.exit_code != 125 || report.reason != expected {
		return error(mode + ': expected ' + expected + ', got ' + report.reason)
	}
	// An independent ps check also works when policy rejects negative-PID probes.
	if !report.cleanup_complete || report.pid !in report.supervised_groups { return error(mode + ': cleanup not verified') }
	for group_id in report.supervised_groups {
		group := os.exec(['/bin/ps', '-o', 'pgid=', '-g', group_id.str()])
		if group.exit_code !in [0, 1] || group.output.trim_space() != '' { return error(mode + ': process group survived') }
	}
	if mode.starts_with('nested-') {
		mut count := 0
		for line in os.read_file(log)!.split_into_lines() {
			if line.starts_with('NESTED-GROUP ') {
				group_id := line.all_after(' ').int()
				if group_id <= 1 || group_id == report.pid || group_id !in report.supervised_groups {
					return error(mode + ': nested group not supervised')
				}
				count++
			}
		}
		if count != if mode == 'nested-rss' { 2 } else { 1 } { return error('nested group markers missing') }
	}
	if os.exists(root) { return error('runner created producer fresh output root') }
	if mode in ['rss', 'nested-rss'] && report.peak_sampled_rss_bytes <= 48 * 1024 * 1024 { return error('descendant memory was not measured') }
	if mode == 'flood' && (os.file_size(log) != 4096 || report.output_bytes != 4096) { return error('output bound differs') }
	before := os.read_file(receipt)!
	again := os.exec([runner, ...args])
	if again.exit_code != 125 || os.read_file(receipt)! != before { return error('fresh receipt guard failed') }
	println('BOUNDED-COMMAND-CONTROL-PASS ' + mode)
}

fn prewrite_refusal(runner string, out string, label string, options []string, expected string) ! {
	root := out + '/' + label + '-generated'
	log := out + '/' + label + '.child.log'
	receipt := out + '/' + label + '.json'
	spawned := out + '/' + label + '-must-not-run'
	mut args := ['root=' + root, 'log=' + log, 'receipt=' + receipt]
	args << options
	args << ['--', '/usr/bin/touch', spawned]
	result := os.exec([runner, ...args])
	if result.exit_code != 125 || !result.output.contains(expected)
		|| os.exists(root) || os.exists(log) || os.exists(receipt) || os.exists(spawned) {
		return error(label + ': expected prewrite/spawn refusal: ' + expected)
	}
	os.write_file(out + '/' + label + '.refusal.log', result.output)!
}

fn audit_receipt_shape(path string) ! {
	fields := json2.decode[map[string]json2.Any](os.read_file(path)!)!
	if fields.keys().sorted() != ['argv', 'generated_root', 'log', 'limits', 'pid',
		'exit_code', 'child_exit_code', 'reason', 'cleanup_complete', 'elapsed_ms',
		'peak_sampled_rss_bytes', 'rss_samples', 'initial_free_bytes', 'minimum_free_bytes',
		'maximum_observed_disk_growth_bytes', 'output_bytes', 'supervised_groups'].sorted() {
		return error('audit option changed receipt shape')
	}
	limits := json2.decode[map[string]json2.Any](json2.encode(fields['limits']!))!
	if limits.keys().sorted() != ['rss', 'wall_ms', 'reserve', 'growth', 'output'].sorted() {
		return error('audit option changed limits shape')
	}
	for key, value in {'rss': '2147483648', 'wall_ms': '1800000', 'reserve': '1073741824',
		'growth': '536870912', 'output': '4194304'} {
		if json2.encode(limits[key]!) != value { return error('audit option changed resource limit: ' + key) }
	}
}

// Focused configuration/refusal coverage. The immediate audit fixture verifies
// selection, not a thirty-minute wait; the existing short fixture verifies the
// unchanged deadline/cleanup path. This mode does not replace the full suite.
fn audit_wall_controls(runner string, out string) ! {
	if os.exists(out) { return error('fresh output directory required') }
	os.mkdir_all(out)!
	self := os.exec([runner, '--self-test'])
	if self.exit_code != 0 || !self.output.contains('BOUNDED-COMMAND-SELF-PASS') {
		return error('disk budget boundary selftest failed')
	}
	os.write_file(out + '/self-test.log', self.output)!
	control(runner, out, 'literal', []string{}, '')!
	control(runner, out, 'long-wall', ['wall_ms=900000'], '')!
	control(runner, out, 'audit-wall', ['audit_wall_ms=1800000'], '')!
	audit_receipt_shape(out + '/audit-wall.json')!
	mut refusals := 0
	for index, invalid in ['', '0', '1', '900000', '1799999', '1800001', '18000000',
		'01800000', '+1800000', '-1800000', '1800000.0', '1.8e6', '1800000 ', ' 1800000',
		'1800000\n', '1800000\t', '１８０００００', '18446744073709551615',
		'18446744073709551616', '9223372036854775808', '1800000=extra'] {
		prewrite_refusal(runner, out, 'invalid-audit-' + index.str(), ['audit_wall_ms=' + invalid],
			'audit_wall_ms requires exactly 1800000')!
		refusals++
	}
	for index, options in [
		['audit_wall_ms=1800000', 'audit_wall_ms=1800000'],
		['audit_wall_ms=1800000', 'audit_wall_ms=1'],
		['audit_wall_ms=1800000', 'rss=629145600', 'audit_wall_ms=1800000'],
		['wall_ms=300000', 'audit_wall_ms=1800000'],
		['audit_wall_ms=1800000', 'wall_ms=300000'],
		['wall_ms=900000', 'audit_wall_ms=1800000'],
		['audit_wall_ms=1800000', 'wall_ms=900000'],
		['wall_ms=250', 'wall_ms=900000', 'audit_wall_ms=1800000'],
		['audit_wall_ms=1800000', 'wall_ms=250', 'wall_ms=900000'],
	] {
		prewrite_refusal(runner, out, 'exclusive-audit-' + index.str(), options,
			'audit wall setting must be exclusive')!
		refusals++
	}
	for index, invalid in ['900001', '1800000', '18446744073709551615'] {
		prewrite_refusal(runner, out, 'unchanged-standard-' + index.str(), ['wall_ms=' + invalid],
			'wall limit exceeds 900 seconds')!
		refusals++
	}
	control(runner, out, 'wall', ['wall_ms=250'], 'wall time')!
	println('BOUNDED-COMMAND-AUDIT-WALL-PASS scope=wall-option-only default300000 legacy900000 audit1800000 prewrite-refusals=' + refusals.str() + ' exact-receipt unchanged-resources short-timeout cleanup full-suite-separate')
}

fn main() {
	C.alarm(30)
	if os.args.len >= 3 && os.args[1] == '--fixture' { fixture(os.args[2]); return }
	if os.args.len > 1 && os.args[1] == '--audit-wall' {
		if os.args.len != 4 { eprintln('usage: check-bounded-command --audit-wall RUNNER FRESH_EXTERNAL_DIR'); exit(2) }
		audit_wall_controls(os.real_path(os.args[2]), os.args[3]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len != 3 { eprintln('usage: check-bounded-command RUNNER FRESH_EXTERNAL_DIR'); exit(2) }
	runner := os.real_path(os.args[1]); out := os.args[2]
	if os.exists(out) { eprintln('fresh output directory required'); exit(2) }
	os.mkdir_all(out) or { eprintln(err); exit(1) }
	self := os.exec([runner, '--self-test'])
	if self.exit_code != 0 || !self.output.contains('BOUNDED-COMMAND-SELF-PASS') {
		eprintln('disk budget boundary selftest failed'); exit(1)
	}
	os.write_file(out + '/self-test.log', self.output) or { eprintln(err); exit(1) }
	control(runner, out, 'literal', []string{}, '') or { eprintln(err); exit(1) }
	control(runner, out, 'long-wall', ['wall_ms=900000'], '') or { eprintln(err); exit(1) }
	for invalid in ['900001', '18446744073709551615'] {
		receipt := out + '/invalid-wall-' + invalid + '.json'
		refused_wall := os.exec([runner, 'root=' + out + '/absent', 'log=' + out + '/invalid-wall.log',
			'receipt=' + receipt, 'wall_ms=' + invalid, '--', '/usr/bin/true'])
		if refused_wall.exit_code != 125 || os.exists(receipt) || !refused_wall.output.contains('wall limit exceeds 900 seconds') {
			eprintln('oversized wall time accepted'); exit(1)
		}
		os.write_file(out + '/invalid-wall-' + invalid + '.log', refused_wall.output) or { eprintln(err); exit(1) }
	}
	control(runner, out, 'growth', ['growth=8589934592'], '') or { eprintln(err); exit(1) }
	for invalid in ['8589934593', '18446744073709551615'] {
		receipt := out + '/invalid-growth-' + invalid + '.json'
		refused_growth := os.exec([runner, 'root=' + out + '/absent', 'log=' + out + '/invalid-growth.log',
			'receipt=' + receipt, 'growth=' + invalid, '--', '/usr/bin/true'])
		if refused_growth.exit_code != 125 || os.exists(receipt) || !refused_growth.output.contains('invalid resource limit') {
			eprintln('oversized growth budget accepted'); exit(1)
		}
		os.write_file(out + '/invalid-growth-' + invalid + '.log', refused_growth.output) or { eprintln(err); exit(1) }
	}
	control(runner, out, 'flood', ['output=4096'], 'output limit') or { eprintln(err); exit(1) }
	control(runner, out, 'wall', ['wall_ms=250'], 'wall time') or { eprintln(err); exit(1) }
	control(runner, out, 'leader', ['wall_ms=250'], 'wall time') or { eprintln(err); exit(1) }
	control(runner, out, 'rss', ['rss=50331648'], 'aggregate RSS') or { eprintln(err); exit(1) }
	control(runner, out, 'nested-success', []string{}, '') or { eprintln(err); exit(1) }
	control(runner, out, 'nested-orphan', ['wall_ms=800'], 'wall time') or { eprintln(err); exit(1) }
	control(runner, out, 'nested-rss', ['rss=50331648'], 'aggregate RSS') or { eprintln(err); exit(1) }
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
	println('BOUNDED-COMMAND-PASS literal exit37 fresh-root fresh-evidence default-wall max-wall max-wall-refusal backed-growth max-growth-refusal flood wall exited-leader descendant-rss nested-success nested-orphan nested-rss')
}
