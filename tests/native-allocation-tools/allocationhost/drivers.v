// SPDX-License-Identifier: GPL-2.0-or-later
module allocationhost

import cachecli
import hosttest
import json2
import os
import sourcecommand
import time

pub fn utc_text(stamp time.Time) string {
	base := '${stamp.year:04d}-${stamp.month:02d}-${stamp.day:02d}T${stamp.hour:02d}:${stamp.minute:02d}:${stamp.second:02d}'
	micro := stamp.nanosecond / 1000
	return base + if micro == 0 { '' } else { '.${micro:06d}' } + '+00:00'
}

fn joined(parent string, child string) string {
	return if child.starts_with('/') { child } else { parent.trim_right('/') + '/' + child }
}

pub fn saved_driver(argv []string, origin string, macos bool) int {
	args := cachecli.arguments(argv, []string{}, []string{}, []string{}, if macos { 1 } else { 3 }, if macos {
		1
	} else {
		3
	},
		if macos {
			'usage: macos-driver RUN_NAME'
		} else {
			'usage: vinix-driver RUN_NAME LIBC_VARIANT KERNEL'
		}) or {
		eprintln(err)
		return 2
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	return driver_options(args.positional, origin, macos) or { return status(err) }
}

fn driver_options(args []string, origin string, macos bool) !int {
	base := os.dir(os.dir(resolve(origin)!))
	state := joined(base + '/build', args[0])
	mut command := []string{}
	if macos {
		// The current executable contains the complete serial/QMP observer;
		// its lifetime outlasts this owned child, including temporary fronts.
		command = [os.executable(), 'measure', state, '--runtime',
			base + '/build/useralloc-macos-runtime', '--config',
			base + '/tests/alloc-bench/results/2026-10-02/user-macos/config.json']
	} else {
		kernel := resolve(args[2])!
		if !os.is_file(kernel) { return error('kernel missing: ' + kernel) }
		command = [os.executable(), 'vinix', '--kernel', kernel, '--sysroot',
			joined(base + '/third_party/useralloc-libc/build/useralloc', args[1]), '--state-dir',
			state, '--iterations', '200000', '--samples', '7', '--timeout', '3600']
	}
	started := utc_text(time.utc())
	log := hosttest.replace_suffix(state, '.runner.log')
	context := CommandDeadline{-1, time.sys_mono_now()}
	result := sourcecommand.run_logged_owned(command, os.environ(), cachecli.cancelled, log, false, base, wait_command, unsafe { &context }, 0)!
	write_json(hosttest.replace_suffix(state, '.exit.json'), {
		'argv':         json2.Any(command.map(json2.Any(it)))
		'started_utc':  json2.Any(started)
		'finished_utc': json2.Any(utc_text(time.utc()))
		'exit_code':    json2.Any(result.status)
	})!
	return result.status
}
