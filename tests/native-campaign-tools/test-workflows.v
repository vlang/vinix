// SPDX-License-Identifier: GPL-2.0-or-later
module main

import campaignhost
import hosttest
import json2
import os
import time

fn entry_cases() ! {
	entries := campaignhost.saved_entries()!
	assert entries.len == 45
	for path, selector in entries {
		args := if selector.str() == 'collect-verification' { ['aarch64'] } else { []string{} }
		actual := campaignhost.saved_arguments(['saved', hosttest.root() + '/' + path, ...args])!
		assert actual[0] == selector.str() && actual[1] == hosttest.root() + '/' + path
		if args.len > 0 { assert actual[2..] == ['--arch', 'aarch64'] }
	}
	mut unknown := false
	campaignhost.saved_arguments(['saved', hosttest.root() + '/unknown-native-entry']) or { unknown = true }
	assert unknown
	assert campaignhost.saved_arguments(['core-recorded', '/example/origin'])! == ['core-recorded', '/example/origin']
}

fn gates(work string) ! {
	os.mkdir(work)!
	for gate in campaignhost.readiness_gates() {
		path := work + '/' + gate.path
		campaignhost.mkdirs(os.dir(path))!
		hosttest.write_json(path, {gate.field: gate.expected})!
	}
	assert campaignhost.inspect_gates(work, campaignhost.readiness_gates())!.len == 16
	for gate in campaignhost.readiness_gates() {
		path := work + '/' + gate.path
		original := os.read_bytes(path)!
		for mutation in [json2.Any('FAIL'), json2.Any(u64(4294967296)), json2.Any(json2.Null{})] {
			hosttest.write_json(path, {gate.field: mutation})!
			mut refused := false
			campaignhost.inspect_gates(work, campaignhost.readiness_gates()) or { refused = true }
			assert refused, gate.path
		}
		os.write_file_array(path, original)!
	}
	assert campaignhost.gate_passed(json2.Any(false), json2.Any(u64(0)))
	assert campaignhost.gate_passed(json2.Any(u64(1)), json2.Any(true))
	assert !campaignhost.gate_passed(json2.Any('0'), json2.Any(u64(0)))
}

fn sequence(work string) ! {
	os.mkdir(work)!
	for failure in [false, true] {
		path := work + '/' + failure.str()
		commands := [[os.executable(), '--step', path, 'first', '0'], [os.executable(), '--step', path, 'second', if failure { '7' } else { '0' }], [os.executable(), '--step', path, 'third', '0']]
		assert campaignhost.sequential_commands(commands, os.environ(), os.getwd())! == if failure { 7 } else { 0 }
		assert os.read_file(path)!.split_into_lines() == if failure { ['first', 'second'] } else { ['first', 'second', 'third'] }
	}
}

fn diagnostic(work string) ! {
	os.mkdir(work)!
	for mode in ['complete', 'failure', 'exit'] {
		state := work + '/' + mode
		os.mkdir(state)!
		os.mkdir(state + '/boot-1')!
		context := campaignhost.Context{root: hosttest.root(), state: state, origin: state + '/origin'}
		record := map[string]json2.Any{'ordinal': json2.Any(u64(1)), 'status': json2.Any('booting')}
		mut checkpoint := map[string]json2.Any{'boots': json2.Any([json2.Any(record)])}
		mut failed := false
		campaignhost.diagnostic_command(context, 1, [os.executable(), '--diagnostic', mode, state + '/boot-1/serial.log'], record, mut checkpoint) or { failed = true }
		assert failed == (mode != 'complete')
		actual := checkpoint['boots']!.as_array()[0].as_map()
		assert actual['qemu_exit_code']!.int() == if mode == 'exit' { 7 } else { -15 }, actual.str()
		assert actual['qemu_stopped_utc']!.str().ends_with('+00:00')
		pid := os.read_file(state + '/boot-1/qemu.pid')!.int()
		assert C.kill(pid, 0) != 0, 'diagnostic leader survived retirement'
	}
}

fn qualify(work string) ! {
	os.mkdir(work)!
	entry_cases()!
	gates(work + '/gates')!
	sequence(work + '/sequences')!
	diagnostic(work + '/diagnostic')!
	os.write_file(work + '/passed', 'PASS\n')!
	println('45 ENTRYPOINTS / sixteen readiness gates and 48 independent mutations / ordered actual children and stop on failure / diagnostic success, failure, early exit and signed retirement status: PASS')
	flush_stdout()
}

fn main() {
	if os.args.len == 5 && os.args[1] == '--step' {
		mut file := os.open_file(os.args[2], 'a') or { eprintln(err); exit(1) }
		file.write_string(os.args[3] + '\n') or { eprintln(err); exit(1) }
		file.close()
		exit(os.args[4].int())
	}
	if os.args.len == 4 && os.args[1] == '--diagnostic' {
		if os.args[2] == 'exit' { os.write_file(os.args[3], 'early exit\n') or { exit(1) }; exit(7) }
		output := if os.args[2] == 'failure' { 'DIAG-FAIL\n' } else { 'DIAG-GUEST-DONE\n' + 'DIAG-SAMPLER-DONE exit_code=0\n'.repeat(6) + 'DIAG-HOT sample=controlled\n'.repeat(84) }
		os.write_file(os.args[3], output) or { exit(1) }
		for { time.sleep(10 * time.millisecond) }
	}
	if os.args.len != 2 { eprintln('usage: test-workflows NEW_STATE'); exit(2) }
	qualify(os.args[1]) or { eprintln(err); exit(1) }
}
