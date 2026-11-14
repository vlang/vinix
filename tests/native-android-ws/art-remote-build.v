// SPDX-License-Identifier: GPL-2.0-or-later
// This recovered, isolated ART builder has one serialized compiler workspace.
module main

import json2
import os
import time

struct NativeReceipt {
	cleanup_complete bool
	reason string
	child_exit_code int
}

struct HostReceipt {
	reason string
	cleanup_complete bool
}

fn quoted(args []string) string { return args.map(os.quoted_path(it)).join(' ') }

fn run(job string, target string, fixture bool) ! {
	if job == '' || !job.bytes().all(it.is_alnum() || it in [`-`, `_`])
		|| !target.starts_with('out/host/linux-x86/') || target.contains('..')
		|| !target.bytes().all(it.is_alnum() || it in [`/`, `.`, `-`, `_`]) {
		return error('invalid job or native target')
	}
	state := os.home_dir() + '/.local/state/vinix/android'
	root := '/var/tmp/vinix-art-alpine-20261114-r1'
	work := '/var/tmp/vinix-art-work-20261114-r1'
	source := if fixture { '/work/art-build-stop-fixture-r1' } else {
		'/work/art-build-20261114-r1/art_standalone-e78bf68917bcaaf58fef3960cd88793b3b7f39cc'
	}
	inputs := '/var/tmp/vinix-art-inputs-20261114-r1'
	stem := state + '/art-native-libart-build-20261114-' + job
	if os.exists(stem + '.json') || os.exists(stem + '.log') { return error('job output must be fresh') }
	gate_dir := state + '/art-builder-run.lock'
	os.mkdir(gate_dir)!
	mut release_gate := false
	defer {
		if release_gate { os.rm(gate_dir + '/owner.txt') or {}; os.rmdir(gate_dir) or {} }
	}
	os.write_file(gate_dir + '/owner.txt', 'pid=${os.getpid()} job=${job}\n')!
	ssh := ['/usr/bin/ssh', '-i', os.home_dir() + '/.lima/_config/user', '-p', '22285',
		'-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5', '-o',
		'UserKnownHostsFile=' + state + '/art-builder-guest-20261114-r2/known_hosts', 'alex@127.0.0.1']
	caps := ['rss=629145600', 'reserve=1073741824', 'growth=536870912', 'output=4194304']
	native_log := '/var/tmp/art-native-libart-build-' + job + '.log'
	native_receipt := '/var/tmp/art-native-libart-build-' + job + '.json'
	mut command := ['sudo', '-n', inputs + '/bounded-command', 'root=' + work,
		'log=' + native_log, 'receipt=' + native_receipt,
		'wall_ms=' + if fixture { '10000' } else { '290000' }]
	command << caps
	command << ['--', '/usr/sbin/chroot', root, '/usr/bin/env', 'SOURCE_DATE_EPOCH=1759985629',
		'/usr/bin/make', '-C', source, '-j1', '____PREFIX=/usr', '____LIBDIR=lib',
		'ANDROID_BUILDSPEC=/inputs/art16k-buildspec.mk', 'ART_BUILD_HOST_DEBUG=false', 'showcommands', target]
	mut guarded := [state + '/audit-wall-guard-2026-11-04-r1/tools/bounded-command',
		'root=' + state + '/art-builder-work-disk-20261114-r1', 'log=' + stem + '.log',
		'receipt=' + stem + '.json', 'wall_ms=' + if fixture { '1000' } else { '300000' }]
	// The guest measures this build on its dedicated volume. Host filesystem
	// growth also includes unrelated sessions: bound that separately, with a
	// larger allowance and a stricter free-space floor. Receipts retain both
	// profiles; an earlier failed receipt must never be relabelled as passing.
	guarded << if fixture { caps } else {
		['rss=629145600', 'reserve=8589934592', 'growth=4294967296', 'output=4194304']
	}
	guarded << '--'
	guarded << ssh
	guarded << quoted(command)
	result := os.exec(guarded)
	if result.exit_code != 0 {
		mut stop := ssh.clone()
		stop << quoted(['sudo', '-n', inputs + '/art-builder-fetch', '--stop-build', root, source])
		stopped := os.exec(stop)
		os.write_file(stem + '.stop.log', stopped.output)!
		if stopped.exit_code != 0 { return error('remote stop failed; inspect ' + stem + '.stop.log') }
	}
	mut complete := false
	mut native_reason := ''
	mut native_child := -1
	for _ in 0 .. 50 {
		mut read := ssh.clone()
		read << quoted(['sudo', '-n', '/bin/cat', native_receipt])
		data := os.exec(read)
		if data.exit_code == 0 && data.output.len > 0 {
			receipt := json2.decode[NativeReceipt](data.output) or { return error('invalid native receipt') }
			os.write_file(stem + '.native.json', data.output)!
			complete = receipt.cleanup_complete
			native_reason = receipt.reason
			native_child = receipt.child_exit_code
			break
		}
		time.sleep(100 * time.millisecond)
	}
	if !complete { return error('native cleanup not confirmed; no subsequent job is authorized by this runner') }
	release_gate = true
	mut read := ssh.clone()
	read << quoted(['sudo', '-n', '/bin/cat', native_log])
	log := os.exec(read)
	if log.exit_code != 0 || log.output.len > 4194304 { return error('native log capture failed') }
	os.write_file(stem + '.native.log', log.output)!
	println('ART-REMOTE-BUILD host_exit=${result.exit_code} native_cleanup=true job=${job}')
	if fixture {
		host := json2.decode[HostReceipt](os.read_file(stem + '.json')!)!
		if result.exit_code != 125 || host.reason != 'wall time' || !host.cleanup_complete
			|| native_reason != '' || native_child != 137
			|| !os.read_file(stem + '.stop.log')!.contains('ART-BUILDER-STOP groups=1') {
			return error('expected host timeout and one stopped native session')
		}
		println('ART-REMOTE-CANCELLATION-PASS host budget stopped isolated native worker group')
		return
	}
	if result.exit_code != 0 { return error('guarded native build failed; retained at ' + stem) }
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--self-test' {
		run(os.args[2], 'out/host/linux-x86/control-wait', true) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len !in [2, 3] { eprintln('usage: art-remote-build FRESH_JOB_ID [NATIVE_MAKE_TARGET]'); exit(2) }
	target := if os.args.len == 3 { os.args[2] } else { 'out/host/linux-x86/lib64/libart.so' }
	run(os.args[1], target, false) or { eprintln(err); exit(1) }
}
