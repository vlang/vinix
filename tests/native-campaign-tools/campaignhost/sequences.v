// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import cachecli
import json2
import os
import sourcecommand
import time

pub fn sequential_commands(commands [][]string, environment map[string]string, directory string) !int {
	if directory != os.getwd() { return error('sequential command directory must be the current directory') }
	for command in commands {
		cachecli.checkpoint()!
		approved := native_command(command)!
		if approved != command { return error('sequence requires an explicit native command') }
		wait := Wait{started: time.sys_mono_now()}
		result := sourcecommand.run_owned(command, environment, cachecli.cancelled, wait_child, unsafe { &wait })!
		if result.status != 0 { return result.status }
	}
	return 0
}

pub fn correctness_driver(context Context, arch string) !int {
	if arch !in ['aarch64', 'x86_64'] { return error('invalid correctness architecture') }
	base := context.root + '/third_party/useralloc-libc/build/useralloc'
	mut commands := [][]string{}
	if arch == 'aarch64' {
		state := context.root + '/build/useralloc-arm-v6-final'
		for operation in ['prepare-arm-v6', 'arm-v6'] {
			commands << command_with_origin(operation, state + '/native-driver', ['--root', context.root, '--state-dir', state])
		}
	} else {
		for action in [['prepare'], ['run', context.root + '/build/useralloc-kernel-speed-v5/x86_64/vinix-x86_64']] {
			commands << command_with_origin('x86-v6', base + '/verify-x86-v6-final', ['--root', context.root, ...action])
		}
	}
	commands << command_with_origin('collect-verification', base + '/collect-v6-verification', ['--root', context.root, '--arch', arch])
	return sequential_commands(commands, os.environ(), os.getwd())!
}

pub fn final_controller(context Context) !int {
	command := command_with_origin('cohorts-v6', context.root + '/build/useralloc-v6-final-cohorts', ['--root', context.root])
	started := now()
	status := logged_grace(command, context.root + '/build/useralloc-v6-final-cohorts.driver.log', os.environ(), context.root, '', 15)!
	write_json(context.root + '/build/useralloc-v6-final-cohorts.exit.json', {
		'argv': json2.Any(command.map(json2.Any(it)))
		'started_utc': json2.Any(started)
		'finished_utc': json2.Any(now())
		'exit_code': json2.Any(status)
	})!
	return status
}

pub fn settlement_after_core(context Context) !int {
	base := context.root + '/build/useralloc-socket-operations-v3'
	core := context.root + '/build/useralloc-arm-core-final-v5/run.json'
	for {
		cachecli.checkpoint()!
		record := read_json(core)!
		if 'finished_utc' in record {
			if !is_zero(record['exit_code']!) { return error('core failed; no supplementary ARM guest launched') }
			break
		}
		time.sleep(250 * time.millisecond)
	}
	mut results := []json2.Any{}
	mut passed := true
	for name in ['settlement-candidate', 'settlement-baseline'] {
		kernel := context.root + if name == 'settlement-candidate' { '/third_party/useralloc-vm-next/kernel' } else { '/third_party/useralloc-audit-baseline-v3/kernel' }
		state := base + '/' + name
		command := command_with_origin('socket-probe', context.origin, ['--root', context.root, '--state-dir', state, 'settlement', kernel])
		status := logged_grace(command, state + '/output.log', os.environ(), '', '', 15)!
		results << json2.Any({'name': json2.Any(name), 'exit_code': json2.Any(status)})
		write_json(base + '/settlement-exit.json', results)!
		println(name + ' ' + status.str())
		flush_stdout()
		if status != 0 { passed = false }
	}
	return if passed { 0 } else { 1 }
}
