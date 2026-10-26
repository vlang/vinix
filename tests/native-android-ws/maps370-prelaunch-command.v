// SPDX-License-Identifier: GPL-2.0-or-later
// Retain the independent Maps370 prelaunch command and its actual child status.
module main

import crypto.sha256
import json2
import os
import time

const state = '/Users/alex/.local/state/vinix/android'
const program = state + '/maps370-prelaunch-review-build-2026-10-26/program'
const program_pin = 'd871020faca0c5b3f88c46de25895924e7958c212457c503064bc61150ca043d'
const prefix = state + '/maps370-independent-prelaunch-review-2026-10-26'

fn hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn canonical(pin string) bool {
	return pin.len == 64 && pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn run() ! {
	assert os.args.len == 3, 'usage: maps370-prelaunch-command PRELAUNCH_SHA LAUNCH_SHA'
	for pin in os.args[1..] {
		assert canonical(pin)
	}
	for suffix in ['.json', '-command.json', '.log', '-recorder.v', '-recorder'] {
		assert !os.exists(prefix + suffix) && !os.is_link(prefix + suffix), 'fresh receipt required'
	}
	assert hash(program)! == program_pin
	argv := [program, '370', os.args[1], os.args[2],
		'd3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1',
		'74e1d74b9ecf51e302f2802a2d291ff15f1d1793495d67c7c108d1d5350a884b',
		'42c7ac8a276a7eb72a3844e94e182aef8ad7df4c2f8f7313f7061527d077b908',
		prefix + '.json']
	os.cp(@FILE, prefix + '-recorder.v')!
	os.cp(os.executable(), prefix + '-recorder')!
	source_pin, binary_pin := hash(@FILE)!, hash(os.executable())!
	started := time.utc().str()
	result := os.exec(argv)
	os.write_file(prefix + '.log', result.output)!
	after := hash(program)!
	os.write_file(prefix + '-command.json', json2.encode({
		'argv': json2.Any(argv)
		'working_directory': json2.Any(os.getwd())
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(result.exit_code)
		'executable_sha256_before': json2.Any(program_pin)
		'executable_sha256_after': json2.Any(after)
		'stdout_stderr_sha256': json2.Any(hash(prefix + '.log')!)
		'recorder_source_sha256': json2.Any(source_pin)
		'recorder_binary_sha256': json2.Any(binary_pin)
		'retained_recorder_source_sha256': json2.Any(hash(prefix + '-recorder.v')!)
		'retained_recorder_binary_sha256': json2.Any(hash(prefix + '-recorder')!)
	}, prettify: true) + '\n')!
	assert result.exit_code == 0 && after == program_pin, result.output
	assert hash(@FILE)! == source_pin && hash(os.executable())! == binary_pin
	receipt := json2.decode[map[string]json2.Any](os.read_file(prefix + '.json')!)!
	assert receipt['exit_code']!.int() == 0
	assert receipt['exact_typed_prelaunch_inventories']!.bool()
	assert receipt['complete_framework369_367_365_361_359_353_chain']!.bool()
	assert receipt['unchanged_observation_seconds']!.int() == 600
	println('MAPS370-INDEPENDENT-PRELAUNCH actual_exit=0 receipt_sha256=' + hash(prefix + '.json')!
		+ ' command_sha256=' + hash(prefix + '-command.json')! + ' log_sha256=' + hash(prefix + '.log')!)
	println(result.output.trim_space())
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
