// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import epollfilecheck
import guesthost
import hosttest
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn run() ! {
	options := guesthost.parse(os.args[1..], [
		hosttest.Option{name: '--arch', value: true, choices: ['aarch64', 'x86_64']},
		hosttest.Option{name: '--kernel-dir', value: true},
		hosttest.Option{name: '--state-dir', value: true},
		hosttest.Option{name: '--case', value: true, choices: ['epollfile', 'pollasync']},
	], [], 'Usage: run-epollfile.v --arch aarch64|x86_64 --kernel-dir DIR --state-dir FRESH-DIR')!
	for key in ['--arch', '--kernel-dir', '--state-dir'] {
		if !options.has(key) { return error('Missing ' + key) }
	}
	arch := options.value('--arch', '')
	case_name := options.value('--case', 'epollfile')
	state := options.value('--state-dir', '')
	if os.exists(state) { return error('State directory must be fresh') }
	kernel := os.read_bytes(options.value('--kernel-dir', '') + '/bin/vinix')!
	if kernel.len < 20 || kernel[..6] != [u8(127), `E`, `L`, `F`, 2, 1]
		|| int(kernel[18]) + (int(kernel[19]) << 8) != if arch == 'aarch64' { 183 } else { 62 } {
		return error('Kernel must be a matching little-endian ELF64')
	}
	os.mkdir_all(state + '/kernel/bin')!
	os.mkdir_all(state + '/source/' + case_name + 'fixture')!
	os.write_file_array(state + '/kernel/bin/vinix', kernel)!
	source := os.read_bytes(os.dir(@FILE) + '/' + case_name + 'fixture/core.v')!
	os.write_file_array(state + '/source/' + case_name + 'fixture/core.v', source)!
	os.write_file(state + '/inputs.json', json2.encode({
		'kernel': sha256.sum(kernel).hex(), 'source': sha256.sum(source).hex(),
	}, prettify: true) + '\n')!
	init := guesthost.compile_init(state + '/source/' + case_name + 'fixture/core.v', state, arch, false)!
	archive := guesthost.image(init, state)!
	launch := guesthost.launch(init, archive, state, state + '/kernel', arch, true)!
	os.write_file(state + '/command.json', json2.encode(launch.command, prettify: true) + '\n')!
	marker := 'LINUX ' + case_name.to_upper()
	result := guesthost.boot_session(launch.command, launch.env, state, guesthost.SessionPolicy{
		pass: marker + ': PASS'
		failures: [marker + ' FAIL', marker + ': FAIL', marker + ' MISMATCH', 'KERNEL PANIC', 'FATAL EXCEPTION']
		settle: 1
		log: state + '/live.log'
	}, 600, true)!
	mut reason := ''
	if case_name == 'epollfile' {
		epollfilecheck.verify(result.text, arch, false, false) or { reason = err.msg() }
	} else {
		actual := result.text.split_into_lines().map(it.trim_space()).filter(it.starts_with(marker))
		if actual != ['LINUX POLLASYNC CASE: vmpressure PASS', 'LINUX POLLASYNC CASE: cgroup PASS',
			'LINUX POLLASYNC CASE: virtual-files PASS', 'LINUX POLLASYNC CASE: pidfd PASS',
			'LINUX POLLASYNC SUMMARY: cases=4 failures=0', 'LINUX POLLASYNC: PASS'] { reason = 'Incomplete asynchronous readiness checks' }
	}
	passed := reason == '' && result.finished && result.passed && result.status == 0
	os.write_file(state + '/receipt.json', json2.encode({
		'architecture': json2.Any(arch), 'passed': passed, 'reason': reason,
		'kernel': sha256.sum(kernel).hex(), 'source': sha256.sum(source).hex(),
		'probe': digest(init)!, 'serial': digest(state + '/serial.log')!,
	}, prettify: true) + '\n')!
	if !passed { return error(if reason != '' { reason } else { 'Guest failed' }) }
	println('Linux ' + case_name + ': PASS ' + arch)
}
fn main() { run() or { eprintln(err.msg()); exit(1) } }
